import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        "browser sync server"
    }

    let versioned = app.grouped("v1")
    versioned.post("auth", "apple") { request async throws -> AuthenticationResponse in
        let credentials = try request.content.decode(AppleCredentials.self)
        guard !credentials.identityToken.isEmpty else {
            throw Abort(.badRequest, reason: "Missing Apple identity token.")
        }

        let subject = try await request.application.browserAuthentication.verifyAppleIdentityToken(
            credentials.identityToken,
            client: request.client
        )
        return try await request.application.browserAuthentication.issueSession(for: subject)
    }

    let authenticated = versioned
        .grouped(BrowserSessionAuthenticator(authentication: app.browserAuthentication))
        .grouped(AuthenticatedBrowserUser.guardMiddleware())

    authenticated.get("sync") { request async throws -> [SyncSnapshotResponse] in
        let user = try request.auth.require(AuthenticatedBrowserUser.self)
        return try await SyncSnapshot.query(on: request.db)
            .filter(\.$appleSubject == user.appleSubject)
            .all()
            .map(\.response)
    }

    authenticated.on(.PUT, ["sync"], body: .collect(maxSize: "7mb")) { request async throws -> SyncSnapshotResponse in
        let user = try request.auth.require(AuthenticatedBrowserUser.self)
        let body = try request.content.decode(SyncSnapshotRequest.self)
        guard body.payload.count <= 5_000_000 else {
            throw Abort(.payloadTooLarge)
        }

        let snapshot = try await SyncSnapshot.query(on: request.db)
            .filter(\.$appleSubject == user.appleSubject)
            .filter(\.$deviceID == body.deviceID)
            .first() ?? SyncSnapshot(
                appleSubject: user.appleSubject,
                deviceID: body.deviceID
            )
        snapshot.payload = body.payload
        snapshot.revision += 1
        snapshot.updatedAt = .now
        try await snapshot.save(on: request.db)
        return snapshot.response
    }
}
