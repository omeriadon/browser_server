import Fluent
import Foundation
import Vapor

final class SyncSnapshot: Model, @unchecked Sendable {
    static let schema = "sync_snapshots"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "apple_subject")
    var appleSubject: String

    @Field(key: "device_id")
    var deviceID: UUID

    @Field(key: "payload")
    var payload: Data

    @Field(key: "revision")
    var revision: Int

    @Field(key: "updated_at")
    var updatedAt: Date

    init() {}

    init(
        id: UUID? = nil,
        appleSubject: String,
        deviceID: UUID,
        payload: Data = Data(),
        revision: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.appleSubject = appleSubject
        self.deviceID = deviceID
        self.payload = payload
        self.revision = revision
        self.updatedAt = updatedAt
    }

    func response() throws -> SyncSnapshotResponse {
        let responsePayload = try Self.responsePayload(from: payload)
        return SyncSnapshotResponse(
            deviceID: deviceID,
            payload: responsePayload,
            revision: revision,
            updatedAt: updatedAt
        )
    }

    private static func responsePayload(from payload: Data) throws -> Data {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        } catch {
            return payload
        }
        guard var dictionary = object as? [String: Any], dictionary.keys.contains("version") else {
            return payload
        }
        if let version = dictionary["version"] as? NSNumber, version.intValue == 1 {
            return payload
        }
        // Keep the response marker compatible with installed clients that still gate versions.
        dictionary["version"] = 1
        return try JSONSerialization.data(withJSONObject: dictionary)
    }
}

struct SyncSnapshotRequest: Content {
    var deviceID: UUID
    var payload: Data
}

struct SyncSnapshotResponse: Content {
    var deviceID: UUID
    var payload: Data
    var revision: Int
    var updatedAt: Date
}
