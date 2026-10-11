//
//  SSHConnection.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's SSHConnection, re-based on the shared engine. Every call site in TerminalSession,
//  SessionManager and the SFTP browser keeps the method surface it
//  had; underneath, the Citadel clients, jump chain, PTY, keep-alive and host-key validation now
//  live in GlassSSHTransport (SSHTransport / SSHShellChannel / SSHTransportPool). The terminal keeps
//  its own concerns: mapping transport events to connection progress and terminal lines, the
//  host-key trust prompt, auto-reconnect policy, purpose (terminal / SFTP) and recording.
//
//  Moved verbatim from glas.sh Models.swift: SSHError, userFacingMessage(for:server:),
//  normalizedHost(_:), isChannelClosedError(_:).
//

import Foundation
import GlassLayers
import GlasSecretStore
import GlassSSHTransport
import NIOCore
@preconcurrency import NIOSSH
import os

enum SSHError: LocalizedError {
    case sessionNotFound
    case passwordRequired
    case sshKeyNotFound
    case invalidCredentialPreparation
    case invalidCredentialEncoding
    case connectionFailed
    case notConnected
    case authenticationFailed
    case invalidHost(String)
    case invalidPort(Int)
    case unsupportedSSHKeyType(String)
    case unsupportedAuthMethod(String)
    case invalidSSHKey(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Terminal session not found"
        case .passwordRequired:
            return "Password is required for authentication"
        case .sshKeyNotFound:
            return "SSH key file not found"
        case .invalidCredentialPreparation:
            return "SSH credentials were not prepared for this connection"
        case .invalidCredentialEncoding:
            return "The stored SSH credential is invalid or corrupt"
        case .connectionFailed:
            return "Failed to establish SSH connection"
        case .notConnected:
            return "Not connected to SSH server"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidHost(let host):
            return "Invalid host: \(host)"
        case .invalidPort(let port):
            return "Invalid SSH port: \(port)"
        case .unsupportedSSHKeyType(let keyType):
            return "SSH key type '\(keyType)' is not supported yet. Use RSA or ED25519."
        case .unsupportedAuthMethod(let message):
            return message
        case .invalidSSHKey(let message):
            return "Invalid SSH key: \(message)"
        }
    }
}

// MARK: - Layout Presets

/// Runtime-only membership for one spatial visionOS terminal window. Live
/// sessions remain authoritative in SessionManager; this value stores only
/// identity, presentation metadata, ordering, and selection.

/// Hands glas.sh's already-resolved credential material (SessionManager.prepareConnection) to the
/// transport. Nothing is looked up twice and no secret crosses the engine boundary as a String.
struct PreparedCredentialResolver: SSHCredentialResolver {
    let materials: [UUID: SessionAuthenticationMaterial]   // keyed by server id

    func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        let id: UUID?
        switch reference {
        case .password(let profileID): id = profileID
        case .privateKey(let keyID): id = keyID
        case .agent, .custom: id = nil
        }
        guard let id, let material = materials[id] else {
            throw SSHTransportError.credentialUnavailable("No prepared credential for \(endpoint.username)@\(endpoint.displayAddress).")
        }
        switch material {
        case .password(let bytes): return .password(bytes)
        case .sshKey(let key): return .privateKey(key)
        }
    }
}

/// Captures the engine's trust challenge for the terminal's own prompt flow: glas.sh rejects the
/// unknown key, surfaces the challenge, and reconnects after the user pins it.
private final class TerminalHostTrustDecider: SSHHostTrustDecider, @unchecked Sendable {
    private let lock = NSLock()
    private var challenge: SSHHostTrustChallenge?
    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision {
        lock.withLock { self.challenge = challenge }
        return .reject
    }
    func take() -> SSHHostTrustChallenge? {
        lock.withLock { defer { challenge = nil }; return challenge }
    }
}

extension HostKeyTrustChallenge {
    init(_ challenge: SSHHostTrustChallenge) {
        self.init(host: challenge.host, port: challenge.port, algorithm: challenge.algorithm,
                  fingerprintSHA256: challenge.fingerprintSHA256, keyDataBase64: challenge.keyDataBase64,
                  reason: challenge.reason == .changed ? .changed : .unknown)
    }
}

