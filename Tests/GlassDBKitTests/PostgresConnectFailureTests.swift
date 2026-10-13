import Foundation
import Testing
@testable import GlassDBKit

/// PostgresNIO keeps a `PSQLError`'s details out of its description, so a wrong password reached
/// the user as "The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)" (measured
/// 2026-10-13). `PostgreSQLEngine.connectFailure` passes the server's own words on. Against the
/// test server, gated as the other live tests are (`GPT_DB_TEST_HOST`, `GPT_DB_TEST_PG_PORT`).
@Suite struct PostgresConnectFailureTests {
    private static func value(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    @Test(.enabled(if: value("GPT_DB_TEST_HOST") != nil))
    func aWrongPasswordIsTheServersOwnWords() async throws {
        let host = Self.value("GPT_DB_TEST_HOST")!
        let port = Self.value("GPT_DB_TEST_PG_PORT").flatMap(Int.init) ?? 5_432
        let user = Self.value("GPT_DB_TEST_PG_USER") ?? "gpt_test"
        do {
            let connection = try await PostgreSQLEngine().connect(
                host: host, port: port, username: user, password: "not-the-password-\(UUID())",
                database: nil, tlsPolicy: .disabled)
            try? await connection.close()
            Issue.record("connected with a wrong password")
        } catch DatabaseError.server(let message) {
            #expect(message.contains("password authentication failed"), "\(message)")
        } catch {
            Issue.record("a wrong password read \"\(error.localizedDescription)\"")
        }
    }
}
