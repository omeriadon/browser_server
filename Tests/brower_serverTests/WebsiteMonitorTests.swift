@testable import brower_server
import Foundation
import XCTest

final class WebsiteMonitorTests: XCTestCase {
    func testPublicTargetsAndPrivateAddressExclusions() throws {
        for value in ["127.0.0.1", "10.2.3.4", "169.254.169.254", "192.168.1.1", "172.16.2.3", "::1", "fd00::1", "::ffff:127.0.0.1", "2001:db8::1"] {
            XCTAssertFalse(PublicWebsiteReader.publicAddress(value), value)
        }
        XCTAssertTrue(PublicWebsiteReader.publicAddress("1.1.1.1"))
        XCTAssertTrue(PublicWebsiteReader.publicAddress("2606:4700:4700::1111"))
        XCTAssertThrowsError(try PublicWebsiteReader.validate(URL(string: "http://localhost")!))
        XCTAssertThrowsError(try PublicWebsiteReader.validate(URL(string: "https://user:password@example.com")!))
        XCTAssertThrowsError(try PublicWebsiteReader.validate(URL(string: "https://example.com:8443")!))
        XCTAssertNoThrow(try PublicWebsiteReader.validate(URL(string: "https://www.apple.com/store")!))
    }

    func testMonitoringDecisionAndIntervals() throws {
        let result = try WebsiteMonitorDecision.decode("```json\n{\"matched\":true,\"reason\":\"The requested phone is now listed in the store.\"}\n```")
        XCTAssertTrue(result.matched)
        XCTAssertThrowsError(try WebsiteMonitorDecision.decode("{\"matched\":true,\"reason\":\"\"}"))
        XCTAssertThrowsError(try WebsiteMonitorInput(spaceID: UUID(), url: "https://example.com", title: "Example", criterion: "New product", instructions: "Check the condition", intervalDays: 0).validate())
        XCTAssertNoThrow(try WebsiteMonitorInput(spaceID: UUID(), url: "https://example.com", title: "Example", criterion: "New product", instructions: "Check the condition", intervalDays: 30).validate())
    }
}