class SSHConnection {
    /// Every terminal's connections, shared per route within what the server allows (W21): a
    /// terminal joins a connection with room — connected or still signing in — and a full one, six
    /// terminals, makes the next open another. See `SSHConnectionLimits`.
    nonisolated static let transportPool = SSHTransportPool<SSHTransport>(limits: .standard)

    private var transport: SSHTransport?
    /// Another terminal's connection this one was told to share (`shareTransport`): its credentials
    /// open a further connection when it is full, so a shared terminal never reads them again.
    private var sharedTransport: SSHTransport?
    private var shell: SSHShellChannel?
    private var eventTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    private var isTransportConnected = false
    /// `disconnect` ran: a connect still on its way gives back what it gets (W21).
    private var isDisconnected = false
    private let ownerID = UUID()
    private let trustDecider = TerminalHostTrustDecider()
    private var terminalRows: Int = TerminalGeometry.default.rows
    private var terminalColumns: Int = TerminalGeometry.default.columns
    weak var session: TerminalSession?

    init(session: TerminalSession) { self.session = session }

    // MARK: - Transport sharing (SessionManager duplicates / SFTP-over-terminal)

    var hasReusableTransport: Bool { (transport != nil && isTransportConnected) || sharedTransport != nil }

    func canShareTransport(for server: ServerConfiguration, jumpHostChain: [ServerConfiguration]) -> Bool {
        guard let transport, isTransportConnected else { return false }
        return transport.identity == Self.makeRoute(for: server, jumpHostChain: jumpHostChain).identity
    }

    /// Shares another connection's route and credentials. `connect` then joins that connection
    /// when it has room, or another to the same route, or opens one with the same credentials
    /// (W21: before, it joined the connection whatever it carried). Ownership is reference-counted
    /// by the engine.
    @discardableResult
    func shareTransport(from connection: SSHConnection) async -> Bool {
        guard transport == nil, sharedTransport == nil,
              let other = connection.transport, connection.isTransportConnected else { return false }
        sharedTransport = other
        return true
    }

    func setPreferredTerminalSize(rows: Int, columns: Int) {
        let geometry = TerminalGeometry(rows: rows, columns: columns)
        terminalRows = geometry.rows
        terminalColumns = geometry.columns
    }

    func takePendingHostKeyChallenge() -> HostKeyTrustChallenge? {
        trustDecider.take().map(HostKeyTrustChallenge.init)
    }

    // MARK: - Route

    static func credentialReference(for server: ServerConfiguration) -> SSHCredentialReference {
        switch server.authMethod {
        case .password: .password(profileID: server.id)
        case .sshKey: .privateKey(keyID: server.id)
        case .agent: .agent
        }
    }

    static func hop(for server: ServerConfiguration) -> SSHHop {
        SSHHop(
            recordID: server.id,
            displayName: server.name,
            endpoint: SSHEndpoint(host: normalizedHost(server.host), port: server.port, username: server.username),
            credential: credentialReference(for: server),
            options: SSHConnectionOptions(
                allowLegacyAlgorithms: server.legacyAlgorithmsEnabled,
                forwardAgent: server.forwardAgent,
                keepAliveInterval: server.keepAliveInterval,
                keepAliveMaxMissed: server.serverAliveCountMax,
                terminalType: server.terminalType,
                environment: server.environmentVariables
            )
        )
    }

    static func hostKeyVerificationMode() -> HostKeyVerificationMode {
        HostKeyVerificationMode(
            rawValue: GlassUITestRun.settingsDefaults.string(forKey: UserDefaultsKeys.hostKeyVerificationMode) ?? ""
        ) ?? .ask
    }

    static func makeRoute(for server: ServerConfiguration, jumpHostChain: [ServerConfiguration]) -> SSHRoute {
        SSHRoute(
            target: hop(for: server),
            jumps: jumpHostChain.map(hop(for:)),
            trustPolicy: hostKeyVerificationMode() == .strict ? .strict : .ask
        )
    }

