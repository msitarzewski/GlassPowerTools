import Foundation
import Testing
@testable import GlassConnectionKit

@Suite("Host address")
struct HostProfileAddressTests {
    @Test func normalisesAndValidatesAddresses() throws {
        #expect(try HostProfile(displayName: "a", address: "  Build.Example.COM ").address == "build.example.com")
        #expect(try HostProfile(displayName: "a", address: "192.0.2.6").address == "192.0.2.6")
        #expect(try HostProfile(displayName: "a", address: "[FE80::1%en0]").address == "fe80::1%en0")
        #expect(try HostProfile(displayName: "a").address == nil)
        #expect(throws: HostProfileError.invalidAddress) { try HostProfile(displayName: "a", address: "") }
        #expect(throws: HostProfileError.invalidAddress) { try HostProfile(displayName: "a", address: "has space") }
        #expect(throws: HostProfileError.invalidAddress) { try HostProfile(displayName: "a", address: "-bad.example") }
        #expect(throws: HostProfileError.invalidAddress) { try HostProfile(displayName: "a", address: "user@host") }
        #expect(throws: HostProfileError.invalidAddress) { try HostProfile(displayName: "a", address: "host:22") }
    }

    @Test func schemaOneRecordWithoutAddressDecodesAndRoundTripsWithOne() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let legacy = try HostProfile(displayName: "alpha", aliases: ["alpha.local"])
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any])
        #expect(json["address"] == nil, "absent, not null, when unset")
        json.removeValue(forKey: "address")
        let decodedLegacy = try decoder.decode(HostProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decodedLegacy.address == nil && decodedLegacy == legacy)

        let addressed = try HostProfile(id: legacy.id, displayName: "alpha", address: "192.0.2.6", aliases: ["alpha.local"],
                                        createdAt: legacy.createdAt, updatedAt: legacy.updatedAt, lastWriterID: legacy.lastWriterID)
        let data = try encoder.encode(addressed)
        #expect(try decoder.decode(HostProfile.self, from: data) == addressed)
        #expect(addressed != legacy, "the address takes part in equality, so a change is a revision")

        // A reader that predates the field: the same keyed decode ignores unknown keys.
        var withExtra = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        withExtra["futureKey"] = "x"
        #expect(try decoder.decode(HostProfile.self, from: JSONSerialization.data(withJSONObject: withExtra)).address == "192.0.2.6")

        // A malformed address from another writer is dropped, not fatal.
        var malformed = withExtra
        malformed["address"] = "not valid!"
        #expect(try decoder.decode(HostProfile.self, from: JSONSerialization.data(withJSONObject: malformed)).address == nil)
    }
}
