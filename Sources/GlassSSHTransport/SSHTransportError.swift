import Foundation
@preconcurrency import Citadel
import NIOCore
@preconcurrency import NIOSSH

/// glas.sh `SSHError` (Models.swift:2781) plus the trust and tunnel cases the engine adds.
public enum SSHTransportError: Error, Sendable, Equatable {
    case invalidHost(String)
    case invalidPort(Int)
    case connectionFailed
    case notConnected
    case authenticationFailed
    case credentialUnavailable(String)
    case invalidCredentialEncoding
    case unsupportedKeyType(String)
    case unsupportedAuthenticationMethod(String)
    case invalidPrivateKey(String)
    case hostTrustRequired(SSHHostTrustChallenge)
    case hostTrustRejected(SSHHostTrustChallenge)
    /// A host-key blob that could not be decoded (S10).
    case invalidHostKey
    case channelClosed
    case cancelled
    case tunnelBindFailed(port: Int, reason: String)
    case sftpUnavailable
    /// The server refused a session channel — a shell, a command or SFTP — on a connection already
    /// carrying as many as it allows (OpenSSH's `MaxSessions`, W21).
    case sessionLimitReached
    /// The server kept closing new connections before they were set up, as OpenSSH does past
    /// `MaxStartups` while others are still signing in (W21). Given after the retries.
    case serverBusy
}

extension SSHTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host): return "Invalid host: \(host)"
        case .invalidPort(let port): return "Invalid SSH port: \(port)"
        case .connectionFailed: return "Failed to establish SSH connection"
        case .notConnected: return "Not connected to SSH server"
        case .authenticationFailed: return "Authentication failed"
        case .credentialUnavailable(let message): return message
        case .invalidCredentialEncoding: return "The stored SSH credential is invalid or corrupt"
        case .unsupportedKeyType(let keyType): return "SSH key type '\(keyType)' is not supported yet. Use RSA or ED25519."
        case .unsupportedAuthenticationMethod(let message): return message
        case .invalidPrivateKey(let message): return "Invalid SSH key: \(message)"
        case .hostTrustRequired(let challenge): return challenge.summary
        case .hostTrustRejected(let challenge): return "The host key for \(challenge.host):\(challenge.port) was not trusted."
        case .invalidHostKey: return "The server's host key could not be decoded"
        case .channelClosed: return "The SSH channel was closed"
        case .cancelled: return "The SSH operation was cancelled"
        case .tunnelBindFailed(let port, let reason): return "Failed to bind port \(port): \(reason)"
        case .sftpUnavailable: return "SFTP is not available on this connection"
        case .sessionLimitReached: return "The server refused another session on this connection"
        case .serverBusy: return "The server turned the connection away while others were signing in"
        }
    }
}

public extension SSHTransportError {
    /// The user-facing text glas.sh showed for a failed connection, moved from
    /// `SSHConnection.userFacingMessage(for:server:)` (Models.swift:2615-2700).
    static func userFacingMessage(for error: Error, endpoint: SSHEndpoint, usesPrivateKey: Bool) -> String {
        let address = endpoint.displayAddress
        if let trustError = error as? SSHHostTrustRequiredError {
            return userFacingMessage(for: SSHTransportError.hostTrustRequired(trustError.challenge), endpoint: endpoint, usesPrivateKey: usesPrivateKey)
        }
        if let transportError = error as? SSHTransportError {
            switch transportError {
            case .invalidHost(let rawHost): return "The host \"\(rawHost)\" is not valid. Use a plain host name or IP (no protocol)."
            case .invalidPort(let port): return "The SSH port \(port) is not valid. Use a port from 1 through 65535."
            case .connectionFailed: return "Could not establish an SSH connection to \(address)."
            case .notConnected: return "Not connected to \(address)."
            case .authenticationFailed: return "Authentication failed for \(endpoint.username)@\(address)."
            case .credentialUnavailable(let message): return message
            case .invalidCredentialEncoding: return "The stored SSH credential is invalid or corrupt. Save or import it again."
            case .unsupportedKeyType(let keyType): return "\(keyType). Supported key types are RSA, ED25519, and ECDSA P-256."
            case .unsupportedAuthenticationMethod(let message): return message
            case .invalidPrivateKey: return "The selected SSH key could not be parsed. Verify key contents and passphrase."
            case .hostTrustRequired(let challenge):
                switch challenge.reason {
                case .unknown: return "First-time host key check for \(address). Review and trust the fingerprint to continue."
                case .changed: return "Warning: the host key changed for \(address). This may indicate a security risk."
                }
            case .hostTrustRejected: return "The host key for \(address) was not trusted, so the connection was not made."
            case .invalidHostKey: return "The host key presented by \(address) could not be decoded."
            case .channelClosed: return "The SSH channel to \(address) was closed."
            case .cancelled: return "The connection to \(address) was cancelled."
            case .tunnelBindFailed(let port, let reason): return "Could not open local port \(port): \(reason)"
            case .sftpUnavailable: return "SFTP is not available on \(address)."
            case .sessionLimitReached:
                return "The server at \(address) limits how many sessions one connection can carry (MaxSessions), "
                    + "and it refused this one on a new connection too. Close a terminal to it, "
                    + "or raise MaxSessions in its sshd_config."
            case .serverBusy:
                return "\(address) kept closing the connection before it could sign in, as SSH servers do when "
                    + "too many connections are opening at once (MaxStartups). Wait a moment and reconnect; "
                    + "if it keeps happening, raise MaxStartups in its sshd_config."
            }
        }
        if let channelError = error as? ChannelError {
            switch channelError {
            case .connectPending: return "A connection to \(address) is already in progress."
            case .connectTimeout: return "Connection to \(address) timed out."
            case .ioOnClosedChannel, .alreadyClosed, .inputClosed, .outputClosed, .eof: return "The SSH channel to \(address) was closed."
            default: return "SSH channel error while connecting to \(address)."
            }
        }
        if isKeyExchangeNegotiationFailure(error) {
            return "SSH handshake failed: no shared security algorithm was found with \(address)."
        }
        let raw = String(describing: error)
        if raw.localizedCaseInsensitiveContains("allauthenticationoptionsfailed")
            || raw.localizedCaseInsensitiveContains("all authentication options failed") {
            if usesPrivateKey {
                return "SSH authentication was rejected by \(address). Verify username, ensure the matching public key is installed in authorized_keys, and confirm the server allows this key algorithm."
            }
            return "Authentication failed for \(endpoint.username)@\(address). Verify credentials and server auth policy."
        }
        if raw.localizedCaseInsensitiveContains("authentication") { return "Authentication failed for \(endpoint.username)@\(address)." }
        if raw.localizedCaseInsensitiveContains("timed out") { return "Connection to \(address) timed out." }
        if raw.localizedCaseInsensitiveContains("refused") { return "Connection refused by \(address). Verify SSH is running on that port." }
        if raw.localizedCaseInsensitiveContains("no route") || raw.localizedCaseInsensitiveContains("unreachable") || raw.localizedCaseInsensitiveContains("dns") {
            return "Could not reach \(address). Check network access and host name."
        }
        return "Could not connect to \(address)."
    }

