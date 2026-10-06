@testable import brower_server
import Foundation
import NIOCore
import Vapor
import XCTest

final class BrowserAITests: XCTestCase {
    private let model = "openai/gpt-4o-mini"

    func testRequestLimitsAndModelAllowlist() throws {
        let models: Set<String> = [model]
        XCTAssertNoThrow(try body().validate(allowedModels: models))
        XCTAssertThrowsError(try body(model: "unapproved/model").validate(allowedModels: models))
        XCTAssertThrowsError(try body(prompt: " \n ").validate(allowedModels: models))
        XCTAssertNoThrow(try body(prompt: String(repeating: "a", count: 200_000)).validate(allowedModels: models))
        XCTAssertThrowsError(try body(prompt: String(repeating: "a", count: 16_777_217)).validate(allowedModels: models))
        XCTAssertThrowsError(try body(tokens: 0).validate(allowedModels: models))
        XCTAssertThrowsError(try body(tokens: 2_049).validate(allowedModels: models))
    }

    func testImagesReachProviderAndAreValidated() async throws {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let image = BrowserAIImage(name: "diagram.png", mediaType: "image/png", data: png)
        let body = BrowserAIRequest(modelID: model, instructions: "Describe it", prompt: "What is shown?", maximumResponseTokens: 128, images: [image])
        let client = AIClient(responseText: "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"A diagram\"}}]}")
        let service = BrowserAIService(apiKey: "test-key", allowedModels: [model])
        _ = try await service.generate(body, subject: "user", client: client)
        let request = try XCTUnwrap(client.lastRequest)
        let buffer = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer.readableBytesView)) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "What is shown?")
        XCTAssertEqual((parts.last?["image_url"] as? [String: String])?["url"], "data:image/png;base64," + png.base64EncodedString())
        let invalid = BrowserAIRequest(modelID: model, instructions: "Describe", prompt: "Question", maximumResponseTokens: 128, images: [.init(name: "bad.png", mediaType: "image/png", data: Data("not an image".utf8))])
        XCTAssertThrowsError(try invalid.validate(allowedModels: [model]))
    }

    func testAIEndpointRequiresVerifiedSession() async throws {
        let app = try await Application.make(.testing)
        do {
            app.browserAuthentication = try await BrowserAuthentication.make(for: .testing)
            try routes(app)
            for path in ["/v1/ai/generate", "/v1/ai/stream"] {
                for token in [nil, "invalid-session"] as [String?] {
                    let request = Request(
                        application: app,
                        method: .POST,
                        url: URI(string: path),
                        on: app.eventLoopGroup.next()
                    )
                    if let token {
                        request.headers.bearerAuthorization = BearerAuthorization(token: token)
                    }
                    try request.content.encode(body())
                    let response = try await app.responder.respond(to: request).get()
                    XCTAssertEqual(response.status, .unauthorized)
                }
            }
            try await app.asyncShutdown()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }

    func testProviderRequestAndResponseContract() async throws {
        let client = AIClient(responseText: "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"A useful filename\"}}]}")
        let service = BrowserAIService(apiKey: "server-only-test-key", allowedModels: [model])
        let response = try await service.generate(body(), subject: "user", client: client)
        XCTAssertEqual(response.text, "A useful filename")
        let request = try XCTUnwrap(client.lastRequest)
        XCTAssertEqual(request.url.string, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.headers.bearerAuthorization?.token, "server-only-test-key")
        let data = Data(try XCTUnwrap(request.body).readableBytesView)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, model)
        XCTAssertEqual(json["max_tokens"] as? Int, 128)
        XCTAssertEqual((json["reasoning"] as? [String: String])?["effort"], "low")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "Name this download")
        XCTAssertNil(json["apiKey"])
    }

    func testAIEndpointAcceptsVerifiedSession() async throws {
        let app = try await Application.make(.testing)
        do {
            let authentication = try await BrowserAuthentication.make(for: .testing)
            let client = AIClient(responseText: "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"Annual Report\"}}]}")
            app.clients.use { _ in client }
            let authenticated = app.grouped("v1")
                .grouped(BrowserSessionAuthenticator(authentication: authentication))
                .grouped(AuthenticatedBrowserUser.guardMiddleware())
            aiRoutes(authenticated, service: BrowserAIService(apiKey: "test-key", allowedModels: [model]))
            let session = try await authentication.issueSession(for: "signed-in-user")
            let request = Request(
                application: app,
                method: .POST,
                url: "/v1/ai/generate",
                on: app.eventLoopGroup.next()
            )
            request.headers.bearerAuthorization = BearerAuthorization(token: session.token)
            try request.content.encode(body())
            let response = try await app.responder.respond(to: request).get()
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(try response.content.decode(BrowserAIResponse.self).text, "Annual Report")
            try await app.asyncShutdown()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }

    func testMissingKeyAndProviderErrorsAreSanitized() async throws {
        let client = AIClient(status: .unauthorized, responseText: "private-provider-error")
        let disabled = BrowserAIService(apiKey: nil, allowedModels: [model])
        await expectStatus(.serviceUnavailable) {
            _ = try await disabled.generate(self.body(), subject: "user", client: client)
        }
        XCTAssertNil(client.lastRequest)
        let service = BrowserAIService(apiKey: "server-only-test-key", allowedModels: [model])
        await expectStatus(.badGateway) {
            _ = try await service.generate(self.body(), subject: "user", client: client)
        }
    }

    func testEmptyMalformedAndTruncatedResponsesAreRejected() async throws {
        for text in [
            "not-json",
            "{\"choices\":[]}",
            "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\" \"}}]}",
            "{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"partial\"}}]}"
        ] {
            let service = BrowserAIService(apiKey: "test-key", allowedModels: [model])
            let client = AIClient(responseText: text)
            await expectStatus(.badGateway) {
                _ = try await service.generate(self.body(), subject: "user", client: client)
            }
        }
    }

    func testUsageLimitCountsAttemptsAndSeparatesUsers() async throws {
        let service = BrowserAIService(apiKey: "test-key", allowedModels: [model])
        let client = AIClient(status: .serviceUnavailable)
        for _ in 0..<10 {
            await expectStatus(.badGateway) {
                _ = try await service.generate(self.body(), subject: "first-user", client: client)
            }
        }
        await expectStatus(.tooManyRequests) {
            _ = try await service.generate(self.body(), subject: "first-user", client: client)
        }
        await expectStatus(.badGateway) {
            _ = try await service.generate(self.body(), subject: "second-user", client: client)
        }
    }

    private func body(model: String = "openai/gpt-4o-mini", prompt: String = "Name this download", tokens: Int = 128) -> BrowserAIRequest {
        BrowserAIRequest(modelID: model, instructions: "Return a filename", prompt: prompt, maximumResponseTokens: tokens)
    }

    private func expectStatus(_ status: HTTPStatus, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected HTTP \(status.code).")
        } catch let error as Abort {
            XCTAssertEqual(error.status, status)
            XCTAssertFalse(error.reason.contains("private-provider-error"))
            XCTAssertFalse(error.reason.contains("test-key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class AIClient: Client, @unchecked Sendable {
    let eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.next()
    private let lock = NSLock()
    private var recordedRequest: ClientRequest?
    private let status: HTTPStatus
    private let responseText: String

    var lastRequest: ClientRequest? {
        lock.withLock { recordedRequest }
    }

    init(status: HTTPStatus = .ok, responseText: String = "{}") {
        self.status = status
        self.responseText = responseText
    }

    func delegating(to eventLoop: any EventLoop) -> any Client {
        self
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        lock.withLock { recordedRequest = request }
        var buffer = ByteBufferAllocator().buffer(capacity: responseText.utf8.count)
        buffer.writeString(responseText)
        var response = ClientResponse(status: status, body: buffer)
        response.headers.contentType = .json
        return eventLoop.makeSucceededFuture(response)
    }
}