    /// Prepare-time validation of resolved material (SessionManager.prepareConnection). The engine
    /// builds the actual authentication method at connect time.
    static func validateAuthentication(for server: ServerConfiguration, authentication: PreparedServerAuthentication) throws {
        guard authentication.serverID == server.id else { throw SSHError.invalidCredentialPreparation }
        switch (server.authMethod, authentication.material) {
        case (.password, .password(let password)):
            guard password.toUTF8String() != nil else { throw SSHError.invalidCredentialEncoding }
        case (.sshKey, .sshKey(let key)):
            guard server.sshKeyID != nil, key.privateKey.toUTF8String() != nil else { throw SSHError.invalidCredentialEncoding }
        default:
            throw SSHError.invalidCredentialPreparation
        }
    }

    // MARK: - Connect

    func connect(
        preparation: SessionConnectionPreparation?,
        jumpHostChain: [ServerConfiguration] = []
    ) async throws {
        guard let session else { throw SSHError.sessionNotFound }
        let server = session.server
        if let transport, isTransportConnected {
            if let shell = try await openShellIfTerminal(on: transport) { startShellTask(shell) }
            return
        }

        // W21: the connection comes from the pool — this terminal's own when nothing to its route
        // has room, made from its prepared credentials (or the shared connection's), otherwise one
        // already open or signing in. The shell opens in the same call, so a server that refuses it
        // a session channel (MaxSessions) gets this terminal on another connection.
        let route: SSHRoute
        let candidate: SSHTransport
        if let shared = sharedTransport {
            route = shared.route
            candidate = shared.makeSibling(trustDecider: trustDecider)
        } else {
            guard let preparation else { throw SSHError.invalidCredentialPreparation }
            let normalizedHost = Self.normalizedHost(server.host)
            guard !normalizedHost.isEmpty else { throw SSHError.invalidHost(server.host) }
            guard (1...65_535).contains(server.port) else { throw SSHError.invalidPort(server.port) }
            guard preparation.jumpHosts.count == jumpHostChain.count else { throw SSHError.invalidCredentialPreparation }

            var materials: [UUID: SessionAuthenticationMaterial] = [preparation.target.serverID: preparation.target.material]
            for hop in preparation.jumpHosts { materials[hop.serverID] = hop.material }
            route = Self.makeRoute(for: server, jumpHostChain: jumpHostChain)
            candidate = SSHTransport(
                route: route,
                credentials: PreparedCredentialResolver(materials: materials),
                trustStore: SecretStoreHostTrustStore(configuration: KeychainManager.hostTrustConfig),
                trustDecider: trustDecider
            )
        }

        session.setConnectionProgress(.resolvingDNS)
        // The connection this terminal would make: its sign-in stages show while it is the one.
        startEventPump(candidate)
        if !jumpHostChain.isEmpty, let first = jumpHostChain.first {
            session.appendLine(TerminalLine(text: "Connecting via jump host \(first.name) (\(first.host):\(first.port))...", style: .system))
        }
        let opened: (transport: SSHTransport, value: SSHShellChannel?)
        do {
            opened = try await Self.transportPool.openSession(route, owner: ownerID, candidate: candidate) { @MainActor [weak self] transport in
                guard let self else { throw SSHError.sessionNotFound }
                guard !self.isDisconnected else { throw SSHError.notConnected }
                self.adopt(transport, candidate: candidate)
                self.session?.setConnectionProgress(.authenticating)
                return try await self.openShellIfTerminal(on: transport)
            }
        } catch let error as SSHTransportError {
            await teardownTransport()
            switch error {
            case .hostTrustRequired(let challenge), .hostTrustRejected(let challenge):
                throw HostKeyTrustRequiredError(challenge: HostKeyTrustChallenge(challenge))
            case .authenticationFailed: throw SSHError.authenticationFailed
            case .connectionFailed: throw SSHError.connectionFailed
            case .invalidHost(let host): throw SSHError.invalidHost(host)
            case .invalidPort(let port): throw SSHError.invalidPort(port)
            case .invalidCredentialEncoding: throw SSHError.invalidCredentialEncoding
            case .unsupportedKeyType(let type): throw SSHError.unsupportedSSHKeyType(type)
            case .unsupportedAuthenticationMethod(let message): throw SSHError.unsupportedAuthMethod(message)
            case .invalidPrivateKey(let message): throw SSHError.invalidSSHKey(message)
            default: throw error
            }
        } catch {
            await teardownTransport()
            throw error
        }
        // Closed while it connected: give the connection back rather than hold it for nobody.
        guard !isDisconnected else {
            if let shell = opened.value { await shell.close() }
            await Self.transportPool.release(opened.transport, owner: ownerID)
            throw SSHError.notConnected
        }
        // The pool holds this owner on `opened.transport` from here; `disconnect` releases it.
        transport = opened.transport
        sharedTransport = nil
        isTransportConnected = true
        if let shell = opened.value { startShellTask(shell) }
    }

