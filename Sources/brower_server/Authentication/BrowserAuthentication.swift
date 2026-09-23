import JWTKit
import Vapor

struct AppleCredentials: Content {
    var identityToken: String
}

struct AuthenticationResponse: Content {
    var token: String
}

struct AuthenticatedBrowserUser: Authenticatable, Sendable {
    var appleSubject: String
}

struct BrowserSessionAuthenticator: AsyncBearerAuthenticator {
    let authentication: BrowserAuthentication

    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        guard let subject = try? await authentication.verifySession(bearer.token) else {
            return
        }
        request.auth.login(AuthenticatedBrowserUser(appleSubject: subject))
    }
}

struct BrowserAuthentication: Sendable {
    private let appleClientID: String
    private let sessionKeys: JWTKeyCollection

    static func make(for environment: Environment) async throws -> Self {
        let appleClientID = Environment.get("APPLE_CLIENT_ID")
            ?? (environment == .testing ? "com.omeriadon.browser" : nil)
        let sessionSecret = Environment.get("SESSION_SECRET")
            ?? (environment == .testing ? String(repeating: "test", count: 16) : nil)

        guard let appleClientID, !appleClientID.isEmpty else {
            throw Abort(.internalServerError, reason: "APPLE_CLIENT_ID is not configured.")
        }
        guard let sessionSecret, sessionSecret.utf8.count >= 32 else {
            throw Abort(.internalServerError, reason: "SESSION_SECRET must contain at least 32 bytes.")
        }

        let sessionKeys = await JWTKeyCollection().add(
            hmac: HMACKey(from: sessionSecret),
            digestAlgorithm: .sha256,
            kid: "browser-session"
        )
        return Self(appleClientID: appleClientID, sessionKeys: sessionKeys)
    }

    func verifyAppleIdentityToken(_ token: String, client: any Client) async throws -> String {
        let response: ClientResponse
        do {
            response = try await client.get("https://appleid.apple.com/auth/keys")
        } catch {
            throw Abort(.badGateway, reason: "Unable to load Apple's signing keys.")
        }
        let readableBytes = response.body?.readableBytes ?? 0
        guard response.status == .ok,
              let keysJSON = response.body?.getString(at: 0, length: readableBytes)
        else {
            throw Abort(.badGateway, reason: "Unable to load Apple's signing keys.")
        }

        do {
            let appleKeys = try await JWTKeyCollection().add(jwksJSON: keysJSON)
            let payload = try await appleKeys.verify(token, as: AppleIdentityPayload.self)
            try payload.audience.verifyIntendedAudience(includes: appleClientID)
            return payload.subject.value
        } catch {
            throw Abort(.unauthorized, reason: "Invalid Apple identity token.")
        }
    }

    func issueSession(for subject: String) async throws -> AuthenticationResponse {
        let payload = BrowserSessionPayload(
            subject: SubjectClaim(value: subject),
            issuer: IssuerClaim(value: "browser-sync-server"),
            expiration: ExpirationClaim(value: .now.addingTimeInterval(90 * 24 * 60 * 60))
        )
        return AuthenticationResponse(
            token: try await sessionKeys.sign(payload, kid: "browser-session")
        )
    }

    func verifySession(_ token: String) async throws -> String {
        try await sessionKeys.verify(token, as: BrowserSessionPayload.self).subject.value
    }
}

private struct AppleIdentityPayload: JWTPayload {
    var issuer: IssuerClaim
    var audience: AudienceClaim
    var expiration: ExpirationClaim
    var issuedAt: IssuedAtClaim
    var subject: SubjectClaim

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case audience = "aud"
        case expiration = "exp"
        case issuedAt = "iat"
        case subject = "sub"
    }

    func verify(using _: some JWTAlgorithm) throws {
        try expiration.verifyNotExpired()
        guard issuer.value == "https://appleid.apple.com" else {
            throw JWTError.claimVerificationFailure(
                failedClaim: issuer,
                reason: "Token was not issued by Apple."
            )
        }
    }
}

private struct BrowserSessionPayload: JWTPayload {
    var subject: SubjectClaim
    var issuer: IssuerClaim
    var expiration: ExpirationClaim

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case issuer = "iss"
        case expiration = "exp"
    }

    func verify(using _: some JWTAlgorithm) throws {
        try expiration.verifyNotExpired()
        guard issuer.value == "browser-sync-server" else {
            throw JWTError.claimVerificationFailure(
                failedClaim: issuer,
                reason: "Invalid session issuer."
            )
        }
    }
}

private struct BrowserAuthenticationKey: StorageKey {
    typealias Value = BrowserAuthentication
}

extension Application {
    var browserAuthentication: BrowserAuthentication {
        get {
            guard let authentication = storage[BrowserAuthenticationKey.self] else {
                fatalError("Browser authentication was accessed before configuration.")
            }
            return authentication
        }
        set {
            storage[BrowserAuthenticationKey.self] = newValue
        }
    }
}
