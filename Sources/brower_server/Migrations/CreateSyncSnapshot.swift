import Fluent

struct CreateSyncSnapshot: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SyncSnapshot.schema)
            .id()
            .field("apple_subject", .string, .required)
            .field("device_id", .uuid, .required)
            .field("payload", .data, .required)
            .field("revision", .int, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "apple_subject", "device_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SyncSnapshot.schema).delete()
    }
}
