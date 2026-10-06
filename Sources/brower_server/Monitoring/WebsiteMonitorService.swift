import Fluent
import Foundation
import Vapor

struct WebsiteMonitorInput: Content {
    let spaceID: UUID
    let url: String
    let title: String
    let criterion: String
    let instructions: String
    let intervalDays: Int

    func validate() throws {
        guard let url = URL(string: url), !criterion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              criterion.utf8.count <= 4000, title.utf8.count <= 1024,
              !instructions.isEmpty, instructions.utf8.count <= 32_768,
              [1, 7, 14, 30].contains(intervalDays) else { throw Abort(.badRequest, reason: "Choose a public website, a condition, and a daily-to-monthly interval.") }
        try PublicWebsiteReader.validate(url)
    }
}

struct MonitorState: Content { let enabled: Bool }
struct MonitorDeleted: Content { let deleted: Bool }

func websiteMonitorRoutes(_ routes: any RoutesBuilder) {
    routes.get("monitors") { request async throws -> [WebsiteMonitorResponse] in
        let owner = try request.auth.require(AuthenticatedBrowserUser.self).appleSubject
        return try await WebsiteMonitor.query(on: request.db).filter(\.$owner == owner).all().map(\.response)
    }
    routes.post("monitors") { request async throws -> WebsiteMonitorResponse in
        let owner = try request.auth.require(AuthenticatedBrowserUser.self).appleSubject
        let input = try request.content.decode(WebsiteMonitorInput.self)
        try input.validate()
        guard try await WebsiteMonitor.query(on: request.db).filter(\.$owner == owner).count() < 20 else { throw Abort(.tooManyRequests, reason: "Keep at most twenty website monitors.") }
        let monitor = WebsiteMonitor()
        monitor.owner = owner
        monitor.spaceID = input.spaceID
        monitor.url = input.url
        monitor.title = input.title
        monitor.criterion = input.criterion
        monitor.instructions = input.instructions
        monitor.intervalDays = input.intervalDays
        monitor.enabled = true
        monitor.nextCheck = .now
        monitor.checks = 0
        try await monitor.save(on: request.db)
        return monitor.response
    }
    routes.put("monitors", "enabled") { request async throws -> MonitorState in
        let owner = try request.auth.require(AuthenticatedBrowserUser.self).appleSubject
        let state = try request.content.decode(MonitorState.self)
        for monitor in try await WebsiteMonitor.query(on: request.db).filter(\.$owner == owner).all() {
            monitor.enabled = state.enabled
            try await monitor.update(on: request.db)
        }
        return state
    }
    routes.delete("monitors", ":id") { request async throws -> MonitorDeleted in
        let owner = try request.auth.require(AuthenticatedBrowserUser.self).appleSubject
        guard let id = request.parameters.get("id", as: UUID.self),
              let monitor = try await WebsiteMonitor.find(id, on: request.db), monitor.owner == owner else { throw Abort(.notFound) }
        try await monitor.delete(on: request.db)
        return MonitorDeleted(deleted: true)
    }
}

struct WebsiteMonitorDecision: Decodable {
    let matched: Bool
    let reason: String

    static func decode(_ text: String) throws -> Self {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), let first = json.firstIndex(of: "\n"), let last = json.range(of: "```", options: .backwards), first < last.lowerBound {
            json = String(json[json.index(after: first)..<last.lowerBound])
        }
        let result = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
        guard !result.reason.isEmpty, result.reason.utf8.count <= 1000,
              result.reason.split(whereSeparator: \.isWhitespace).count <= 40 else { throw Abort(.badGateway, reason: "The model returned an invalid monitoring explanation.") }
        return result
    }
}

actor WebsiteMonitorWorker {
    let app: Application
    let ai = BrowserAIService.configured()

    init(app: Application) { self.app = app }

    func tick() async {
        do {
            let due = try await WebsiteMonitor.query(on: app.db)
                .filter(\.$enabled == true).filter(\.$matchedAt == nil).filter(\.$nextCheck <= Date.now)
                .sort(\.$nextCheck).limit(10).all()
            for monitor in due {
                guard !Task.isCancelled else { return }
                let start = Date.now
                monitor.nextCheck = Calendar(identifier: .gregorian).date(byAdding: monitor.intervalDays == 30 ? .month : .day, value: monitor.intervalDays == 30 ? 1 : monitor.intervalDays, to: start) ?? start.addingTimeInterval(Double(monitor.intervalDays) * 86400)
                monitor.checks += 1
                try await monitor.update(on: app.db)
                do {
                    guard let url = URL(string: monitor.url) else { throw Abort(.badRequest) }
                    let page = try await PublicWebsiteReader.read(url)
                    app.logger.info("AI usage feature=website-monitor event=request monitor=\(monitor.id!)")
                    let response = try await ai.generate(.init(modelID: Environment.get("MONITOR_OPENROUTER_MODEL") ?? "openai/gpt-4o-mini", instructions: monitor.instructions, prompt: "Current date: \(Date().ISO8601Format())\nWebsite URL: \(monitor.url)\nCondition: \(monitor.criterion)\n<untrusted-page>\n\(page)\n</untrusted-page>", maximumResponseTokens: 256), subject: monitor.owner, client: app.client)
                    let decision = try WebsiteMonitorDecision.decode(response.text)
                    guard let current = try await WebsiteMonitor.find(monitor.id, on: app.db), current.enabled else { continue }
                    current.lastError = nil
                    if decision.matched {
                        current.matchedAt = .now
                        current.message = decision.reason
                    }
                    try await current.update(on: app.db)
                    app.logger.info("AI usage feature=website-monitor event=success monitor=\(monitor.id!) matched=\(decision.matched)")
                } catch {
                    if let current = try await WebsiteMonitor.find(monitor.id, on: app.db) {
                        current.lastError = (error as? Abort)?.reason ?? "The website or AI service could not be checked."
                        try await current.update(on: app.db)
                    }
                    app.logger.warning("AI usage feature=website-monitor event=failed monitor=\(monitor.id!)")
                }
            }
        } catch { app.logger.error("Website monitoring tick failed: \(String(describing: type(of: error)))") }
    }
}

final class WebsiteMonitorLifecycle: LifecycleHandler, @unchecked Sendable {
    private var task: Task<Void, Never>?

    func didBoot(_ application: Application) throws {
        guard application.environment != .testing, CommandLine.arguments.contains("serve") else { return }
        task = Task {
            let worker = WebsiteMonitorWorker(app: application)
            while !Task.isCancelled {
                await worker.tick()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }

    func shutdown(_ application: Application) { task?.cancel() }
}