    /// The connection the pool gave this terminal. Events come from it from now on; a candidate the
    /// pool did not use is dropped with its pump, never connected.
    private func adopt(_ transport: SSHTransport, candidate: SSHTransport) {
        guard transport !== candidate || eventTask == nil else { return }
        startEventPump(transport)
    }

    private func openShellIfTerminal(on transport: SSHTransport) async throws -> SSHShellChannel? {
        guard let session else { throw SSHError.sessionNotFound }
        guard session.purpose == .terminal else { return nil }
        _ = await session.prepareInitialTerminalPresentation()
        session.setConnectionProgress(.startingShell)
        return try await transport.openShell(pty: SSHPTYRequest(columns: terminalColumns, rows: terminalRows))
    }

    private func startShellTask(_ shell: SSHShellChannel) {
        self.shell = shell
        shellTask = Task { [weak self] in
            for await output in shell.output {
                guard !Task.isCancelled else { return }
                switch output {
                case .stdout(let data), .stderr(let data):
                    self?.session?.feedTerminalData(data)
                }
            }
            guard !Task.isCancelled, let self else { return }
            switch await shell.exit {
            case .remoteClosed, .none:
                self.session?.handleCleanRemoteExit()
            case .cancelled:
                break
            case .failed(let message):
                if case .connected = self.session?.state { self.session?.reportError(message) }
                let autoReconnect = GlassUITestRun.settingsDefaults.bool(forKey: UserDefaultsKeys.autoReconnect)
                self.session?.attemptAutoReconnect(autoReconnectEnabled: autoReconnect)
            }
        }
    }

