@testable import brower_server
import AsyncHTTPClient
import Foundation
import NIOCore
import Vapor
import XCTest

final class BrowserAIStreamTests: XCTestCase {
    func testSSEFramingAcrossEveryByteBoundary() throws {
        let source = ": heartbeat\r\ndata: first\r\ndata: café\r\n\r\ndata: [DONE]\n\n"
        var parser = BrowserSSEParser()
        var events: [String] = []
        for byte in source.utf8 {
            events += try parser.feed(ByteBuffer(bytes: [byte]))
        }
        XCTAssertEqual(events, ["first\ncafé", "[DONE]"])
    }

    func testSSERejectsOversizedEvents() throws {
        var parser = BrowserSSEParser()
        XCTAssertThrowsError(try parser.feed(ByteBuffer(string: "data: " + String(repeating: "a", count: 65_537) + "\n\n")))
    }

    func testSnapshotsAndRepeatedUsageFinishReason() throws {
        var decoder = OpenRouterStreamDecoder()
        XCTAssertEqual(try decoder.consume(chunk("Hello"))?.text, "Hello")
        XCTAssertEqual(try decoder.consume(chunk(" world"))?.text, "Hello world")
        XCTAssertNil(try decoder.consume(chunk("", reason: "stop")))
        XCTAssertNil(try decoder.consume(chunk("", reason: "stop")))
        let final = try decoder.consume("[DONE]")
        XCTAssertEqual(final?.text, "Hello world")
        XCTAssertEqual(final?.isFinal, true)
        XCTAssertTrue(decoder.isComplete)
    }

    func testStreamRejectsMalformedTruncatedAndErrorEvents() throws {
        for data in ["not-json", "[DONE]", chunk("partial", reason: "length"), "{\"error\":{\"message\":\"secret-provider-detail\"}}"] {
            var decoder = OpenRouterStreamDecoder()
            XCTAssertThrowsError(try decoder.consume(data))
        }
    }

    func testStreamingProxyProducesSnapshotsAndFinalEvent() async throws {
        let service = BrowserAIService(apiKey: "server-test-key", allowedModels: ["openai/gpt-4o-mini"])
        let upstream = "data: \(chunk("Hello"))\n\ndata: \(chunk(" world", reason: "stop"))\n\ndata: [DONE]\n\n"
        let response = try await service.stream(body(), subject: "user") { request in
            XCTAssertEqual(request.url, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.headers.bearerAuthorization?.token, "server-test-key")
            return HTTPClientResponse(headers: ["Content-Type": "text/event-stream"], body: .bytes(ByteBuffer(string: upstream)))
        }
        XCTAssertEqual(response.headers.first(name: "X-Accel-Buffering"), "no")
        let collected = try await response.body.collect(on: MultiThreadedEventLoopGroup.singleton.next()).get()
        var parser = BrowserSSEParser()
        let events = try parser.feed(XCTUnwrap(collected)).map {
            try JSONDecoder().decode(BrowserAIStreamEvent.self, from: Data($0.utf8))
        }
        XCTAssertEqual(events.compactMap(\.text), ["Hello", "Hello world", "Hello world"])
        XCTAssertEqual(events.compactMap(\.isFinal), [false, false, true])
    }

    func testMidstreamFailureIsSanitizedAndHasNoFinalEvent() async throws {
        let service = BrowserAIService(apiKey: "server-test-key", allowedModels: ["openai/gpt-4o-mini"])
        for suffix in ["", "data: {\"error\":{\"message\":\"secret-provider-detail\"}}\n\n"] {
            let upstream = "data: \(chunk("partial"))\n\n" + suffix
            let response = try await service.stream(body(), subject: "user") { _ in
                HTTPClientResponse(headers: ["Content-Type": "text/event-stream"], body: .bytes(ByteBuffer(string: upstream)))
            }
            let collected = try await response.body.collect(on: MultiThreadedEventLoopGroup.singleton.next()).get()
            let buffer = try XCTUnwrap(collected)
            let wire = String(decoding: buffer.readableBytesView, as: UTF8.self)
            XCTAssertFalse(wire.contains("secret-provider-detail"))
            var parser = BrowserSSEParser()
            let events = try parser.feed(buffer).map {
                try JSONDecoder().decode(BrowserAIStreamEvent.self, from: Data($0.utf8))
            }
            XCTAssertEqual(events.last?.error, "Cloud AI generation failed.")
            XCTAssertFalse(events.contains { $0.isFinal == true })
        }
    }

    func testStreamingAndSingleResponseShareQuota() async throws {
        let service = BrowserAIService(apiKey: "test-key", allowedModels: ["openai/gpt-4o-mini"])
        for _ in 0..<10 {
            do {
                _ = try await service.stream(body(), subject: "user") { _ in
                    HTTPClientResponse(status: .serviceUnavailable)
                }
                XCTFail("Expected an upstream failure.")
            } catch let error as Abort {
                XCTAssertEqual(error.status, .badGateway)
            }
        }
        do {
            _ = try await service.stream(body(), subject: "user") { _ in
                XCTFail("Quota failure must not contact the provider.")
                return HTTPClientResponse()
            }
            XCTFail("Expected quota rejection.")
        } catch let error as Abort {
            XCTAssertEqual(error.status, .tooManyRequests)
        }
        let singleClient = AIClient(status: .serviceUnavailable)
        do {
            _ = try await service.generate(body(), subject: "user", client: singleClient)
            XCTFail("Both response modes must share the account quota.")
        } catch let error as Abort {
            XCTAssertEqual(error.status, .tooManyRequests)
        }
        XCTAssertNil(singleClient.lastRequest)
        // A different account can still reserve a request after upstream failures release concurrency slots.
        do {
            _ = try await service.stream(body(), subject: "other-user") { _ in
                HTTPClientResponse(status: .tooManyRequests)
            }
            XCTFail("Expected provider rate limiting.")
        } catch let error as Abort {
            XCTAssertEqual(error.status, .tooManyRequests)
        }
    }

    private func body() -> BrowserAIRequest {
        BrowserAIRequest(modelID: "openai/gpt-4o-mini", instructions: "Answer briefly", prompt: "Hello", maximumResponseTokens: 128)
    }

    private func chunk(_ text: String, reason: String? = nil) -> String {
        let encoded = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        let finish = reason.map { "\"\($0)\"" } ?? "null"
        return "{\"choices\":[{\"delta\":{\"content\":\(encoded)},\"finish_reason\":\(finish)}]}"
    }
}
