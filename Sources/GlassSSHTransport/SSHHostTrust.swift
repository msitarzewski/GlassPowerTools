import Foundation
import Citadel
import NIOCore
import NIOSSH
import GlasSecretStore
import os
import Crypto

/// glas.sh's `HostKeyVerificationMode` (Models.swift:26). Both modes stop on an unknown or
/// changed key; `ask` lets a decider answer, `strict` never trusts interactively.
public enum SSHHostTrustPolicy: String, Sendable, Codable, CaseIterable {
    case ask
    case strict
}

public enum SSHHostTrustReason: String, Sendable, Codable {
    case unknown
    case changed
}

/// The one host-trust challenge type for the whole application. Moved from glas.sh
/// `HostKeyTrustChallenge` (Models.swift:248); glassdb's duplicate `SSHHostKeyChallenge` is
/// not ported.
public struct SSHHostTrustChallenge: Sendable, Hashable, Codable {
    public let host: String
    public let port: Int
    public let algorithm: String
    public let fingerprintSHA256: String
    public let keyDataBase64: String
    public let reason: SSHHostTrustReason

    public init(host: String, port: Int, algorithm: String, fingerprintSHA256: String, keyDataBase64: String, reason: SSHHostTrustReason) {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.fingerprintSHA256 = fingerprintSHA256
        self.keyDataBase64 = keyDataBase64
        self.reason = reason
    }

    public var keyData: Data? { Data(base64Encoded: keyDataBase64) }

    public var summary: String {
        switch reason {
        case .unknown: return "This is the first time connecting to \(host):\(port)."
        case .changed: return "The server key for \(host):\(port) has changed."
        }
    }
}

public struct SSHHostTrustRequiredError: Error, Sendable, Equatable {
    public let challenge: SSHHostTrustChallenge
    public init(challenge: SSHHostTrustChallenge) { self.challenge = challenge }
}

public enum SSHHostTrustDecision: Sendable, Equatable {
    /// Accept the key. With `remember`, the key is pinned in the trust store; otherwise it is
    /// trusted for this transport's lifetime only.
    case trust(remember: Bool)
    case reject
}

/// Answers a challenge, typically by prompting. Absent a decider the transport throws
/// `SSHHostTrustRequiredError`, the behaviour glas.sh's session layer expects.
public protocol SSHHostTrustDecider: Sendable {
    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision
}

/// Where pinned keys live. The default is GlasSecretStore's `SSHHostTrustKeychainStore`.
public protocol SSHHostTrustStore: Sendable {
    /// Base64-encoded wire-format public keys currently authorised for `host:port`.
    func authorizedKeys(host: String, port: Int) throws -> Set<String>
    /// Pins the challenged key; a `changed` reason supersedes the previous generation.
    func pin(_ challenge: SSHHostTrustChallenge) throws
}

public struct SecretStoreHostTrustStore: SSHHostTrustStore {
    public let configuration: SecretStoreConfiguration
    public init(configuration: SecretStoreConfiguration) { self.configuration = configuration }

    public func authorizedKeys(host: String, port: Int) throws -> Set<String> {
        let records = try SSHHostTrustKeychainStore.authorizedRecords(host: host, port: port, config: configuration)
        return Set(records.map { $0.publicKeyData.base64EncodedString() })
    }

    public func pin(_ challenge: SSHHostTrustChallenge) throws {
        guard let keyData = challenge.keyData else { throw SSHTransportError.invalidHostKey }
        let pinned = PinnedSSHHostKey(host: challenge.host, port: challenge.port, algorithm: challenge.algorithm, publicKeyData: keyData)
        switch challenge.reason {
        case .unknown:
            try SSHHostTrustKeychainStore.save(pinned, config: configuration)
        case .changed:
            _ = try SSHHostTrustKeychainStore.replace(with: pinned, config: configuration)
        }
    }
}

