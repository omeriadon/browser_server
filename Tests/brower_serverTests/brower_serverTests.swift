@testable import brower_server
import Vapor
import XCTest

final class BrowserServerTests: XCTestCase {
    func testSessionTokensRoundTrip() async throws {
        let authentication = try await BrowserAuthentication.make(for: .testing)
        let response = try await authentication.issueSession(for: "apple-user")

        let subject = try await authentication.verifySession(response.token)
        XCTAssertEqual(subject, "apple-user")
    }
}
