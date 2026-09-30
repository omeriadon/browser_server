import NIOSSL
import Fluent
import FluentPostgresDriver
import PostgresNIO
import Vapor

/// configures your application
func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let databaseHostname = Environment.get("DATABASE_HOST") ?? "localhost"
    let databaseTLS: PostgresConnection.Configuration.TLS = ["localhost", "127.0.0.1", "::1"].contains(databaseHostname.lowercased())
        ? .disable
        : .prefer(try .init(configuration: .clientDefault))

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: databaseHostname,
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: databaseTLS)
    ), as: .psql)

    app.browserAuthentication = try await BrowserAuthentication.make(for: app.environment)

    app.migrations.add(CreateSyncSnapshot())

    // register routes
    try routes(app)
}
