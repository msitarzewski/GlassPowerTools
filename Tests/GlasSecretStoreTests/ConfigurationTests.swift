import Testing
import Foundation
import Security
@testable import GlasSecretStore

@Suite("SecretStoreConfiguration")
struct ConfigurationTests {
    @Test("Secret access policies are stable and exhaustive")
    func secretAccessPolicies() {
        #expect(SecretAccessPolicy.allCases == [.standard, .userPresence])
        #expect(SecretAccessPolicy.userPresence.rawValue == "userPresence")
    }


    @Test("Default init values")
    func defaultInit() {
        let config = SecretStoreConfiguration()
        #expect(config.serviceNamePrefix == "sh.glas")
        #expect(config.accessGroup == nil)
        #expect(config.migrationMarkerComment == "sh.glas.secretstore.v1")
        #expect(config.legacyServiceNamePrefixes.isEmpty)
    }

    @Test("Custom prefix produces correct derived service names")
    func customPrefixDerivedNames() {
        let config = SecretStoreConfiguration(serviceNamePrefix: "com.test")
        #expect(config.passwordsService == "com.test.passwords")
        #expect(config.sshPasswordsService == "com.test.sshpasswords")
        #expect(config.sshKeysPrivateService == "com.test.sshkeys.private")
        #expect(config.sshKeysPassphraseService == "com.test.sshkeys.passphrase")
        #expect(config.sealedP256Service == "com.test.sshkeys.sealedp256")
        #expect(config.sealedP256TagService == "com.test.sshkeys.sealedp256.tag")
        #expect(config.sshHostTrustService == "com.test.ssh.hosttrust")
    }

    @Test("Glass-family credential accounts preserve UUID identity")
    func glassFamilyCredentialAccounts() {
        let profileID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        #expect(
            GlassFamilyCredentialAccount.databasePassword(profileID: profileID)
                == "database:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        #expect(
            GlassFamilyCredentialAccount.sshPassword(profileID: profileID)
                == "ssh:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
    }
}
