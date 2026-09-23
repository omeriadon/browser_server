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

    var response: SyncSnapshotResponse {
        SyncSnapshotResponse(
            deviceID: deviceID,
            payload: payload,
            revision: revision,
            updatedAt: updatedAt
        )
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
