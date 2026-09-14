import Foundation
import Testing
@testable import GlassConnectionKit

@Suite("EndpointProfile contract")
struct EndpointProfileTests {
    private let endpointID = EndpointID(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )
    private let credentialID = CredentialID(
        rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    )
    private let writerID = WriterID(
        rawValue: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    )
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Canonical codec round-trips the complete version-one record")
    func canonicalRoundTrip() throws {
        let profile = try makeProfile(tags: [" production ", "alpha", "alpha"])

        let data = try EndpointProfileCodec.encode(profile)
        let decoded = try EndpointProfileCodec.decode(data)

        #expect(decoded == profile)
        #expect(decoded.tags == ["alpha", "production"])
        #expect(decoded.credentialID == credentialID)
        #expect(String(decoding: data, as: UTF8.self).contains("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test("Stable ID wrappers encode as lowercase UUID strings")
    func stableIdentifierEncoding() throws {
        let data = try JSONEncoder().encode(endpointID)
        #expect(String(decoding: data, as: UTF8.self) == "\"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\"")
        #expect(try JSONDecoder().decode(EndpointID.self, from: data) == endpointID)
    }

    @Test("Required fields normalize without changing endpoint identity")
    func requiredFieldNormalization() throws {
        let profile = try EndpointProfile(
            id: endpointID,
            displayName: "  Production  ",
            host: " host.example.com\n",
            username: " deploy ",
            appVisibility: .glasShOnly,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastWriterID: writerID
        )

        #expect(profile.id == endpointID)
        #expect(profile.displayName == "Production")
        #expect(profile.host == "host.example.com")
        #expect(profile.username == "deploy")
    }

    @Test("Unsupported schema versions fail closed")
    func unsupportedSchemaVersion() {
        #expect(throws: EndpointProfileValidationError.unsupportedSchemaVersion(2)) {
            try makeProfile(schemaVersion: 2)
        }
    }

    @Test("Empty required fields fail validation")
    func emptyRequiredField() {
        #expect(throws: EndpointProfileValidationError.emptyField("host")) {
            try EndpointProfile(
                id: endpointID,
                displayName: "Production",
                host: "  ",
                username: "deploy",
                appVisibility: .glassFamily,
                createdAt: createdAt,
                updatedAt: createdAt,
                lastWriterID: writerID
            )
        }
    }

    @Test("Self and duplicate jump endpoint references fail validation")
    func invalidJumpReferences() {
        #expect(throws: EndpointProfileValidationError.selfReferentialJumpEndpoint) {
            try makeProfile(jumpEndpointIDs: [endpointID])
        }

        let jumpID = EndpointID(
            rawValue: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        )
        #expect(throws: EndpointProfileValidationError.duplicateJumpEndpoint(jumpID)) {
            try makeProfile(jumpEndpointIDs: [jumpID, jumpID])
        }
    }

    @Test("Invalid update and deletion chronology fails validation")
    func invalidChronology() {
        #expect(throws: EndpointProfileValidationError.updatedBeforeCreation) {
            try makeProfile(updatedAt: createdAt.addingTimeInterval(-1))
        }
        #expect(throws: EndpointProfileValidationError.deletionBeforeCreation) {
            try makeProfile(deletedAt: createdAt.addingTimeInterval(-1))
        }
    }

    @Test("Unknown fields do not prevent a version-one reader from decoding")
    func unknownFieldsAreIgnored() throws {
        let profile = try makeProfile()
        let encoded = try EndpointProfileCodec.encode(profile)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["futureOverlayHint"] = "preserve raw payload at repository boundary"
        let extended = try JSONSerialization.data(withJSONObject: object)

        #expect(try EndpointProfileCodec.decode(extended) == profile)
    }

    @Test("Wire payload contains only the approved non-secret fields")
    func payloadAllowlist() throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: EndpointProfileCodec.encode(makeProfile()))
                as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "appVisibility",
            "createdAt",
            "credentialID",
            "displayName",
            "host",
            "id",
            "jumpEndpointIDs",
            "lastWriterID",
            "port",
            "schemaVersion",
            "tags",
            "updatedAt",
            "username",
        ])
        #expect(object["password"] == nil)
        #expect(object["privateKey"] == nil)
        #expect(object["hostFingerprint"] == nil)
    }

    @Test("Deletion timestamps serialize as tombstones")
    func tombstoneEncoding() throws {
        let object = try #require(
            JSONSerialization.jsonObject(
                with: EndpointProfileCodec.encode(
                    makeProfile(deletedAt: createdAt.addingTimeInterval(60))
                )
            ) as? [String: Any]
        )
        #expect(object["deletedAt"] != nil)
    }

    @Test("Visibility raw values are stable and exhaustive")
    func visibilityContract() {
        #expect(EndpointAppVisibility.allCases == [.glasShOnly, .glassdbOnly, .glassFamily])
        #expect(EndpointAppVisibility.glasShOnly.rawValue == "glasShOnly")
        #expect(EndpointAppVisibility.glassdbOnly.rawValue == "glassdbOnly")
        #expect(EndpointAppVisibility.glassFamily.rawValue == "glassFamily")
    }

    private func makeProfile(
        schemaVersion: UInt16 = EndpointProfile.currentSchemaVersion,
        jumpEndpointIDs: [EndpointID] = [],
        tags: [String] = [],
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> EndpointProfile {
        try EndpointProfile(
            schemaVersion: schemaVersion,
            id: endpointID,
            displayName: "Production",
            host: "host.example.com",
            port: 22,
            username: "deploy",
            credentialID: credentialID,
            jumpEndpointIDs: jumpEndpointIDs,
            tags: tags,
            appVisibility: .glassFamily,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt,
            lastWriterID: writerID
        )
    }
}
