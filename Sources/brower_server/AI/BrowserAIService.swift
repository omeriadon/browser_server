import Foundation
import AsyncHTTPClient
import Vapor

struct BrowserAIRequest: Content {
    let modelID: String
    let instructions: String
    let prompt: String
    let maximumResponseTokens: Int
    let images: [BrowserAIImage]?

    init(modelID: String, instructions: String, prompt: String, maximumResponseTokens: Int, images: [BrowserAIImage]? = nil) {
        self.modelID = modelID
        self.instructions = instructions
        self.prompt = prompt
        self.maximumResponseTokens = maximumResponseTokens
        self.images = images
    }

    func validate(allowedModels: Set<String>) throws {
        guard allowedModels.contains(modelID) else {
            throw Abort(.badRequest, reason: "This AI model is not enabled on the server.")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              instructions.utf8.count <= 32_768,
              prompt.utf8.count <= 16_777_216,
              (1...2_048).contains(maximumResponseTokens)
        else {
            throw Abort(.badRequest, reason: "Invalid AI prompt or output limit.")
        }
        if let images {
            guard images.count <= 8,
                  images.reduce(0, { $0 + $1.data.count }) <= 10_485_760,
                  images.allSatisfy(\.isValid) else {
                throw Abort(.badRequest, reason: "Attach at most eight PNG, JPEG, GIF, or WebP images totaling 10 MB.")
            }
        }
    }
}

struct BrowserAIImage: Content {
    let name: String
    let mediaType: String
    let data: Data

    var isValid: Bool {
        guard !name.isEmpty, name.utf8.count <= 240, !data.isEmpty else { return false }
        let prefix = [UInt8](data.prefix(12))
        switch mediaType {
        case "image/png": return prefix.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        case "image/jpeg": return prefix.starts(with: [255, 216, 255])
        case "image/gif": return prefix.starts(with: Array("GIF8".utf8))
        case "image/webp": return prefix.starts(with: Array("RIFF".utf8)) && Array(prefix.dropFirst(8)) == Array("WEBP".utf8)
        default: return false
        }
    }
}

struct BrowserAIResponse: Content {
    let text: String
}

func aiRoutes(_ routes: any RoutesBuilder, service: BrowserAIService) {
    routes.on(.POST, ["ai", "generate"], body: .collect(maxSize: "20mb")) { request async throws -> BrowserAIResponse in
        let user = try request.auth.require(AuthenticatedBrowserUser.self)
        let body = try request.content.decode(BrowserAIRequest.self)
        return try await service.generate(body, subject: user.appleSubject, client: request.client)
    }
    routes.on(.POST, ["ai", "stream"], body: .collect(maxSize: "20mb")) { request async throws -> Response in
        let user = try request.auth.require(AuthenticatedBrowserUser.self)
        let body = try request.content.decode(BrowserAIRequest.self)
        return try await service.stream(body, subject: user.appleSubject) { upstream in
            try await request.application.http.client.shared.execute(upstream, timeout: .seconds(75))
        }
    }
}

/// One service per process. Limits count attempts, including provider failures.
actor BrowserAIService {
    private let apiKey: String?
    private let allowedModels: Set<String>
    private var usage: [String: Usage] = [:]
    private var activeRequests = 0

    private struct Usage {
        var dayStarted: Date
        var minuteStarted: Date
        var dailyRequests = 0
        var minuteRequests = 0
        var activeRequests = 0
    }

    init(apiKey: String?, allowedModels: Set<String>) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allowedModels = allowedModels
    }

    static func configured() -> BrowserAIService {
        let models = (Environment.get("OPENROUTER_ALLOWED_MODELS") ?? "inclusionai/ling-3.1-flash,openai/gpt-4o-mini")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return BrowserAIService(
            apiKey: Environment.get("OPENROUTER_API_KEY"),
            allowedModels: Set(models)
        )
    }

    func generate(_ body: BrowserAIRequest, subject: String, client: any Client) async throws -> BrowserAIResponse {
        try body.validate(allowedModels: allowedModels)
        guard let apiKey, !apiKey.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Cloud AI is not configured.")
        }
        try reserve(for: subject)
        defer { release(for: subject) }