/// An in-memory store for tests and for callers that keep trust elsewhere.
public final class InMemoryHostTrustStore: SSHHostTrustStore, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String: Set<String>]>(initialState: [:])
    public init(pinned: [String: Set<String>] = [:]) { lock.withLock { $0 = pinned } }
    public static func key(host: String, port: Int) -> String { "\(host):\(port)" }
    public func authorizedKeys(host: String, port: Int) throws -> Set<String> {
        lock.withLock { $0[Self.key(host: host, port: port)] ?? [] }
    }
    public func pin(_ challenge: SSHHostTrustChallenge) throws {
        lock.withLock {
            switch challenge.reason {
            case .unknown: $0[Self.key(host: challenge.host, port: challenge.port), default: []].insert(challenge.keyDataBase64)
            case .changed: $0[Self.key(host: challenge.host, port: challenge.port)] = [challenge.keyDataBase64]
            }
        }
    }
}

/// Pure trust arithmetic, separated from NIO so it is unit-testable: given what is authorised
/// and what the server presented, either accept or produce the challenge.
public enum SSHHostTrustEvaluator {
    public static func evaluate(
        presentedKeyBase64: String,
        algorithm: String,
        fingerprintSHA256: String,
        host: String,
        port: Int,
        authorizedKeys: Set<String>
    ) -> SSHHostTrustChallenge? {
        if authorizedKeys.contains(presentedKeyBase64) { return nil }
        return SSHHostTrustChallenge(
            host: host,
            port: port,
            algorithm: algorithm,
            fingerprintSHA256: fingerprintSHA256,
            keyDataBase64: presentedKeyBase64,
            reason: authorizedKeys.isEmpty ? .unknown : .changed
        )
    }

    public static func algorithm(fromWireData data: Data) -> String {
        guard data.count >= 4 else { return "unknown" }
        let length = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, data.count >= 4 + length else { return "unknown" }
        return String(data: data[4..<(4 + length)], encoding: .utf8) ?? "unknown"
    }

    public static func sha256Base64(of data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}

/// Per-connection challenge handoff for SSH libraries that wrap delegate errors. Avoiding
/// global endpoint state prevents concurrent sessions from accepting one another's
/// fingerprints. Moved from glas.sh `HostKeyChallengeBox` (Models.swift:270).
final class SSHHostKeyChallengeBox: Sendable {
    private let value = OSAllocatedUnfairLock<SSHHostTrustChallenge?>(initialState: nil)
    func store(_ challenge: SSHHostTrustChallenge) { value.withLock { $0 = challenge } }
    func take() -> SSHHostTrustChallenge? { value.withLock { defer { $0 = nil }; return $0 } }
    func clear() { value.withLock { $0 = nil } }
}

/// Moved from glas.sh `PromptingHostKeyValidator` (Models.swift:290-368).
final class SSHPromptingHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    private let host: String
    private let port: Int
    private let trustedKeyBase64Set: Set<String>
    private let challengeBox: SSHHostKeyChallengeBox

    init(host: String, port: Int, trustedKeyBase64Set: Set<String>, challengeBox: SSHHostKeyChallengeBox) {
        self.host = host
        self.port = port
        self.trustedKeyBase64Set = trustedKeyBase64Set
        self.challengeBox = challengeBox
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        _ = hostKey.write(to: &buffer)
        let keyData = Data(buffer.readableBytesView)
        let presented = keyData.base64EncodedString()
        if let challenge = SSHHostTrustEvaluator.evaluate(
            presentedKeyBase64: presented,
            algorithm: SSHHostTrustEvaluator.algorithm(fromWireData: keyData),
            fingerprintSHA256: SSHHostTrustEvaluator.sha256Base64(of: keyData),
            host: host,
            port: port,
            authorizedKeys: trustedKeyBase64Set
        ) {
            challengeBox.store(challenge)
            validationCompletePromise.fail(SSHHostTrustRequiredError(challenge: challenge))
        } else {
            challengeBox.clear()
            validationCompletePromise.succeed(())
        }
    }
}
