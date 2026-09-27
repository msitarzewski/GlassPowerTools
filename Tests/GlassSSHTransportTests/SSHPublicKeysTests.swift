import Foundation
import Testing
import Crypto
import GlasSecretStore
@testable import GlassSSHTransport

// Throwaway keys generated with `ssh-keygen` for this test only; they have never been used
// anywhere and are not secrets. The expected lines are what ssh-keygen wrote to the `.pub` files.
@Suite("Public key derivation")
struct SSHPublicKeysTests {
    static let ed25519PrivateKey = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD3YRYq3T2S3DeG3itZcfXO3GgTfLpwstlCEGe3DWjg+AAAAJjZbHn52Wx5
+QAAAAtzc2gtZWQyNTUxOQAAACD3YRYq3T2S3DeG3itZcfXO3GgTfLpwstlCEGe3DWjg+A
AAAEDR+QNWVqxLejisTJ61KaLSo6imru0hgq6hY8sTtXPb7fdhFirdPZLcN4beK1lx9c7c
aBN8unCy2UIQZ7cNaOD4AAAAD2ZpeHR1cmUtZWQyNTUxOQECAwQFBg==
-----END OPENSSH PRIVATE KEY-----
"""
    static let ed25519PublicLine = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPdhFirdPZLcN4beK1lx9c7caBN8unCy2UIQZ7cNaOD4 fixture-ed25519"
    static let rsaPrivateKey = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
NhAAAAAwEAAQAAAQEAu/ThUCY4TUT5ENFUSOK68DGEgyHH+px/AuZncdUqVwBbACnnsz8S
0/8JUw1zyKvEWdi+9bfCl1xSuSSN0S4zbC9npMvmiY8pERDT6v8fp+YnhQxnt1qs1cmaZ5
sHKOht9m1Zu/A+eLGyAyNUWgDBz6FzrsXN63Ai8DSxvj2JJWLvzcpGEn9kOJASjuDYL4VB
hGxagK0Z073S7zszmsfdDYM63stm7ynH0YXxf3z0Psi44uPans4Z026VmFWl8yuXc147cz
ZpMBzQJw6AOa3Mh1wuJuBTLX/XmmodRiMyIaQmz14ZpnfpXHSnSfs0r1H/slG4fmQRUrQ/
9W/EGEuLXwAAA8BVeZknVXmZJwAAAAdzc2gtcnNhAAABAQC79OFQJjhNRPkQ0VRI4rrwMY
SDIcf6nH8C5mdx1SpXAFsAKeezPxLT/wlTDXPIq8RZ2L71t8KXXFK5JI3RLjNsL2eky+aJ
jykRENPq/x+n5ieFDGe3WqzVyZpnmwco6G32bVm78D54sbIDI1RaAMHPoXOuxc3rcCLwNL
G+PYklYu/NykYSf2Q4kBKO4NgvhUGEbFqArRnTvdLvOzOax90Ngzrey2bvKcfRhfF/fPQ+
yLji49qezhnTbpWYVaXzK5dzXjtzNmkwHNAnDoA5rcyHXC4m4FMtf9eaah1GIzIhpCbPXh
mmd+lcdKdJ+zSvUf+yUbh+ZBFStD/1b8QYS4tfAAAAAwEAAQAAAQAhvcs47TOMQ4aGy11b
HEC839bPB6Bzz+ZJKf2GBONt7OVpORycJAWIQy90VmTjsFo2Wt+lEtD/BRbgn7xJwgZ/NF
9hySzgou+XXbL9a8FODdYoX1q7Iq8GTgPG96CoallbNLQ4Nd+xIQ043P3Gjn48fNpclKvr
yRysjHkgEsHtEO/t8uSbtiTYrpQ1ni4N3NFnnqxH0fMrroLEKBS0UCgM+uNTvjIExzrNyK
h+LTbQj7FwTCTehct4pGuYqYA/sPjDlb4roE2wsiwFDNN+8sZR9S2R9/P77U4/whfZBbdz
nD75cD3eEAi8n4n3I0KuXMUrt9m1V/97yLlwS2pRlQoRAAAAgAUJzr3RKuWpUVzoieksHg
UdC4yNlMh5gF2zEPlGfwSnumLdh+CZxKnluVIuC5uu7PRfVvLQ/1R/d+i/qein54bPzp7S
Lk/9yHGBnvdi9EHboeS3iuhDHWeOGylC64x2IH50nxuh7H0GzakgNg8lqmOBoiyIO4S7dT
mtQzFzg93HAAAAgQDl04pscZmSWkHlS7USKkentrJw2BUUZEXe8/6IfrIOWjgyUNuzQ/na
wjTYb/DroeyXIjx68vYvJwdDgdTiZG6diOxmVoa5FVAb50BF7a+obuFZrb2AvxeKmbnRyS
jQCuElSaM8fEzeh4rP+SpeVV4t1tlv/kE8jr0jEDSMmJlx1wAAAIEA0VymSBD8b/+F1wDt
PnVIaNBFOAwSs4TjBYbZVunuw1bF8iZ1cM1uYn7NXDE3G08aMJe7vKgbrP9lgmnyyQ77zs
EzD8+gMDPemLf8hRxa+5XY0cAEVokZl89whse7NIR6wHfuA4Uf8wjIMCqlD6yKn3k5tyo2
4BXMTqMbhYzPEbkAAAALZml4dHVyZS1yc2E=
-----END OPENSSH PRIVATE KEY-----
"""
    static let rsaPublicLine = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC79OFQJjhNRPkQ0VRI4rrwMYSDIcf6nH8C5mdx1SpXAFsAKeezPxLT/wlTDXPIq8RZ2L71t8KXXFK5JI3RLjNsL2eky+aJjykRENPq/x+n5ieFDGe3WqzVyZpnmwco6G32bVm78D54sbIDI1RaAMHPoXOuxc3rcCLwNLG+PYklYu/NykYSf2Q4kBKO4NgvhUGEbFqArRnTvdLvOzOax90Ngzrey2bvKcfRhfF/fPQ+yLji49qezhnTbpWYVaXzK5dzXjtzNmkwHNAnDoA5rcyHXC4m4FMtf9eaah1GIzIhpCbPXhmmd+lcdKdJ+zSvUf+yUbh+ZBFStD/1b8QYS4tf fixture-rsa"
    static let passphrasePrivateKey = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCv2NosWQ
sHJ5WluojzyhNcAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAICmwNecHBCSVRK5k
weh9EQseq4AjkgPD8CLau+/HlmFsAAAAoBR5ZopHeXII4jGIk76iW+Ln5Shrq8vl3ovXKV
vWQ/t5jh3sAs5fTpTmjE9snKsLmG9eDujUxedBxGWNmlVDdYo6F3OSdvanSuMcBIt8T5me
gTD0X7TW156yrmyG3YmeDErEcUHgy0+Svd3yaO5lWv1IFIsddhQREjO4bvxdpZ4rNiykqB
AchkG92DPg9/h94Hlidb8Dl6fz0aV2/rQzwgI=
-----END OPENSSH PRIVATE KEY-----
"""
    static let passphrasePublicLine = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICmwNecHBCSVRK5kweh9EQseq4AjkgPD8CLau+/HlmFs fixture-ed25519-pass"

    private func material(_ key: String, passphrase: String? = nil) -> SSHKeyMaterial {
        SSHKeyMaterial(privateKey: SecureBytes(Data(key.utf8)), passphrase: passphrase.map { SecureBytes(Data($0.utf8)) })
    }

    @Test func ed25519MatchesSSHKeygen() throws {
        let line = try SSHPublicKeys.openSSHLine(for: material(Self.ed25519PrivateKey), comment: "fixture-ed25519")
        #expect(line == Self.ed25519PublicLine)
        #expect(try SSHPublicKeys.algorithm(for: material(Self.ed25519PrivateKey)) == "ssh-ed25519")
        #expect(try SSHPublicKeys.openSSHLine(for: material(Self.ed25519PrivateKey)).split(separator: " ").count == 2, "no comment when none given")
    }

    @Test func rsaMatchesSSHKeygen() throws {
        #expect(try SSHPublicKeys.openSSHLine(for: material(Self.rsaPrivateKey), comment: "fixture-rsa") == Self.rsaPublicLine)
        #expect(try SSHPublicKeys.algorithm(for: material(Self.rsaPrivateKey)) == "ssh-rsa")
    }

    @Test func passphraseProtectedKeyNeedsItsPassphrase() throws {
        #expect(try SSHPublicKeys.openSSHLine(for: material(Self.passphrasePrivateKey, passphrase: "fixture-pass"), comment: "fixture-ed25519-pass") == Self.passphrasePublicLine)
        #expect(throws: SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")) {
            _ = try SSHPublicKeys.openSSHLine(for: material(Self.passphrasePrivateKey, passphrase: "wrong"))
        }
    }

    @Test func legacyWrappedP256DerivesAnECDSAKey() throws {
        let p256 = P256.Signing.PrivateKey()
        let wrapped = "SECURE_ENCLAVE_P256:" + p256.rawRepresentation.base64EncodedString()
        let line = try SSHPublicKeys.openSSHLine(for: material(wrapped))
        #expect(line.hasPrefix("ecdsa-sha2-nistp256 "))
        #expect(throws: SSHTransportError.invalidPrivateKey("Invalid Secure Enclave P-256 payload.")) {
            _ = try SSHPublicKeys.openSSHLine(for: material("SECURE_ENCLAVE_P256:***"))
        }
    }

    @Test func fingerprintMatchesSSHKeygenFormat() throws {
        // ssh-keygen -lf prints SHA256:<unpadded base64 of the key blob>.
        let fingerprint = try SSHPublicKeys.sha256Fingerprint(for: material(Self.ed25519PrivateKey))
        let blob = try #require(Data(base64Encoded: String(Self.ed25519PublicLine.split(separator: " ")[1])))
        let expected = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        #expect(fingerprint == expected)
        #expect(!fingerprint.hasSuffix("="))
    }

    @Test func declaredTypeReadsOnlyTheHeader() throws {
        #expect(try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: Self.ed25519PrivateKey) == .ed25519)
        #expect(try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: Self.rsaPrivateKey) == .rsa)
        #expect(try SSHPublicKeys.declaredKeyType(in: material(Self.passphrasePrivateKey)) == .ed25519,
                "a passphrase-protected key is classified without its passphrase")

        // Header valid, body unparseable: the header probe still answers; full derivation does not.
        let lines = Self.ed25519PrivateKey.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var corrupted = lines
        if corrupted.count > 3 { corrupted[corrupted.count - 3] = String(corrupted[corrupted.count - 3].reversed()) }
        let corruptedKey = corrupted.joined(separator: "\n")
        #expect(try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: corruptedKey) == .ed25519)
        #expect(throws: SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")) {
            _ = try SSHPublicKeys.openSSHLine(for: material(corruptedKey))
        }

        #expect(throws: SSHKeyHeaderError.notAnOpenSSHPrivateKey) { _ = try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: "not a key") }
        #expect(throws: SSHKeyHeaderError.notAnOpenSSHPrivateKey) { _ = try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: Self.ed25519PublicLine) }
        #expect(SSHDeclaredKeyType.ecdsaP384.isSupportedForAuthentication == false)
        // Imported P-256 keys are refused on Save; the Secure Enclave's own P-256 keys never
        // come through this check.
        #expect(SSHDeclaredKeyType.ecdsaP256.isSupportedForAuthentication == false)
        #expect(SSHDeclaredKeyType.ed25519.isSupportedForAuthentication && SSHDeclaredKeyType.rsa.isSupportedForAuthentication)
        #expect(SSHDeclaredKeyType.ed25519.displayName == "ED25519")
    }

    @Test func garbageIsRefusedWithoutEchoingIt() {
        #expect(throws: SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")) {
            _ = try SSHPublicKeys.openSSHLine(for: material("not a key at all"))
        }
    }
}
