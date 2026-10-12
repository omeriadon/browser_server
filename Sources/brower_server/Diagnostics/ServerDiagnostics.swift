import Foundation
import Logging
import NIOCore
import Vapor

private struct DiagnosticRequestIDKey: StorageKey {
    typealias Value = String
}

extension Request {
    var diagnosticRequestID: String {
        if let existing = storage[DiagnosticRequestIDKey.self] {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        storage[DiagnosticRequestIDKey.self] = value
        return value
    }
}

enum DiagnosticFormatter {
    static let maximumMessageLength = 4_000

    static func log(
        _ error: any Error,
        logger: Logger,
        requestID: String? = nil,
        operation: String,
        metadata: Logger.Metadata = [:],
        redacting secrets: [String] = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        var fields = metadata.mapValues { Logger.MetadataValue.string(sanitize($0.description, redacting: secrets)) }
        fields["request_id"] = .string(sanitize(requestID ?? "background"))
        fields["operation"] = .string(sanitize(operation))
        fields["error_type"] = .string(String(reflecting: type(of: error)))
        fields["error_chain"] = .string(errorChain(error, redacting: secrets))
        fields["source"] = .string("\(file):\(line) \(function)")
        if let debuggable = error as? any DebuggableError {
            fields["error_identifier"] = .string(sanitize(debuggable.identifier))
            if let source = debuggable.source {
                fields["error_source"] = .string("\(source.file):\(source.line) \(source.function)")
            }
        }
        logger.error("operation failed", metadata: fields, file: file, function: function, line: line)
    }

    static func errorChain(_ error: any Error, redacting secrets: [String] = []) -> String {
        var values: [String] = []
        var current: (any Error)? = error
        var seen = Set<ObjectIdentifier>()
        while let value = current, values.count < 8 {
            let nsError = value as NSError
            guard seen.insert(ObjectIdentifier(nsError)).inserted else {
                values.append("<cycle>")
                break
            }
            var fields = [
                "\(String(reflecting: type(of: value))) [\(nsError.domain):\(nsError.code)]",
                sanitize(type(of: value) is NSError.Type ? nsError.localizedDescription : String(reflecting: value), redacting: secrets),
            ]
            var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error
            let context: DecodingError.Context?
            switch value {
            case let DecodingError.dataCorrupted(detail):
                fields.append("decoding=dataCorrupted")
                context = detail
            case let DecodingError.keyNotFound(key, detail):
                fields.append("decoding=keyNotFound missing_key=\(sanitize(key.stringValue))")
                context = detail
            case let DecodingError.typeMismatch(type, detail):
                fields.append("decoding=typeMismatch expected_type=\(String(reflecting: type))")
                context = detail
            case let DecodingError.valueNotFound(type, detail):
                fields.append("decoding=valueNotFound expected_type=\(String(reflecting: type))")
                context = detail
            default:
                context = nil
            }
            if let context {
                fields.append("coding_path=\(context.codingPath.map(\.stringValue).joined(separator: "."))")
                fields.append("detail=\(context.debugDescription)")
                underlying = context.underlyingError ?? underlying
            }
            for key in nsError.userInfo.keys.sorted() where key != NSUnderlyingErrorKey {
                let detail = isSensitiveKey(key) ? "<redacted>" : String(describing: nsError.userInfo[key]!)
                fields.append("\(key)=\(detail)")
            }
            values.append(truncate(sanitize(fields.joined(separator: " "), redacting: secrets), maximumBytes: 480))
            current = underlying
        }
        if current != nil, values.count >= 8 {
            values.append("<chain truncated>")
        }
        return truncate(values.joined(separator: " <- "))
    }

    static func sanitize(_ value: String, redacting secrets: [String] = []) -> String {
        let value = secrets.filter { !$0.isEmpty }.reduce(value) { result, secret in
            result.replacingOccurrences(of: secret, with: "<redacted>")
        }
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let redacted = try? JSONSerialization.data(withJSONObject: redactJSON(object), options: [.sortedKeys]),
           let json = String(data: redacted, encoding: .utf8) {
            return truncate(json)
        }
        return truncate(sanitizeText(value))
    }

