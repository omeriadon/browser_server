import Foundation
import SwiftSoup
import Logging
import Vapor
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum PublicWebsiteReader {
    static func publicAddress(_ address: String) -> Bool {
        if address.contains(":") {
            var value = in6_addr()
            guard inet_pton(AF_INET6, address, &value) == 1 else { return false }
            return withUnsafeBytes(of: value) { bytes in
                bytes[0] & 0xe0 == 0x20 && !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
            }
        }
        let values = address.split(separator: ".").compactMap { Int($0) }
        guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return false }
        let a = values[0], b = values[1]
        return a != 0 && a != 10 && a != 127 && a < 224
            && !(a == 100 && (64...127).contains(b))
            && !(a == 169 && b == 254)
            && !(a == 172 && (16...31).contains(b))
            && !(a == 192 && (b == 168 || b == 0))
            && !(a == 198 && (b == 18 || b == 19 || b == 51))
            && !(a == 203 && b == 0 && values[2] == 113)
    }

    static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.port == nil || [80, 443].contains(url.port!),
              url.absoluteString.utf8.count <= 8192,
              !["localhost", "localhost.localdomain"].contains(host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))),
              ![".local", ".internal", ".localhost", ".onion"].contains(where: { host.lowercased().hasSuffix($0) }) else {
            throw Abort(.badRequest, reason: "Monitoring requires a public HTTP or HTTPS website without URL credentials.")
        }
    }

    private static func resolve(_ host: String, logger: Logger? = nil, requestID: String? = nil) throws -> String {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let first = result else {
            logger.map {
                DiagnosticFormatter.log(
                    NSError(domain: "getaddrinfo", code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(cString: gai_strerror(status))]),
                    logger: $0,
                    requestID: requestID,
                    operation: "monitor.resolve",
                    metadata: ["host": .string(DiagnosticFormatter.sanitize(host))]
                )
            }
            throw Abort(.badRequest, reason: "The website hostname could not be resolved.")
        }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var addresses: [String] = []
        while let entry = cursor {
            var buffer = [CChar](repeating: 0, count: 1025)
            if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
            cursor = entry.pointee.ai_next
        }
        guard !addresses.isEmpty, addresses.allSatisfy(publicAddress) else {
            throw Abort(.badRequest, reason: "Private, local, and reserved network addresses cannot be monitored.")
        }
        return addresses.first!
    }

    static func read(_ initialURL: URL, logger: Logger? = nil, requestID: String? = nil) async throws -> String {
        try await Task.detached(priority: .utility) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("astra-monitor-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var url = initialURL
            for _ in 0..<4 {
                try validate(url)
                let host = url.host!
                let address = try resolve(host, logger: logger, requestID: requestID)
                let pinned = address.contains(":") ? "[\(address)]" : address
                let headers = directory.appendingPathComponent("headers")
                let body = directory.appendingPathComponent("body")
                let stderr = directory.appendingPathComponent("stderr")
                guard FileManager.default.createFile(atPath: stderr.path, contents: nil) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = ["--disable", "--silent", "--show-error", "--noproxy", "*", "--proto", "=http,https", "--max-time", "25", "--connect-timeout", "10", "--max-filesize", "4194304", "--resolve", "\(host):\(url.port ?? (url.scheme == "https" ? 443 : 80)):\(pinned)", "--dump-header", headers.path, "--output", body.path, "--user-agent", "Mozilla/5.0 AstraWebsiteMonitor/1.0", "--", url.absoluteString]
                process.standardOutput = FileHandle.nullDevice
                let stderrHandle = try FileHandle(forWritingTo: stderr)
                defer { try? stderrHandle.close() }
                process.standardError = stderrHandle
                try process.run()
                process.waitUntilExit()
                try? stderrHandle.close()
                guard process.terminationStatus == 0 else {
                    let reader = try FileHandle(forReadingFrom: stderr)
                    defer { try? reader.close() }
                    let detail = String(decoding: try reader.read(upToCount: 16_384) ?? Data(), as: UTF8.self)
                    logger.map {
                        DiagnosticFormatter.log(
                            NSError(domain: "curl", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail]),
                            logger: $0,
                            requestID: requestID,
                            operation: "monitor.fetch",
                            metadata: ["url": .string(DiagnosticFormatter.sanitize(url.absoluteString)), "address": .string(address)]
                        )
                    }
                    throw Abort(.badGateway, reason: "The public website could not be read within its size or time limit.")
                }
                let header = try String(contentsOf: headers, encoding: .utf8)
                let lines = header.components(separatedBy: .newlines)
                let status = lines.first(where: { $0.hasPrefix("HTTP/") })?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
                if (300..<400).contains(status), let location = lines.first(where: { $0.lowercased().hasPrefix("location:") }) {
                    guard let next = URL(string: String(location.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: url)?.absoluteURL else { throw Abort(.badGateway) }
                    url = next
                    continue
                }
                guard (200..<300).contains(status) else {
                    logger.map {
                        DiagnosticFormatter.log(
                            Abort(.badGateway, reason: "The website returned HTTP \(status)."),
                            logger: $0,
                            requestID: requestID,
                            operation: "monitor.http",
                            metadata: ["url": .string(DiagnosticFormatter.sanitize(url.absoluteString)), "http_status": .stringConvertible(status)]
                        )
                    }
                    throw Abort(.badGateway, reason: "The website returned HTTP \(status).")
                }
                let data = try Data(contentsOf: body)
                guard data.count <= 4_194_304, let html = String(data: data, encoding: .utf8) else { throw Abort(.badGateway) }
                let document = try SwiftSoup.parse(html)
                try document.select("script,style,noscript,template,svg,canvas,input,textarea,select,[hidden],[aria-hidden=true]").remove()
                let text = try document.body()?.text() ?? ""
                guard !text.isEmpty else { throw Abort(.badGateway, reason: "This website has no publicly readable text.") }
                return String(text.prefix(110_000))
            }
            throw Abort(.badGateway, reason: "The website redirected too many times.")
        }.value
    }
}
