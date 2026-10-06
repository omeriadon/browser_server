import Fluent
import Foundation
import Vapor

final class WebsiteMonitor: Model, @unchecked Sendable {
    static let schema = "website_monitors"
    @ID(key: .id) var id: UUID?
    @Field(key: "owner") var owner: String
    @Field(key: "space_id") var spaceID: UUID
    @Field(key: "url") var url: String
    @Field(key: "title") var title: String
    @Field(key: "criterion") var criterion: String
    @Field(key: "instructions") var instructions: String
    @Field(key: "interval_days") var intervalDays: Int
    @Field(key: "enabled") var enabled: Bool
    @Field(key: "next_check") var nextCheck: Date
    @OptionalField(key: "matched_at") var matchedAt: Date?
    @OptionalField(key: "message") var message: String?
    @OptionalField(key: "last_error") var lastError: String?
    @Field(key: "checks") var checks: Int

    init() {}

    var response: WebsiteMonitorResponse {
        .init(id: id!, spaceID: spaceID, url: url, title: title, criterion: criterion, intervalDays: intervalDays, enabled: enabled, nextCheck: nextCheck.timeIntervalSince1970, matchedAt: matchedAt?.timeIntervalSince1970, message: message, lastError: lastError, checks: checks)
    }
}

struct WebsiteMonitorResponse: Content {
    let id: UUID
    let spaceID: UUID
    let url: String
    let title: String
    let criterion: String
    let intervalDays: Int
    let enabled: Bool
    let nextCheck: Double
    let matchedAt: Double?
    let message: String?
    let lastError: String?
    let checks: Int
}

struct CreateWebsiteMonitors: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(WebsiteMonitor.schema)
            .id()
            .field("owner", .string, .required)
            .field("space_id", .uuid, .required)
            .field("url", .string, .required)
            .field("title", .string, .required)
            .field("criterion", .string, .required)
            .field("instructions", .string, .required)
            .field("interval_days", .int, .required)
            .field("enabled", .bool, .required)
            .field("next_check", .datetime, .required)
            .field("matched_at", .datetime)
            .field("message", .string)
            .field("last_error", .string)
            .field("checks", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(WebsiteMonitor.schema).delete()
    }
}
