import Foundation
import Testing
@testable import GlassSSHTransport

@Suite("Transport ownership and identity")
struct SSHTransportOwnershipTests {
    @Test func finalReleaseClosesExactlyOnceAndClosingRefusesNewOwners() {
        var ownership = SSHTransportOwnership()
        let a = UUID(), b = UUID()
        let acquiredA = ownership.acquire(a), acquiredB = ownership.acquire(b)
        #expect(acquiredA && acquiredB)
        let releasedA = ownership.release(a)
        #expect(!releasedA)                     // still owned by b
        let releasedB = ownership.release(b)
        #expect(releasedB)                      // last owner → closing, once
        #expect(ownership.isClosing)
        let releasedAgain = ownership.release(b)
        #expect(!releasedAgain)                 // never twice
        let acquiredWhileClosing = ownership.acquire(UUID())
        #expect(!acquiredWhileClosing)          // closing refuses owners
    }

    @Test func releasingAnUnknownOwnerDoesNothing() {
        var ownership = SSHTransportOwnership()
        let acquired = ownership.acquire(UUID())
        let releasedUnknown = ownership.release(UUID())
        #expect(acquired && !releasedUnknown)
        #expect(!ownership.isClosing)
    }

    @Test func forceCloseDropsOwnersAndReturnsTrueOnce() {
        var ownership = SSHTransportOwnership()
        _ = ownership.acquire(UUID())
        let first = ownership.forceClose(), second = ownership.forceClose()
        #expect(first && !second)
        #expect(ownership.owners.isEmpty)
    }

    @Test func identityDependsOnRouteCredentialsOptionsAndPolicy() {
        let endpoint = SSHEndpoint(host: " ssh://Example.local ", port: 22, username: "me")
        #expect(endpoint.host == "Example.local")
        let key = UUID()
        let hop = SSHHop(recordID: UUID(), displayName: "Box", endpoint: endpoint, credential: .privateKey(keyID: key))
        let route = SSHRoute(target: hop)
        #expect(route.identity == SSHRoute(target: hop).identity)

        var otherCredential = hop
        otherCredential.credential = .password(profileID: key)
        #expect(route.identity != SSHRoute(target: otherCredential).identity)

        var legacy = hop
        legacy.options.allowLegacyAlgorithms = true
        #expect(route.identity != SSHRoute(target: legacy).identity)

        #expect(route.identity != SSHRoute(target: hop, trustPolicy: .strict).identity)
        #expect(route.identity != SSHRoute(target: hop, jumps: [hop]).identity)
    }

    @Test func endpointValidationMatchesGlasSH() {
        #expect(throws: SSHTransportError.invalidHost("")) { try SSHEndpoint(host: "   ", username: "me").validate() }
        #expect(throws: SSHTransportError.invalidPort(0)) { try SSHEndpoint(host: "h", port: 0, username: "me").validate() }
        #expect(throws: SSHTransportError.invalidPort(70_000)) { try SSHEndpoint(host: "h", port: 70_000, username: "me").validate() }
        #expect(throws: Never.self) { try SSHEndpoint(host: "h", port: 22, username: "me").validate() }
    }

    @Test func credentialReferenceBridgesToCatalogIDs() {
        let id = UUID()
        #expect(SSHCredentialReference.password(profileID: id).credentialID?.rawValue == id)
        #expect(SSHCredentialReference.privateKey(keyID: id).credentialID?.rawValue == id)
        #expect(SSHCredentialReference.agent.credentialID == nil)
        #expect(SSHCredentialReference.custom("x").credentialID == nil)
        #expect(SSHCredentialReference.privateKey(keyID: id).usesPrivateKey)
    }
}
