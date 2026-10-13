@testable import brower_server
import Foundation
import XCTest

final class SyncSnapshotTests: XCTestCase {
    func testResponseNormalizesTopLevelVersionAndPreservesOtherFields() throws {
        let payload = Data(#"{"version":99,"unknown":"keep","nested":{"version":77}}"#.utf8)
        let snapshot = SyncSnapshot(appleSubject: "subject", deviceID: UUID(), payload: payload)

        let response = try snapshot.response()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.payload) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["unknown"] as? String, "keep")
        XCTAssertEqual((object["nested"] as? [String: Any])?["version"] as? Int, 77)
        XCTAssertEqual(snapshot.payload, payload)
    }

    func testResponseLeavesOlderMissingAndNonObjectPayloadsUntouched() throws {
        for payload in [
            Data(#"{"version":1,"value":true}"#.utf8),
            Data(#"{"value":true}"#.utf8),
            Data(#"[1,{"version":99}]"#.utf8),
            Data([0xff, 0xfe, 0xfd])
        ] {
            let snapshot = SyncSnapshot(appleSubject: "subject", deviceID: UUID(), payload: payload)
            XCTAssertEqual(try snapshot.response().payload, payload)
        }
    }
}
