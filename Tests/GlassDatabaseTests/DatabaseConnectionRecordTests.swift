//
//  DatabaseConnectionRecordTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The connection record changed shape in the move: six SSH fields left (D7) and the version
//  number the format never had arrived. These cover the migration and the transport rules that
//  depend on it, not the encoder's field list.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Database connection record")
struct DatabaseConnectionRecordTests {

    /// glassdb's own JSON, with no version and its full SSH section.
    private func versionOneJSON(useSSHTunnel: Bool) -> Data {
        """
        {
          "id": "8B1E5C2A-0000-4000-8000-000000000001",
          "name": "Fixture",
          "engine": "mysql",
          "host": "db.example.test",
          "port": 3306,
          "username": "reader",
          "defaultDatabase": "gpt_test",
          "useSSHTunnel": \(useSSHTunnel),
          "sshHost": "jump.example.test",
          "sshPort": 2222,
          "sshUsername": "operator",
          "sshAuthMethod": "sshKey",
          "sshKeyID": "8B1E5C2A-0000-4000-8000-0000000000FF",
          "databaseCredentialPolicy": "glassdbOnly",
          "sshCredentialPolicy": "sharedWithGlas",
          "useTLS": true,
          "isFavorite": true,
          "colorTag": "blue",
          "dateAdded": 760000000,
          "tags": ["Production"]
        }
        """.data(using: .utf8)!
    }

    @Test("A version-1 record decodes as version 1 and keeps everything but its SSH section")
    func versionOneDecodes() throws {
        let record = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: versionOneJSON(useSSHTunnel: true))
        #expect(record.schemaVersion == 1)
        #expect(record.name == "Fixture")
        #expect(record.host == "db.example.test")
        #expect(record.port == 3306)
        #expect(record.username == "reader")
        #expect(record.defaultDatabase == "gpt_test")
        #expect(record.useTLS)
        #expect(record.isFavorite)
        #expect(record.colorTag == .blue)
        #expect(record.tags == ["Production"])
    }

    @Test("`useSSHTunnel` migrates to `usesHostTunnel`: the intent carries, the five SSH fields do not")
    func tunnelIntentMigrates() throws {
        let tunnelled = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: versionOneJSON(useSSHTunnel: true))
        #expect(tunnelled.usesHostTunnel)
        let direct = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: versionOneJSON(useSSHTunnel: false))
        #expect(!direct.usesHostTunnel)
    }

    @Test("Re-encoding a version-1 record rewrites it at version 2 with no SSH keys left in the JSON")
    func encodingIsTheRewrite() throws {
        let record = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: versionOneJSON(useSSHTunnel: true))
        let encoded = try JSONEncoder().encode(record)
        let fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(fields["schemaVersion"] as? Int == 2)
        #expect(fields["usesHostTunnel"] as? Bool == true)
        for gone in ["useSSHTunnel", "sshHost", "sshPort", "sshUsername", "sshAuthMethod", "sshKeyID", "sshCredentialPolicy"] {
            #expect(fields[gone] == nil, "\(gone) must not survive the rewrite")
        }

        // The rewritten record round-trips at the current version.
        let again = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: encoded)
        #expect(again.schemaVersion == DatabaseConnectionConfig.currentSchemaVersion)
        #expect(again == record.withSchemaVersion(DatabaseConnectionConfig.currentSchemaVersion))
    }

    @Test("The renamed credential policy still decodes glassdb's raw value, and a shared database password normalizes to private")
    func credentialPolicyCompatibility() throws {
        #expect(CredentialStoragePolicy(rawValue: "glassdbOnly") == .appOnly)
        #expect(CredentialStoragePolicy.databasePolicies == [.appOnly, .requireAuthentication])

        let record = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: versionOneJSON(useSSHTunnel: false))
        #expect(record.databaseCredentialPolicy == .appOnly)
    }

    @Test("A record written as shared normalizes on read: database passwords are never shared")
    func sharedDatabasePolicyNormalizes() throws {
        let json = """
        {"id":"8B1E5C2A-0000-4000-8000-000000000002","name":"Shared","engine":"postgresql",
         "host":"db.example.test","port":5432,"username":"reader",
         "databaseCredentialPolicy":"sharedWithGlas","dateAdded":760000000}
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: json)
        #expect(record.databaseCredentialPolicy == .appOnly)
    }
}

private extension DatabaseConnectionConfig {
    /// The decoded version is the only field the rewrite changes, so compare like with like.
    func withSchemaVersion(_ version: Int) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(
            id: id, name: name, engine: engine, host: host, port: port, username: username,
            defaultDatabase: defaultDatabase, usesHostTunnel: usesHostTunnel,
            databaseCredentialPolicy: databaseCredentialPolicy, useTLS: useTLS,
            isFavorite: isFavorite, colorTag: colorTag, dateAdded: dateAdded,
            lastConnected: lastConnected, tags: tags, schemaVersion: version
        )
    }
}