    static func isKeyExchangeNegotiationFailure(_ error: Error) -> Bool {
        if let nioError = error as? NIOSSHError, nioError.type == .keyExchangeNegotiationFailure { return true }
        let raw = String(describing: error)
        return raw.localizedCaseInsensitiveContains("keyexchangenegotiationfailure")
            || raw.localizedCaseInsensitiveContains("key exchange negotiation failure")
    }

    static func shouldRetryWithLegacyAlgorithms(_ error: Error, enabled: Bool) -> Bool {
        enabled && isKeyExchangeNegotiationFailure(error)
    }

    /// The server would not open a session channel here (W21): OpenSSH answers past `MaxSessions`
    /// with SSH_MSG_CHANNEL_OPEN_FAILURE, which NIOSSH raises as `channelSetupRejected`.
    static func isSessionChannelRefused(_ error: Error) -> Bool {
        if let transportError = error as? SSHTransportError { return transportError == .sessionLimitReached }
        if let nioError = error as? NIOSSHError, nioError.type == .channelSetupRejected { return true }
        return String(describing: error).localizedCaseInsensitiveContains("channelsetuprejected")
    }

    /// The server never answered a session channel open — Citadel gives up after 15 seconds. The
    /// connection is likely dead though its socket looks open (W21): a terminal joining or
    /// reconnecting onto it would wait the same 15 seconds every time.
    static func isSessionOpenUnanswered(_ error: Error) -> Bool {
        (error as? CitadelError) == .channelCreationFailed
    }

    /// The server closed or reset a connection before it was set up (W21). Past `MaxStartups`
    /// OpenSSH writes "Exceeded MaxStartups" and closes; NIOSSH reads that line as text before a
    /// banner, so the client sees only the connection end. Closed cleanly, Citadel's handshake
    /// handler goes away with `Disconnected`; closed with the client's banner unread, it is a
    /// reset (`ECONNRESET`) — both seen against a loopback server doing exactly that
    /// (`SSHConnectionLimitsTests`). Worth another try after a pause. A refused port, a timeout,
    /// a host key or a rejected sign-in is not.
    static func isDroppedDuringSetup(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            switch channelError {
            case .eof, .ioOnClosedChannel, .alreadyClosed, .inputClosed, .outputClosed: return true
            default: return false
            }
        }
        if let ioError = error as? IOError {
            return [ECONNRESET, EPIPE, ECONNABORTED].contains(ioError.errnoCode)
        }
        if String(describing: type(of: error)) == "Disconnected" { return true }
        let raw = String(describing: error)
        return raw.localizedCaseInsensitiveContains("exceeded maxstartups")
            || raw.localizedCaseInsensitiveContains("connection reset by peer")
    }

    static func isChannelClosedError(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            return channelError == .eof || channelError == .alreadyClosed
                || channelError == .inputClosed || channelError == .outputClosed
        }
        return false
    }

    /// The bind-failure text glas.sh showed for port forwards (PortForwardManager.swift:1165).
    static func bindFailureReason(_ error: Error, port: Int) -> String {
        let description = "\(error)"
        if description.contains("address_already_in_use") || description.contains("EADDRINUSE") || description.contains("Address already in use") {
            return "Port \(port) is already in use."
        }
        if description.contains("permission_denied") || description.contains("EACCES") {
            return "Permission denied binding port \(port). Ports below 1024 require elevated privileges."
        }
        return error.localizedDescription
    }
}
