@testable import brower_server
import JWTKit
import NIOCore
import Vapor
import XCTest

final class BrowserServerTests: XCTestCase {
    func testAppleAudienceAllowlist() async throws {
        let authentication = try await BrowserAuthentication.make(for: .testing)
        let configuredIDs = (Environment.get("APPLE_CLIENT_ID") ?? "com.omeriadon.browser")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for clientID in configuredIDs {
            XCTAssertNoThrow(try authentication.verifyAppleAudience(AudienceClaim(value: [clientID])))
        }
        XCTAssertThrowsError(try authentication.verifyAppleAudience(AudienceClaim(value: ["untrusted.app"])))
    }

    func testSessionTokensRoundTrip() async throws {
        let authentication = try await BrowserAuthentication.make(for: .testing)
        let response = try await authentication.issueSession(for: "apple-user")

        let subject = try await authentication.verifySession(response.token)
        XCTAssertEqual(subject, "apple-user")
    }

    func testSessionRejectsTamperedAndInvalidTokens() async throws {
        let authentication = try await BrowserAuthentication.make(for: .testing)
        let response = try await authentication.issueSession(for: "apple-user")
        var tokenParts = response.token.split(separator: ".", omittingEmptySubsequences: false)
        tokenParts[2].replaceSubrange(tokenParts[2].startIndex...tokenParts[2].startIndex, with: tokenParts[2].first == "A" ? "B" : "A")
        let tampered = tokenParts.joined(separator: ".")

        await XCTAssertThrowsErrorAsync {
            _ = try await authentication.verifySession(tampered)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await authentication.verifySession("not-a-jwt")
        }
    }

    func testAppleIdentityTokenRejectsFakeSignature() async throws {
        let authentication = try await BrowserAuthentication.make(for: .testing)
        let client = FakeAppleClient(eventLoop: MultiThreadedEventLoopGroup.singleton.next())

        do {
            _ = try await authentication.verifyAppleIdentityToken(
                "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYWtlIn0.fake-signature",
                client: client
            )
            XCTFail("A token with a fake signature must be rejected.")
        } catch let error as Abort {
            XCTAssertEqual(error.status, .unauthorized)
        }
    }
}

private struct FakeAppleClient: Client, @unchecked Sendable {
    let eventLoop: any EventLoop

    func delegating(to eventLoop: any EventLoop) -> any Client {
        FakeAppleClient(eventLoop: eventLoop)
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        var body = ByteBufferAllocator().buffer(capacity: 16)
        body.writeString("{\"keys\":[]}")
        return eventLoop.makeSucceededFuture(ClientResponse(body: body))
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error.", file: file, line: line)
    } catch {
    }
}
