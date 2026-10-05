import Foundation
import NIOCore
import Vapor

struct BrowserAIStreamEvent: Codable, Sendable {
    let text: String?
    let isFinal: Bool?
    let error: String?

    func buffer() throws -> ByteBuffer {
        let data = try JSONEncoder().encode(self)
        return ByteBuffer(string: "data: \(String(decoding: data, as: UTF8.self))\n\n")
    }
}

/// Handles split UTF-8, CR/LF delimiters, comments, and multiline SSE data fields.
struct BrowserSSEParser {
    private var pending: [UInt8] = []
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var totalBytes = 0

    mutating func feed(_ buffer: ByteBuffer) throws -> [String] {
        totalBytes += buffer.readableBytes
        guard totalBytes <= 1_048_576 else { throw invalidStream() }
        pending.append(contentsOf: buffer.readableBytesView)
        var events: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            if pending[end] == 13, end + 1 == pending.count { break }
            guard let line = String(bytes: pending[..<end], encoding: .utf8) else { throw invalidStream() }
            let consumed = end + (pending[end] == 13 && pending[end + 1] == 10 ? 2 : 1)
            pending.removeFirst(consumed)
            if line.isEmpty {
                if !dataLines.isEmpty { events.append(dataLines.joined(separator: "\n")) }
                dataLines.removeAll(keepingCapacity: true)
                eventBytes = 0
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                eventBytes += value.utf8.count
                guard eventBytes <= 65_536 else { throw invalidStream() }
                dataLines.append(value)
            }
        }
        guard pending.count <= 65_536 else { throw invalidStream() }
        return events
    }

    private func invalidStream() -> Abort {
        Abort(.badGateway, reason: "Invalid AI stream.")
    }
}

struct OpenRouterStreamDecoder {
    private(set) var isComplete = false
    private var text = ""
    private var stopped = false

    mutating func consume(_ data: String) throws -> BrowserAIStreamEvent? {
        guard !isComplete else { return nil }
        if data == "[DONE]" {
            guard stopped, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalidStream()
            }
            isComplete = true
            return BrowserAIStreamEvent(text: text, isFinal: true, error: nil)
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(data.utf8)), chunk.error == nil else {
            throw invalidStream()
        }
        guard let choices = chunk.choices else { throw invalidStream() }
        guard let choice = choices.first else { return nil }
        if let reason = choice.finishReason, reason != "stop" { throw invalidStream() }
        let delta = choice.delta.content ?? ""
        guard !stopped || delta.isEmpty else { throw invalidStream() }
        text += delta
        guard text.utf8.count <= 262_144 else { throw invalidStream() }
        if choice.finishReason == "stop" { stopped = true }
        guard !delta.isEmpty else { return nil }
        return BrowserAIStreamEvent(text: text, isFinal: false, error: nil)
    }

    private func invalidStream() -> Abort {
        Abort(.badGateway, reason: "The AI provider returned an invalid or incomplete stream.")
    }

    private struct Chunk: Decodable {
        struct ProviderError: Decodable {}

        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]?
        let error: ProviderError?
    }
}
