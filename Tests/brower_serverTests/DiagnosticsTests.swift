@testable import brower_server
import Foundation
import Logging
import NIOCore
import Vapor
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testSanitizesNestedJSONCredentialsAndBearerValues() {
        let input = #"{"provider":{"apiKey":"secret-key","nested":{"authorization":"Bearer reusable-token"}},"message":"safe context bearer hidden-token"}"#
        let result = DiagnosticFormatter.sanitize(input)

        XCTAssertFalse(result.contains("secret-key"))
        XCTAssertFalse(result.contains("reusable-token"))
        XCTAssertFalse(result.contains("hidden-token"))
        XCTAssertTrue(result.contains("safe context"))
        XCTAssertTrue(result.contains("<redacted>"))
    }

    func testSanitizesCredentialAssignmentsAndURLs() {
        let result = DiagnosticFormatter.sanitize("token=abc123 url=https://example.test/path?identityToken=secret")

        XCTAssertFalse(result.contains("abc123"))
        XCTAssertFalse(result.contains("identityToken=secret"))
        XCTAssertTrue(result.contains("example.test"))
    }

    func testErrorChainIncludesCauseAndIsBounded() {
        let underlying = NSError(domain: "provider", code: 502, userInfo: [NSLocalizedDescriptionKey: "upstream failed"])
        let error = NSError(domain: "request", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])

        let chain = DiagnosticFormatter.errorChain(error)

        XCTAssertTrue(chain.contains("request:1"))
        XCTAssertTrue(chain.contains("provider:502"))
        XCTAssertLessThanOrEqual(chain.utf8.count, DiagnosticFormatter.maximumMessageLength)
    }
}

extension DiagnosticsTests {
    func testQuotedCredentialsUnicodeBoundsAndKnownSecrets() {
        let result = DiagnosticFormatter.sanitize(
            #"prefix {"password":"two word secret","api_key":"key123","identity_token":"id123"} cookie: a=one; b=two"#
        )
        for secret in ["two word secret", "key123", "id123", "a=one", "b=two"] {
            XCTAssertFalse(result.contains(secret), result)
        }
        let bounded = DiagnosticFormatter.sanitize(String(repeating: "漢字", count: 5_000))
        XCTAssertLessThanOrEqual(bounded.utf8.count, DiagnosticFormatter.maximumMessageLength)
        XCTAssertTrue(bounded.contains("truncated:"))
        XCTAssertFalse(DiagnosticFormatter.sanitize("provider echoed opaque-key", redacting: ["opaque-key"]).contains("opaque-key"))
    }

    func testDecodingContextPreservesUnderlyingCause() {
        let error = DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Invalid provider envelope",
            underlyingError: NSError(domain: "transport", code: 7)
        ))
        let detail = DiagnosticFormatter.errorChain(error)
        XCTAssertTrue(detail.contains("decoding=dataCorrupted"), detail)
        XCTAssertTrue(detail.contains("Invalid provider envelope"), detail)
        XCTAssertTrue(detail.contains("transport:7"), detail)
    }

    func testMiddlewareKeepsSuccessQuietAndCorrelatesSanitizedFailures() async throws {
        let app = try await Application.make(.testing)
        let capture = DiagnosticLogCapture()
        let logger = Logger(label: "diagnostics-test") { _ in DiagnosticCaptureHandler(capture: capture) }
        let middleware = ServerDiagnosticsMiddleware()
        do {
            let success = Request(application: app, method: .GET, url: "/health", on: app.eventLoopGroup.next())
            success.logger = logger
            let response = try await middleware.respond(to: success, chainingTo: DiagnosticResponder(status: .ok)).get()
            XCTAssertEqual(response.status, .ok)
            XCTAssertNotNil(UUID(uuidString: response.headers.first(name: "X-Request-ID") ?? ""))
            XCTAssertTrue(capture.snapshot.isEmpty)

            var body = ByteBufferAllocator().buffer(capacity: 128)
            body.writeString(#"{"identityToken":"never-log-this","nested":{"password":"also-secret"},"context":"keep-this"}"#)
            let failure = Request(application: app, method: .POST, url: "/v1/auth/apple", collectedBody: body, on: app.eventLoopGroup.next())
            failure.logger = logger
            let failed = try await middleware.respond(to: failure, chainingTo: DiagnosticResponder(status: .unauthorized)).get()
            XCTAssertEqual(failed.status, .unauthorized)
            XCTAssertEqual(capture.snapshot.count, 1)
            let record = capture.snapshot[0]
            XCTAssertEqual(record["request_id"]?.description, failed.headers.first(name: "X-Request-ID"))
            let rendered = String(describing: record)
            XCTAssertFalse(rendered.contains("never-log-this"), rendered)
            XCTAssertFalse(rendered.contains("also-secret"), rendered)
            XCTAssertTrue(rendered.contains("keep-this"), rendered)
            XCTAssertTrue(rendered.contains("request_bytes"), rendered)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    func testMiddlewarePreservesAbortHeadersAndHidesUnexpectedErrors() async throws {
        let app = try await Application.make(.testing)
        let capture = DiagnosticLogCapture()
        let logger = Logger(label: "diagnostics-test") { _ in DiagnosticCaptureHandler(capture: capture) }
        let request = Request(application: app, method: .POST, url: "/failure", on: app.eventLoopGroup.next())
        request.logger = logger
        do {
            let response = try await ServerDiagnosticsMiddleware().respond(
                to: request,
                chainingTo: DiagnosticResponder(error: Abort(.tooManyRequests, headers: ["Retry-After": "60"], reason: "Try later."))
            ).get()
            XCTAssertEqual(response.status, .tooManyRequests)
            XCTAssertEqual(response.headers.first(name: "Retry-After"), "60")
            XCTAssertTrue(response.body.string?.contains("Try later.") == true)
            XCTAssertEqual(capture.snapshot.count, 1)

            let unexpected = try await ServerDiagnosticsMiddleware().respond(
                to: request,
                chainingTo: DiagnosticResponder(error: NSError(domain: "database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Private table details"]))
            ).get()
            XCTAssertEqual(unexpected.status, .internalServerError)
            XCTAssertFalse(unexpected.body.string?.contains("Private table details") == true)
            XCTAssertTrue(String(describing: capture.snapshot.last).contains("Private table details"))
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

private final class DiagnosticLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [Logger.Metadata] = []

    func append(_ record: Logger.Metadata) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
    }

    var snapshot: [Logger.Metadata] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

private struct DiagnosticCaptureHandler: LogHandler {
    let capture: DiagnosticLogCapture
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.MetadataValue? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        capture.append(metadata.merging(event.metadata ?? [:]) { _, new in new })
    }
}

private struct DiagnosticResponder: Responder {
    var status: HTTPResponseStatus = .ok
    var error: (any Error)? = nil

    func respond(to request: Request) -> EventLoopFuture<Response> {
        if let error {
            return request.eventLoop.makeFailedFuture(error)
        }
        return request.eventLoop.makeSucceededFuture(Response(status: status))
    }
}