    private static func sanitizeText(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)\b(?:cookie|set-cookie|authorization)\s*:[^\r\n]*"#,
            #"(?i)\b(?:Bearer|Basic)\s+[^\s,;\"'<>]+"#,
            #"(?i)(?:[\"']?(?:[a-z_-]*token|password|passwd|secret|[a-z_-]*api[_-]?key|authorization|cookies?|private[_-]?key|session|database[_-]?url)[\"']?)\s*[:=]\s*(?:\"(?:\\.|[^\"\\])*\"|'[^']*'|[^\s,;}]+)"#,
            #"(?i)\bsk-(?:or-v1-|proj-|ant-)?[A-Za-z0-9_-]{12,}"#,
            #"\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        result = result.replacingOccurrences(
            of: #"(?i)((?:https?|postgres(?:ql)?|mysql|redis)://)[^/@\s]+@"#,
            with: "$1<redacted>@",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(https?://[^?\s\"<>]+)\?[^\s\"<>]*"#,
            with: "$1?<redacted>",
            options: .regularExpression
        )
        return result
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func truncate(_ value: String, maximumBytes: Int = maximumMessageLength) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        let marker = " <truncated:\(value.utf8.count)bytes>"
        var prefix = String(decoding: value.utf8.prefix(maximumBytes - marker.utf8.count - 3), as: UTF8.self)
        while prefix.utf8.count + marker.utf8.count > maximumBytes {
            prefix.removeLast()
        }
        return prefix + marker
    }

    private static func redactJSON(_ value: Any, key: String? = nil) -> Any {
        if let key, isSensitiveKey(key) { return "<redacted>" }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redactJSON(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] { return array.map { redactJSON($0) } }
        if let string = value as? String { return sanitizeText(string) }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return normalized.hasSuffix("token") || [
            "apikey", "xapikey", "password", "passwd", "authorization", "cookie", "cookies",
            "setcookie", "secret", "privatekey", "session", "databaseurl",
        ].contains(normalized)
    }
}

struct ServerDiagnosticsMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
        let started = ContinuousClock.now
        let requestID = request.diagnosticRequestID
        request.logger[metadataKey: "request-id"] = .string(requestID)
        return next.respond(to: request).map { response in
            response.headers.replaceOrAdd(name: "X-Request-ID", value: requestID)
            if response.status.code >= 400 {
                Self.report(Abort(response.status), request: request, started: started, requestID: requestID)
            }
            return response
        }.flatMapErrorThrowing { error in
            Self.report(error, request: request, started: started, requestID: requestID)
            return Self.errorResponse(for: error, request: request, requestID: requestID)
        }
    }

    private static func report(_ error: any Error, request: Request, started: ContinuousClock.Instant, requestID: String) {
        let elapsed = started.duration(to: .now)
        let durationMilliseconds = elapsed.components.seconds * 1_000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        var metadata: Logger.Metadata = [
            "status": .stringConvertible((error as? any AbortError)?.status.code ?? 500),
            "duration_ms": .stringConvertible(durationMilliseconds),
            "user_agent": .string(request.headers.first(name: "User-Agent") ?? ""),
            "content_type": .string(request.headers.contentType?.description ?? ""),
            "request_bytes": .stringConvertible(request.body.data?.readableBytes ?? 0),
            "account": .string(request.auth.get(AuthenticatedBrowserUser.self)?.appleSubject ?? "anonymous"),
        ]
        if let body = request.body.string {
            if request.url.path.hasPrefix("/v1/ai/"),
               let data = body.data(using: .utf8),
               var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["prompt", "instructions", "images"] {
                    if let text = object[key] as? String {
                        object[key] = "<\(text.utf8.count) bytes; see provider failure record>"
                    } else if let images = object[key] as? [Any] {
                        object[key] = "<\(images.count) images>"
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: object) {
                    metadata["request_context"] = .string(DiagnosticFormatter.sanitize(String(decoding: data, as: UTF8.self)))
                }
            } else {
                metadata["request_context"] = .string(DiagnosticFormatter.sanitize(body))
            }
        }
        DiagnosticFormatter.log(
            error,
            logger: request.logger,
            requestID: requestID,
            operation: "http \(request.method.rawValue) \(request.url.path)",
            metadata: metadata
        )
    }

    private static func errorResponse(for error: any Error, request: Request, requestID: String) -> Response {
        let status = (error as? any AbortError)?.status ?? .internalServerError
        let reason: String
        if let abort = error as? any AbortError {
            reason = abort.reason
        } else {
            reason = "Something went wrong."
        }
        var headers = (error as? any AbortError)?.headers ?? HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: "X-Request-ID", value: requestID)
        struct ErrorBody: Encodable {
            let error = true
            let reason: String
        }
        let body = (try? JSONEncoder().encode(ErrorBody(reason: reason))) ?? Data(#"{"error":true,"reason":"Request failed."}"#.utf8)
        return Response(status: status, headers: headers, body: .init(data: body))
    }
}