    private func startEventPump(_ transport: SSHTransport) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in transport.events {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .stage(let stage):
                    switch stage {
                    case .resolvingHost: self.session?.setConnectionProgress(.resolvingDNS)
                    case .openingSocket(let port): self.session?.setConnectionProgress(.openingSocket(port: port))
                    case .negotiatingSecurity: self.session?.setConnectionProgress(.negotiatingSecurity)
                    case .negotiatingCompatibility: self.session?.setConnectionProgress(.negotiatingCompatibility)
                    case .authenticating: self.session?.setConnectionProgress(.authenticating)
                    case .connectingJump(let index, let count, let name):
                        self.session?.appendLine(TerminalLine(text: "Jumping to hop \(index + 1)/\(count): \(name)", style: .system))
                    case .jumpConnected(let index, let count, let name):
                        self.session?.appendLine(TerminalLine(text: "Hop \(index + 1)/\(count) connected: \(name)", style: .system))
                    case .tunnelingToTarget(let host, let port):
                        self.session?.appendLine(TerminalLine(text: "Tunneling to target \(host):\(port)...", style: .system))
                    }
                case .connected:
                    self.isTransportConnected = true
                case .keepAliveMissed(let count, let maximum):
                    Logger.ssh.warning("Keep-alive missed \(count)/\(maximum)")
                case .lost(let message):
                    self.isTransportConnected = false
                    if case .connected = self.session?.state { self.session?.reportError(message) }
                    let autoReconnect = GlassUITestRun.settingsDefaults.bool(forKey: UserDefaultsKeys.autoReconnect)
                    self.session?.attemptAutoReconnect(autoReconnectEnabled: autoReconnect)
                case .closed:
                    self.isTransportConnected = false
                }
            }
        }
    }

    // MARK: - I/O

    func sendCommand(_ command: String) async throws {
        guard shell != nil else { throw SSHError.notConnected }
        try await sendInput(command + "\n")
    }

    func sendInput(_ input: String) async throws {
        guard let shell else { throw SSHError.notConnected }
        try await shell.write(input)
    }

    func sendBytes(_ data: Data) async throws {
        guard let shell else { throw SSHError.notConnected }
        try await shell.write(data)
    }

    func resizeTerminal(rows: Int, columns: Int) async throws {
        setPreferredTerminalSize(rows: rows, columns: columns)
        guard let shell else { throw SSHError.notConnected }
        try await shell.resize(columns: terminalColumns, rows: terminalRows)
    }

    /// The browser's entry point, unchanged: a Citadel-shaped client over the engine's session.
    func openSFTPClient() async throws -> SFTPClient {
        let session = try await openSFTPSession()
        return SFTPClient(session: session, extensions: await session.serverExtensions)
    }

    func openSFTPSession() async throws -> any SFTPSession {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        return try await transport.openSFTP()
    }

    func executeRemoteCommand(
        _ command: String,
        maxResponseBytes: Int = .max,
        executionTimeout: TimeAmount = .seconds(3_600)
    ) async throws -> String {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        return try await transport.execute(
            command,
            maxResponseBytes: maxResponseBytes,
            timeout: .nanoseconds(executionTimeout.nanoseconds)
        )
    }

    func createDirectTCPIPChannel(targetHost: String, targetPort: Int) async throws -> Channel {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        return try await transport.openDirectChannel(toHost: targetHost, port: targetPort)
    }

    func forward(localPort: Int, toHost host: String, port: Int) async throws -> SSHTunnel {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        return try await transport.forward(localPort: localPort, toHost: host, port: port)
    }

    func socks5(localPort: Int, credentials: SOCKS5Credentials) async throws -> SSHTunnel {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        return try await transport.socks5(localPort: localPort, credentials: credentials)
    }

    /// Runs until the forward closes, as before; `onOpen` receives the port the server bound.
    func runRemotePortForward(
        remoteHost: String,
        remotePort: Int,
        localHost: String,
        localPort: Int,
        onOpen: @escaping @MainActor @Sendable (_ boundPort: Int) -> Void
    ) async throws {
        guard let transport, isTransportConnected else { throw SSHError.notConnected }
        let forward = try await transport.remoteForward(remoteHost: remoteHost, remotePort: remotePort,
                                                        toLocalHost: localHost, localPort: localPort)
        if let bound = await forward.boundPort() {
            await onOpen(bound)
            Logger.ssh.info("Remote port forward established: \(remoteHost):\(bound) -> \(localHost):\(localPort)")
        }
        try await forward.waitUntilClosed()
    }

    func disconnect() async {
        isDisconnected = true
        eventTask?.cancel(); eventTask = nil
        shellTask?.cancel(); shellTask = nil
        if let shell { await shell.close() }
        shell = nil
        await teardownTransport()
    }

    private func teardownTransport() async {
        isTransportConnected = false
        sharedTransport = nil
        guard let transport else { return }
        self.transport = nil
        await Self.transportPool.release(transport, owner: ownerID)
    }

    static func isKeyExchangeNegotiationFailure(_ error: Error) -> Bool {
        if let nioError = error as? NIOSSHError, nioError.type == .keyExchangeNegotiationFailure {
            return true
        }

        let raw = String(describing: error)
        return raw.localizedCaseInsensitiveContains("keyexchangenegotiationfailure")
            || raw.localizedCaseInsensitiveContains("key exchange negotiation failure")
    }

    // MARK: - Messages (verbatim from glas.sh)

    static func userFacingMessage(for error: Error, server: ServerConfiguration) -> String {
        if let trustError = error as? HostKeyTrustRequiredError {
            switch trustError.challenge.reason {
            case .unknown:
                return "First-time host key check for \(server.host):\(server.port). Review and trust the fingerprint to continue."
            case .changed:
                return "Warning: the host key changed for \(server.host):\(server.port). This may indicate a security risk."
            }
        }

        if let sshError = error as? SSHError {
            switch sshError {
            case .passwordRequired:
                return "A password is required for \(server.username)@\(server.host):\(server.port)."
            case .sshKeyNotFound:
                return "SSH key was not found. Check the key path in server settings."
            case .invalidCredentialPreparation:
                return "SSH credentials were not prepared for this connection. Start the connection again."
            case .invalidCredentialEncoding:
                return "The stored SSH credential is invalid or corrupt. Save or import it again."
            case .authenticationFailed:
                return "Authentication failed for \(server.username)@\(server.host):\(server.port)."
            case .invalidHost(let rawHost):
                return "The host \"\(rawHost)\" is not valid. Use a plain host name or IP (no protocol)."
            case .invalidPort(let port):
                return "The SSH port \(port) is not valid. Use a port from 1 through 65535."
            case .connectionFailed:
                return "Could not establish an SSH connection to \(server.host):\(server.port)."
            case .notConnected:
                return "Not connected to \(server.host):\(server.port)."
            case .sessionNotFound:
                return "The terminal session is no longer available."
            case .unsupportedSSHKeyType(let keyType):
                return "\(keyType). Supported key types are RSA, ED25519, and ECDSA P-256."
            case .unsupportedAuthMethod(let message):
                return message
            case .invalidSSHKey:
                return "The selected SSH key could not be parsed. Verify key contents and passphrase."
            }
        }

        // W21: the server's own limits, named so the person knows which setting it is.
        if let transportError = error as? SSHTransportError,
           transportError == .sessionLimitReached || transportError == .serverBusy {
            return SSHTransportError.userFacingMessage(
                for: transportError,
                endpoint: SSHEndpoint(host: server.host, port: server.port, username: server.username),
                usesPrivateKey: server.authMethod == .sshKey
            )
        }

        if let channelError = error as? ChannelError {
            switch channelError {
            case .connectPending:
                return "A connection to \(server.host):\(server.port) is already in progress."
            case .connectTimeout:
                return "Connection to \(server.host):\(server.port) timed out."
            case .ioOnClosedChannel, .alreadyClosed, .inputClosed, .outputClosed, .eof:
                return "The SSH channel to \(server.host):\(server.port) was closed."
            default:
                return "SSH channel error while connecting to \(server.host):\(server.port)."
            }
        }

        if isKeyExchangeNegotiationFailure(error) {
            return "SSH handshake failed: no shared security algorithm was found with \(server.host):\(server.port)."
        }

        let raw = String(describing: error)
        if raw.localizedCaseInsensitiveContains("allauthenticationoptionsfailed")
            || raw.localizedCaseInsensitiveContains("all authentication options failed")
        {
            if server.authMethod == .sshKey {
                return "SSH authentication was rejected by \(server.host):\(server.port). Verify username, ensure the matching public key is installed in authorized_keys, and confirm the server allows this key algorithm."
            }
            return "Authentication failed for \(server.username)@\(server.host):\(server.port). Verify credentials and server auth policy."
        }
        if raw.localizedCaseInsensitiveContains("authentication") {
            return "Authentication failed for \(server.username)@\(server.host):\(server.port)."
        }
        if raw.localizedCaseInsensitiveContains("timed out") {
            return "Connection to \(server.host):\(server.port) timed out."
        }
        if raw.localizedCaseInsensitiveContains("refused") {
            return "Connection refused by \(server.host):\(server.port). Verify SSH is running on that port."
        }
        if raw.localizedCaseInsensitiveContains("no route")
            || raw.localizedCaseInsensitiveContains("unreachable")
            || raw.localizedCaseInsensitiveContains("dns")
        {
            return "Could not reach \(server.host):\(server.port). Check network access and host name."
        }

        return "Could not connect to \(server.host):\(server.port)."
    }

    static func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ssh://", with: "", options: [.caseInsensitive])
    }

    static func isChannelClosedError(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            return channelError == .eof || channelError == .alreadyClosed
                || channelError == .inputClosed || channelError == .outputClosed
        }
        return false
    }
}