        let response: ClientResponse
        do {
            response = try await client.post("https://openrouter.ai/api/v1/chat/completions") { request in
                request.timeout = .seconds(75)
                request.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
                request.headers.replaceOrAdd(name: "Accept", value: "application/json")
                request.headers.replaceOrAdd(name: "X-Title", value: "Astra")
                try request.content.encode(OpenRouterRequest(
                    model: body.modelID,
                    messages: [
                        .init(role: "system", content: body.instructions),
                        .init(role: "user", prompt: body.prompt, images: body.images)
                    ],
                    maxTokens: body.maximumResponseTokens
                ))
            }
        } catch {
            // Do not expose provider errors, headers, prompts, or credentials.
            throw Abort(.badGateway, reason: "The AI provider could not be reached.")
        }
        if response.status == .tooManyRequests {
            throw Abort(.tooManyRequests, reason: "The AI provider is busy. Try again later.")
        }
        guard response.status == .ok,
              let buffer = response.body,
              buffer.readableBytes <= 262_144,
              let completion = try? response.content.decode(OpenRouterResponse.self),
              let choice = completion.choices.first,
              choice.finishReason == "stop",
              let text = choice.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Abort(.badGateway, reason: "The AI provider did not return a complete text response.")
        }
        return BrowserAIResponse(text: text)
    }

    private func reserve(for subject: String, now: Date = .now) throws {
        // ponytail: process-local quotas reset on restart; use a shared store before running multiple replicas.
        usage = usage.filter { $0.value.activeRequests > 0 || now.timeIntervalSince($0.value.dayStarted) < 86_400 }
        var current = usage[subject] ?? Usage(dayStarted: now, minuteStarted: now)
        if now.timeIntervalSince(current.dayStarted) >= 86_400 {
            current.dayStarted = now
            current.dailyRequests = 0
        }
        if now.timeIntervalSince(current.minuteStarted) >= 60 {
            current.minuteStarted = now
            current.minuteRequests = 0
        }
        guard current.dailyRequests < 100, current.minuteRequests < 10,
              current.activeRequests < 2, activeRequests < 8,
              usage[subject] != nil || usage.count < 10_000
        else {
            throw Abort(.tooManyRequests, reason: "AI usage limit reached. Try again later.")
        }
        current.dailyRequests += 1
        current.minuteRequests += 1
        current.activeRequests += 1
        usage[subject] = current
        activeRequests += 1
    }

    private func release(for subject: String) {
        usage[subject]?.activeRequests -= 1
        activeRequests -= 1
    }

    func stream(
        _ body: BrowserAIRequest,
        subject: String,
        execute: @Sendable (HTTPClientRequest) async throws -> HTTPClientResponse
    ) async throws -> Response {
        try body.validate(allowedModels: allowedModels)
        guard let apiKey, !apiKey.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Cloud AI is not configured.")
        }
        try reserve(for: subject)
        let upstream: HTTPClientResponse
        do {
            var request = HTTPClientRequest(url: "https://openrouter.ai/api/v1/chat/completions")
            request.method = .POST
            request.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
            request.headers.contentType = .json
            request.headers.replaceOrAdd(name: "Accept", value: "text/event-stream")
            request.headers.replaceOrAdd(name: "X-Title", value: "Astra")
            request.body = .bytes(try JSONEncoder().encode(OpenRouterRequest(
                model: body.modelID,
                messages: [
                    .init(role: "system", content: body.instructions),
                    .init(role: "user", prompt: body.prompt, images: body.images)
                ],
                maxTokens: body.maximumResponseTokens,
                stream: true
            )))
            upstream = try await execute(request)
            if upstream.status == .tooManyRequests {
                throw Abort(.tooManyRequests, reason: "The AI provider is busy. Try again later.")
            }
            guard upstream.status == .ok,
                  upstream.headers.first(name: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true
            else {
                throw Abort(.badGateway, reason: "The AI provider did not return a text stream.")
            }
        } catch {
            release(for: subject)
            if let abort = error as? Abort, abort.status == .tooManyRequests {
                throw abort
            }
            throw Abort(.badGateway, reason: "The AI provider could not start generation.")
        }

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/event-stream; charset=utf-8")
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache, no-transform")
        response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")
        response.body = .init(managedAsyncStream: { writer in
            do {
                var parser = BrowserSSEParser()
                var decoder = OpenRouterStreamDecoder()
                for try await buffer in upstream.body {
                    try Task.checkCancellation()
                    for data in try parser.feed(buffer) {
                        if let event = try decoder.consume(data) {
                            try await writer.writeBuffer(event.buffer())
                        }
                    }
                    if decoder.isComplete { break }
                }
                guard decoder.isComplete else {
                    throw Abort(.badGateway, reason: "Incomplete AI stream.")
                }
            } catch {
                // A 200 stream can fail later. Never forward upstream error details.
                let event = BrowserAIStreamEvent(text: nil, isFinal: nil, error: "Cloud AI generation failed.")
                try? await writer.writeBuffer(event.buffer())
            }
            await self.release(for: subject)
        })
        return response
    }
}

private struct OpenRouterRequest: Content {
    struct Message: Content {
        struct Part: Content {
            struct ImageURL: Content { let url: String }
            let type: String
            var text: String?
            var imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }
        }

        enum Body: Content {
            case text(String)
            case parts([Part])

            init(from decoder: any Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let text = try? value.decode(String.self) { self = .text(text) }
                else { self = .parts(try value.decode([Part].self)) }
            }

            func encode(to encoder: any Encoder) throws {
                var value = encoder.singleValueContainer()
                switch self {
                case let .text(text): try value.encode(text)
                case let .parts(parts): try value.encode(parts)
                }
            }
        }

        let role: String
        let content: Body

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        init(role: String, prompt: String, images: [BrowserAIImage]?) {
            self.role = role
            if let images, !images.isEmpty {
                content = .parts([Part(type: "text", text: prompt)] + images.map {
                    Part(type: "image_url", imageURL: .init(url: "data:\($0.mediaType);base64,\($0.data.base64EncodedString())"))
                })
            } else {
                content = .text(prompt)
            }
        }
    }

    struct Reasoning: Content {
        let effort: String
    }

    let reasoning = Reasoning(effort: "low")
    let model: String
    let messages: [Message]
    let maxTokens: Int
    var stream: Bool = false

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case reasoning
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenRouterResponse: Content {
    struct Choice: Content {
        struct Message: Content {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}
