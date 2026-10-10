//
//  Models.swift
//  glas.sh
//
//  Core data models for SSH connections, sessions, and configuration
//

import SwiftUI
import Foundation
import CoreGraphics
import Security
import Observation
import NIOCore
import Logging
import GlassTerminalEmulator
import os
import GlasSecretStore
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Host Key Verification

enum HostKeyVerificationMode: String, Codable, CaseIterable {
    case ask = "Ask"
    case strict = "Strict"
}

struct TrustedHostKeyEntry: Codable, Identifiable, Hashable {
    var id: String { "\(host):\(port):\(algorithm):\(fingerprintSHA256)" }
    let host: String
    let port: Int
    let algorithm: String
    let fingerprintSHA256: String
    let keyDataBase64: String
    let addedAt: Date
}

// MARK: - Authentication

enum AuthenticationMethod: String, Codable, CaseIterable {
    case password
    case sshKey
    case agent
    
    var displayName: String {
        switch self {
        case .password: return "Password"
        case .sshKey: return "SSH Key"
        case .agent: return "SSH Agent"
        }
    }
    
    var icon: String {
        switch self {
        case .password: return "key.fill"
        case .sshKey: return "key.radiowaves.forward.fill"
        case .agent: return "person.badge.key.fill"
        }
    }
}

// MARK: - Server Configuration

struct ServerConnectionProvenance: Codable, Hashable, Sendable {
    enum Provider: String, Codable, Hashable, Sendable {
        case tailscale
    }

    static let maximumExternalIDLength = 256

    let provider: Provider
    let externalID: String

    init?(provider: Provider, externalID: String) {
        let normalizedID = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
              normalizedID.count <= Self.maximumExternalIDLength,
              !normalizedID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        self.provider = provider
        self.externalID = normalizedID
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case externalID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(Provider.self, forKey: .provider)
        let externalID = try container.decode(String.self, forKey: .externalID)
        guard let validated = Self(provider: provider, externalID: externalID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .externalID,
                in: container,
                debugDescription: "Connection provenance external identifier is invalid."
            )
        }
        self = validated
    }
}

nonisolated struct TerminalGeometry: Equatable, Hashable, Sendable {
    static let columnRange = 20...500
    static let rowRange = 8...300
    static let `default` = TerminalGeometry(rows: 40, columns: 120)

    let rows: Int
    let columns: Int

    init(rows: Int, columns: Int) {
        self.rows = min(Self.rowRange.upperBound, max(Self.rowRange.lowerBound, rows))
        self.columns = min(Self.columnRange.upperBound, max(Self.columnRange.lowerBound, columns))
    }

    static func contains(rows: Int, columns: Int) -> Bool {
        rowRange.contains(rows) && columnRange.contains(columns)
    }

    /// What the view actually holds, for the PTY. The ranges above are for a size someone sets;
    /// a measured size is the truth, however small. Held to 8 rows, an iPhone on its side with
    /// the keyboard up showed about 4 while the host drew 8, and the prompt was off screen
    /// (2026-10-04).
    static let measuredRowRange = 2...300
    static let measuredColumnRange = 10...500

    init(measuredRows rows: Int, columns: Int) {
        self.rows = min(Self.measuredRowRange.upperBound, max(Self.measuredRowRange.lowerBound, rows))
        self.columns = min(Self.measuredColumnRange.upperBound, max(Self.measuredColumnRange.lowerBound, columns))
    }
}

struct ServerConfiguration: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthenticationMethod
    var sshKeyPath: String?
    var sshKeyID: UUID?
    var trustedHostKeys: [TrustedHostKeyEntry]?
    var isFavorite: Bool
    var colorTag: ServerColorTag
    let dateAdded: Date
    var lastConnected: Date?
    var tags: [String]
    var provenance: ServerConnectionProvenance?
    var jumpHostID: UUID?
    var jumpHostIDs: [UUID]?

    /// Returns the ordered list of jump host UUIDs, preferring the multi-hop
    /// array when present and falling back to the legacy single-hop property.
    var resolvedJumpHostIDs: [UUID] {
        if let ids = jumpHostIDs, !ids.isEmpty { return ids }
        if let id = jumpHostID { return [id] }
        return []
    }

    // Advanced options
    var compression: Bool
    var keepAliveInterval: Int // seconds
    var serverAliveCountMax: Int
    var forwardAgent: Bool
    /// Explicit, per-host opt-in for compatibility algorithms. Existing
    /// records with no value remain on the modern default policy.
    var allowLegacyAlgorithms: Bool?
    var requestPTY: Bool
    var terminalType: String
    var environmentVariables: [String: String]
    /// Optional saved-profile opening grid. Both values must be present or both
    /// must be absent; macOS fits the initial window before creating the PTY.
    var initialTerminalColumns: Int?
    var initialTerminalRows: Int?
    /// D44: keep each terminal in its own tmux session on the host. Absent on every record saved
    /// before 2026-10-01, which reads as off.
    var tmux: Bool?
    /// Whether the host had tmux when a terminal last connected; nil until one has. The setting
    /// above can only be turned on when it did.
    var tmuxAvailable: Bool?
    /// The owner has answered "keep terminals running with tmux?" for this server, on any device.
    var tmuxOffered: Bool?
    
    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthenticationMethod = .password,
        sshKeyPath: String? = nil,
        sshKeyID: UUID? = nil,
        isFavorite: Bool = false,
        colorTag: ServerColorTag = .blue,
        tags: [String] = [],
        provenance: ServerConnectionProvenance? = nil,
        jumpHostID: UUID? = nil,
        jumpHostIDs: [UUID]? = nil,
        initialTerminalColumns: Int? = nil,
        initialTerminalRows: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.sshKeyPath = sshKeyPath
        self.sshKeyID = sshKeyID
        self.trustedHostKeys = nil
        self.isFavorite = isFavorite
        self.colorTag = colorTag
        self.dateAdded = Date()
        self.lastConnected = nil
        self.tags = tags
        self.provenance = provenance
        self.jumpHostID = jumpHostID
        self.jumpHostIDs = jumpHostIDs

        // Defaults
        self.compression = false
        self.keepAliveInterval = 60
        self.serverAliveCountMax = 3
        self.forwardAgent = false
        self.allowLegacyAlgorithms = false
        self.requestPTY = true
        self.terminalType = "xterm-256color"
        self.environmentVariables = [:]
        self.initialTerminalColumns = initialTerminalColumns
        self.initialTerminalRows = initialTerminalRows
    }

    var legacyAlgorithmsEnabled: Bool {
        allowLegacyAlgorithms == true
    }

    var keepsSessionsInTmux: Bool { tmux == true }
}

enum ServerColorTag: String, Codable, CaseIterable, Hashable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, cyan, gray
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .cyan: return .cyan
        case .gray: return .gray
        }
    }
}

// MARK: - Terminal Session

enum HostKeyChallengeReason: String, Codable {
    case unknown
    case changed
}

struct HostKeyTrustChallenge: Codable, Equatable, Sendable {
    let host: String
    let port: Int
    let algorithm: String
    let fingerprintSHA256: String
    let keyDataBase64: String
    let reason: HostKeyChallengeReason

    var summary: String {
        switch reason {
        case .unknown:
            return "This is the first time connecting to \(host):\(port)."
        case .changed:
            return "The server key for \(host):\(port) has changed."
        }
    }
}

struct HostKeyTrustRequiredError: Error {
    let challenge: HostKeyTrustChallenge
}

/// Per-connection challenge handoff for SSH libraries that wrap delegate errors.
/// Avoiding global endpoint state prevents concurrent sessions from accepting
/// one another's fingerprints.
enum SessionAuthenticationMaterial {
    case password(SecureBytes)
    case sshKey(SSHKeyMaterial)
}

struct PreparedServerAuthentication {
    let serverID: UUID
    let material: SessionAuthenticationMaterial
}

struct SessionConnectionPreparation {
    let target: PreparedServerAuthentication
    let jumpHosts: [PreparedServerAuthentication]
}

enum TerminalSessionLifecycleTransition: CaseIterable, Sendable {
    case manualReconnect
    case automaticReconnect
    case explicitDisconnect
    case cleanRemoteExit
    case terminalError
}

/// A single explicit launch-time command. Tickets are intentionally runtime
/// only: command text never enters live workspace restoration, credentials, or
/// connection-preparation data, and a claimed ticket is never retried after an
/// uncertain transport write.
struct TerminalStartupCommandTicket: Identifiable, Equatable, Sendable {
    static let maximumCommandBytes = SwiftTermPastePolicy.directPasteMaximumBytes

    let id: UUID
    let command: String

    init?(id: UUID = UUID(), command: String?) {
        guard let command else { return nil }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.utf8.contains(0),
              !normalized.contains("\n"),
              !normalized.contains("\r"),
              normalized.utf8.count <= Self.maximumCommandBytes else { return nil }
        self.id = id
        self.command = normalized
    }
}

@MainActor
@Observable
class TerminalSession: Identifiable, Hashable {
    /// `probe`: a short, unseen connection that only runs commands — Active asking a host which
    /// tmux sessions it has (D44). No shell, no window, not listed, not "last connected".
    enum Purpose { case terminal, sftp, probe }
    let purpose: Purpose
    typealias TerminalWriteSink = @MainActor (Data) async throws -> Void
    typealias TerminalResizeSink = @MainActor (_ rows: Int, _ columns: Int) async throws -> Void
    typealias LifecycleHook = @MainActor (TerminalSessionLifecycleTransition) -> Task<Void, Never>?
    typealias InitialTerminalPresentationRequest = @MainActor (TerminalSession) -> Void

    private struct PendingTerminalWrite {
        let data: Data
        let presentsFailure: Bool
    }

    let id: UUID
    var server: ServerConfiguration
    /// The terminal emulator belongs to the live session rather than any one
    /// presentation. Adaptive tab/sidebar changes may reconstruct views, but
    /// must not discard scrollback, search state, or pending terminal input.
    let terminalHostModel = SwiftTermHostModel()
    
    var state: SessionState = .disconnected {
        didSet {
            if oldValue != .connected, state == .connected {
                if usesTmux { attachTmux() } else { dispatchStartupCommandIfNeeded(); checkTmuxAvailability() }
            }
        }
    }
    var output: [TerminalLine] = []
    /// One per chunk of output, up to 125 a second. Not observed: every view reading it was
    /// rebuilt per chunk — on Vision Pro the whole terminal window, ornaments and focused values
    /// with it (W10, 2026-10-08). Views that care about output use `outputSettledNonce`.
    @ObservationIgnored var terminalInputNonce: UInt64 = 0
    /// Changes once output has been quiet for `outputSettleDelay`: when a busy screen has come to
    /// rest, at most once per burst of output.
    private(set) var outputSettledNonce: UInt64 = 0
    @ObservationIgnored var outputSettleDelay: Duration = .milliseconds(800)
    @ObservationIgnored private var lastOutputInstant: ContinuousClock.Instant?
    @ObservationIgnored private var outputSettleTask: Task<Void, Never>?
    var closeWindowNonce: UInt64 = 0
    var currentDirectory: String = "~"
    var pendingHostKeyChallenge: HostKeyTrustChallenge?
    var lastConnectionDiagnostics: String?
    var connectionProgress: ConnectionProgressStage?
    
    // Terminal properties
    let maxScrollback: Int = 10000
    
    // Jump host chain (resolved before connect, ordered first-hop to last-hop)
    var jumpHostChain: [ServerConfiguration] = []
    var connectionPreparation: SessionConnectionPreparation?

    // SSH Connection
    private var sshConnection: SSHConnection?
    private var pendingTerminalOutput = Data()
    private var terminalFlushTask: Task<Void, Never>?
    private var terminalFlushGeneration: UInt64 = 0
    private let terminalFlushInterval: Duration = .milliseconds(8)
    private let terminalWriteSink: TerminalWriteSink?
    private var pendingTerminalWrites: [PendingTerminalWrite] = []
    private var terminalWriteTask: Task<Void, Never>?
    private var terminalWriteGeneration: UInt64 = 0
    private let terminalResizeSink: TerminalResizeSink?
    private var pendingTerminalResize: (rows: Int, columns: Int)?
    private var terminalResizeTask: Task<Void, Never>?
    private var terminalResizeGeneration: UInt64 = 0
    private var latestTerminalRows: Int = TerminalGeometry.default.rows
    private var latestTerminalColumns: Int = TerminalGeometry.default.columns
    private let initialTerminalGeometryEvents: AsyncStream<Void>
    private let initialTerminalGeometryContinuation: AsyncStream<Void>.Continuation
    private var initialTerminalPresentationRequest: InitialTerminalPresentationRequest?
    private(set) var didRequestInitialTerminalPresentation = false
    private(set) var hasMeasuredTerminalGeometry = false
    private var userInitiatedDisconnect: Bool = false
    private var reconnectTask: Task<Void, Never>?
    var reconnectAttemptCount: Int = 0
    var recorder: SessionRecorder?
    var reconnectPreparation: ((ServerConfiguration) async throws -> SessionConnectionPreparation)?
    var automaticReconnectSucceeded: (() -> Void)?
    private var lifecycleHook: LifecycleHook?
    private var lifecycleCleanupPerformed = false
    private var lifecycleCleanupTask: Task<Void, Never>?
    private var startupCommandTicket: TerminalStartupCommandTicket?

    // MARK: tmux (D44)
    /// The tmux session this terminal lives in. Claimed on the first connect, or given by Active
    /// when attaching to a session already running; every reconnect attaches to it again.
    var tmuxSessionName: String?
    /// The first attach detaches any other client — Active's "Take Over".
    var tmuxTakesOver = false
    /// The host had no tmux when this terminal connected: it is an ordinary shell.
    private(set) var tmuxUnavailable = false
    /// Told what each connection found: whether the host has tmux. Installed by the session
    /// manager, which records it on the server and decides whether to offer the setting.
    var tmuxAvailabilityObserved: (@MainActor (Bool) -> Void)?
    /// Ask this terminal's owner whether to keep terminals on this server in tmux (D44).
    var tmuxOffer = false
    /// Runs a command on the host and returns its output. Tests replace it; otherwise an exec
    /// channel on this session's own transport.
    var tmuxCommandRunner: (@MainActor (String) async throws -> String)?
    private var tmuxTask: Task<Void, Never>?
    /// `tmuxSessionName` was kept from before — W4b: a workgroup's saved session — rather than
    /// chosen in Active to join: the first attach claims it, making it again if it has ended.
    var tmuxClaimsGivenName = false
    /// Names a new session never takes, though the host may not be running them — W4b: those
    /// saved workgroups hold.
    var tmuxNamesHeld: (@MainActor () -> Set<String>)?
    /// The session was made for this terminal and the startup command has not followed yet.
    private var tmuxSessionIsNew = false
    /// W4b: told the name this terminal claimed for a new session, once it has one, so whoever
    /// opened it — a workgroup, a Mac tab — keeps the name and attaches to it next time.
    var tmuxSessionClaimed: (@MainActor (String) -> Void)?

    // MARK: Workgroup slots (W4b, 2026-10-08)
    /// What the workgroup calls this terminal, when it names it: the iPhone's switcher shows it.
    var workgroupLabel: String?
    /// One of the terminals an iPhone opens a workgroup with: it connects only when it is shown
    /// (owner, 2026-10-08: "opening a workgroup on iPhone would be a challenge"). Terminals opened
    /// any other way connect as they always have.
    var isWorkgroupSlot = false
    /// A slot that is not on screen: it connects when it is shown, and a connection it loses —
    /// the app was suspended — waits to be shown again rather than reconnecting unseen.
    var connectsWhenShown = false

    // MARK: What it is called (W11, 2026-10-09)
    //
    // The owner: "Terminal names aren't persisted between devices." A Mac tab keeps the name it
    // is given on its tmux session (`@glass-name`, W6), and names itself by its program's title,
    // repository and folder; an iPhone, iPad or Vision Pro showed the server's name. A terminal
    // there reads what its session says about itself — once attached, and when output settles —
    // and is named by the same rule.

    /// What its tmux session says about itself, last read: the name a tab gave it, its active
    /// pane's title and folder, and the repository and branch there.
    private(set) var tmuxPane: TerminalTmux.PaneState?
    /// The name someone gave this terminal, here or on another device through its session.
    private(set) var givenName: String?
    /// Reads `tmuxPane` on devices without the Mac's tabs. On the Mac a tab turns it on for its
    /// SSH panes (W19), and asks this Mac's own tmux for its local ones.
    #if os(macOS)
    @ObservationIgnored var readsTmuxPane = false
    #else
    @ObservationIgnored var readsTmuxPane = true
    #endif
    /// Told what each read found (W19): a Mac tab names itself from it. `firstSinceAttach` is
    /// true for the first read after the terminal attached, or attached again: the session may be
    /// a new one made under the same name, which knows nothing of the name the tab had.
    @ObservationIgnored var tmuxPaneObserved: (@MainActor (_ pane: TerminalTmux.PaneState, _ firstSinceAttach: Bool) -> Void)?
    /// A read has answered since the terminal last attached.
    @ObservationIgnored private var tmuxPaneReadSinceAttach = false
    /// The least time between two reads. Output settling inside it asks for one more at its end;
    /// a quiet terminal is never asked.
    @ObservationIgnored var tmuxPaneReadInterval: Duration = .seconds(5)
    @ObservationIgnored private var tmuxPaneRead: Task<Void, Never>?
    @ObservationIgnored private var tmuxPaneReadAt: ContinuousClock.Instant?
    @ObservationIgnored private var tmuxPaneReadWanted = false
    /// Counts namings here, so an answer asked for before one is not taken after it.
    @ObservationIgnored private var givenNameGeneration: UInt64 = 0
    /// The last name sent to the session; a read waits for it, and the next name follows it.
    @ObservationIgnored private var givenNameWrite: Task<Void, Never>?

    /// What this terminal is called away from the Mac's tabs, by the rule they and Active share
    /// (`TerminalSessionNaming`): a given name, the workgroup's label for it, its program's title,
    /// its repository, its folder. Nil when nothing names it, and the caller says the server.
    var terminalName: String? {
        givenName ?? workgroupLabel
            ?? TerminalSessionNaming.automaticName(title: tmuxPane?.title, directory: tmuxPane?.directory,
                                                   home: tmuxPane?.home, repository: tmuxPane?.repository)
    }

    /// In a repository, its name and branch, said before the machine as a Mac's SSH tab says them.
    var repositoryLine: String? {
        TerminalSessionNaming.location(directory: nil, home: nil, repository: tmuxPane?.repository)
    }

    /// Names this terminal, as a Mac tab's Rename does (W6): its tmux session keeps the name as
    /// `@glass-name`, so every device shows it. Nil or blank goes back to the automatic name.
    /// Outside tmux the name is this device's alone.
    func rename(to name: String?) {
        let value = name.flatMap { TerminalSessionNaming.displayText($0) }
        givenNameGeneration &+= 1
        givenName = value
        guard survivesClose, state == .connected, let session = tmuxSessionName,
              let command = TerminalTmux.givenNameCommand(session: session, name: value) else { return }
        // One after another, so a rename and its undo reach the host in that order.
        let previous = givenNameWrite
        givenNameWrite = Task { [weak self] in
            await previous?.value
            do { _ = try await self?.runTmuxCommand(command) } catch {
                Logger.ssh.notice("A terminal's name didn't reach its tmux session: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Asks its tmux session what it says about itself, in one command: at once, or at the end of
    /// the interval when it was asked within it. Called once attached and when output settles.
    func readTmuxPaneIfDue() {
        guard readsTmuxPane, purpose == .terminal, survivesClose, state == .connected,
              let name = tmuxSessionName, let command = TerminalTmux.paneStateCommand(session: name) else { return }
        guard tmuxPaneRead == nil else {
            tmuxPaneReadWanted = true
            return
        }
        tmuxPaneRead = Task { [weak self] in
            if let due = self?.tmuxPaneReadDue, ContinuousClock.now < due {
                try? await Task.sleep(until: due, clock: .continuous)
            }
            await self?.readTmuxPane(command)
        }
    }

    private var tmuxPaneReadDue: ContinuousClock.Instant? {
        tmuxPaneReadAt.map { $0 + tmuxPaneReadInterval }
    }

    private func readTmuxPane(_ command: String) async {
        defer {
            tmuxPaneRead = nil
            if tmuxPaneReadWanted { readTmuxPaneIfDue() }
        }
        guard state == .connected else { return }
        // This read answers for every settle so far; one after it starts asks again.
        tmuxPaneReadWanted = false
        // A name on its way to the host is read back, not the one it replaces.
        await givenNameWrite?.value
        let generation = givenNameGeneration
        tmuxPaneReadAt = .now
        guard let answer = try? await runTmuxCommand(command),
              let pane = TerminalTmux.parsePaneState(answer) else { return }
        if tmuxPane != pane { tmuxPane = pane }
        if generation == givenNameGeneration, givenName != pane.givenName { givenName = pane.givenName }
        let first = !tmuxPaneReadSinceAttach
        tmuxPaneReadSinceAttach = true
        tmuxPaneObserved?(pane, first)
    }

    /// A slot just shown should connect: it never has, or it lost its connection while hidden or
    /// failed to open. Not one someone disconnected, one already on its way, or one waiting for a
    /// host-key answer.
    var connectsOnShow: Bool {
        guard purpose == .terminal, !userInitiatedDisconnect, pendingHostKeyChallenge == nil else { return false }
        switch state {
        case .disconnected, .error: return true
        case .connecting, .connected, .reconnecting: return false
        }
    }

    init(
        server: ServerConfiguration,
        purpose: Purpose = .terminal,
        initialTerminalGeometry: TerminalGeometry = .default,
        terminalWriteSink: TerminalWriteSink? = nil,
        terminalResizeSink: TerminalResizeSink? = nil
    ) {
        let geometryEvents = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.id = UUID()
        self.purpose = purpose
        self.server = server
        self.terminalWriteSink = terminalWriteSink
        self.terminalResizeSink = terminalResizeSink
        self.initialTerminalGeometryEvents = geometryEvents.stream
        self.initialTerminalGeometryContinuation = geometryEvents.continuation
        self.latestTerminalRows = initialTerminalGeometry.rows
        self.latestTerminalColumns = initialTerminalGeometry.columns
        let connection = SSHConnection(session: self)
        connection.setPreferredTerminalSize(
            rows: latestTerminalRows,
            columns: latestTerminalColumns
        )
        self.sshConnection = connection
        terminalHostModel.onAlternateScreenScroll = { [weak self] deltaY, precise in
            self?.scrollTmux(deltaY: deltaY, precise: precise) ?? false
        }
    }

    // MARK: Scrolling in tmux (2026-10-08)

    /// tmux draws on the alternate screen, so the terminal has no scrollback of its own and a
    /// scroll would arrive as arrow keys. A terminal in tmux scrolls tmux's history on the host
    /// instead, over this connection; scrolling gathered while one command is on its way follows it.
    private var pendingTmuxScroll: Double = 0
    private var tmuxScrollInFlight = false

    func scrollTmux(deltaY: CGFloat, precise: Bool) -> Bool {
        guard survivesClose, state == .connected else { return false }
        // A trackpad reports points, a mouse wheel lines; a terminal line is about 16 points.
        pendingTmuxScroll += precise ? Double(deltaY) / 16 : Double(deltaY)
        sendTmuxScroll()
        return true
    }

    private func sendTmuxScroll() {
        guard !tmuxScrollInFlight, let name = tmuxSessionName else { return }
        let lines = Int(pendingTmuxScroll.rounded(.towardZero))
        guard lines != 0 else { return }
        pendingTmuxScroll -= Double(lines)
        tmuxScrollInFlight = true
        Task { [weak self] in
            _ = try? await self?.runTmuxCommand(TerminalTmux.scrollCommand(name: name, lines: lines))
            guard let self else { return }
            tmuxScrollInFlight = false
            sendTmuxScroll()
        }
    }

    isolated deinit {
        terminalFlushTask?.cancel()
        terminalWriteTask?.cancel()
        terminalResizeTask?.cancel()
        reconnectTask?.cancel()
        tmuxTask?.cancel()
        outputSettleTask?.cancel()
        initialTerminalGeometryContinuation.finish()
    }

    func getSSHConnection() -> SSHConnection? { sshConnection }

    func installLifecycleHook(_ hook: @escaping LifecycleHook) {
        lifecycleHook = hook
    }

    func installInitialTerminalPresentationRequest(
        _ request: @escaping InitialTerminalPresentationRequest
    ) {
        guard !didRequestInitialTerminalPresentation else { return }
        initialTerminalPresentationRequest = request
    }

    var currentTerminalGeometry: TerminalGeometry {
        TerminalGeometry(rows: latestTerminalRows, columns: latestTerminalColumns)
    }

    func updateConfiguredInitialTerminalGeometry(_ geometry: TerminalGeometry) {
        guard !hasMeasuredTerminalGeometry else { return }
        latestTerminalRows = geometry.rows
        latestTerminalColumns = geometry.columns
        sshConnection?.setPreferredTerminalSize(rows: geometry.rows, columns: geometry.columns)
    }

    /// Requests the terminal surface only after transport authentication has
    /// succeeded, then gives its first measured resize a bounded opportunity to
    /// define the initial remote PTY. Background/headless sessions retain their
    /// configured fallback and never block indefinitely.
    @discardableResult
    func prepareInitialTerminalPresentation(
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        if hasMeasuredTerminalGeometry { return true }
        guard let request = initialTerminalPresentationRequest else { return false }

        initialTerminalPresentationRequest = nil
        didRequestInitialTerminalPresentation = true
        request(self)
        if hasMeasuredTerminalGeometry { return true }

        let events = initialTerminalGeometryEvents
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = events.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return false
                }
                return false
            }

            let measured = await group.next() ?? false
            group.cancelAll()
            return measured
        }
    }

    /// Arms one launch-time command before the initial connection attempt.
    /// Reconnect never replenishes a claimed ticket.
    @discardableResult
    func installStartupCommand(_ command: String?) -> Bool {
        guard startupCommandTicket == nil,
              let ticket = TerminalStartupCommandTicket(command: command) else { return false }
        startupCommandTicket = ticket
        return true
    }

    var hasPendingStartupCommand: Bool { startupCommandTicket != nil }

    /// Runs once for each attached SSH connection. Repeated terminal errors,
    /// reconnect signals, and close requests for the same transport are harmless.
    func performLifecycleCleanup(for transition: TerminalSessionLifecycleTransition) {
        guard !lifecycleCleanupPerformed else { return }
        lifecycleCleanupPerformed = true
        lifecycleCleanupTask = lifecycleHook?(transition)
    }

    func awaitLifecycleCleanup() async {
        await lifecycleCleanupTask?.value
    }

    /// Extends the current resource cleanup so callers awaiting the lifecycle
    /// boundary also wait for the detached SSH transport to close. This is used
    /// by synchronous error callbacks that cannot themselves `await`.
    private func appendTransportDisconnectToLifecycleCleanup(_ connection: SSHConnection?) {
        let resourceCleanup = lifecycleCleanupTask
        lifecycleCleanupTask = Task {
            await resourceCleanup?.value
            await connection?.disconnect()
        }
    }

    /// The sole boundary for detaching an SSH connection. Session-owned
    /// resources are stopped before callers can disconnect or replace it.
    func detachSSHConnection(for transition: TerminalSessionLifecycleTransition) -> SSHConnection? {
        performLifecycleCleanup(for: transition)
        let detachedConnection = sshConnection
        sshConnection = nil
        return detachedConnection
    }

    // Hashable conformance
    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func connect() async {
        userInitiatedDisconnect = false
        if state == .connecting {
            appendLine(TerminalLine(text: "Connection already in progress. Please wait…", style: .system))
            return
        }

        if state == .connected {
            appendLine(TerminalLine(text: "Already connected to \(server.name).", style: .system))
            return
        }

        if sshConnection == nil {
            sshConnection = makeConfiguredSSHConnection()
        }

        state = .connecting
        connectionProgress = .resolvingDNS
        lastConnectionDiagnostics = nil
        appendLine(TerminalLine(text: "Connecting to \(server.name)...", style: .system))
        
        do {
            guard connectionPreparation != nil || sshConnection?.hasReusableTransport == true else {
                throw SSHError.invalidCredentialPreparation
            }
            let preparation = connectionPreparation
            self.connectionPreparation = nil
            try await sshConnection?.connect(
                preparation: preparation,
                jumpHostChain: jumpHostChain
            )
            pendingHostKeyChallenge = nil
            connectionProgress = nil
            lastConnectionDiagnostics = nil
            state = .connected
            lifecycleCleanupPerformed = false
            appendLine(TerminalLine(text: "✓ Connected to \(server.username)@\(server.host)", style: .system))
        } catch {
            if let challengeError = error as? HostKeyTrustRequiredError {
                pendingHostKeyChallenge = challengeError.challenge
            } else if let cachedChallenge = sshConnection?.takePendingHostKeyChallenge() {
                pendingHostKeyChallenge = cachedChallenge
            }
            let failedConnection = detachSSHConnection(for: .terminalError)
            let mode = HostKeyVerificationMode(
                rawValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.hostKeyVerificationMode) ?? ""
            ) ?? .ask
            let message: String
            if let challenge = pendingHostKeyChallenge {
                switch mode {
                case .ask:
                    message = "Host key verification required for \(challenge.host):\(challenge.port)."
                case .strict:
                    message = "Strict host-key verification blocked the connection to \(challenge.host):\(challenge.port)."
                }
            } else {
                message = SSHConnection.userFacingMessage(for: error, server: server)
            }
            Logger.ssh.error(
                "SSH connect error (\(self.server.host):\(self.server.port)); category=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            lastConnectionDiagnostics =
                "Attempted: \(server.host):\(server.port)\nAuth method: \(server.authMethod.displayName)\nHost key mode: \(mode.rawValue)\nFailure category: \(String(reflecting: type(of: error)))"
            connectionProgress = nil
            state = .error(message)
            recorder?.finalize()
            appendLine(TerminalLine(text: "✗ \(message)", style: .error))
            await awaitLifecycleCleanup()
            await failedConnection?.disconnect()
        }
    }
    
    func disconnect() {
        userInitiatedDisconnect = true
        flushPendingTerminalOutputNow()
        cancelPendingTerminalWrites()
        cancelPendingTerminalResizes()
        recorder?.finalize()
        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionToDisconnect = detachSSHConnection(for: .explicitDisconnect)
        connectionProgress = nil
        state = .disconnected
        appendTransportDisconnectToLifecycleCleanup(connectionToDisconnect)
    }

    func reconnect() async {
        state = .reconnecting
        flushPendingTerminalOutputNow()
        cancelPendingTerminalWrites()
        cancelPendingTerminalResizes()
        recorder?.finalize()
        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionToDisconnect = detachSSHConnection(for: .manualReconnect)
        await awaitLifecycleCleanup()
        await connectionToDisconnect?.disconnect()
        sshConnection = makeConfiguredSSHConnection()
        connectionProgress = nil
        state = .disconnected
        await connect()
    }

    func attemptAutoReconnect(autoReconnectEnabled: Bool) {
        guard autoReconnectEnabled,
              purpose == .terminal,
              !userInitiatedDisconnect
        else { return }
        // W4b: a slot hidden on an iPhone reconnects when it is shown (`connectsOnShow`), so a
        // workgroup coming back from suspension reconnects only the terminal on screen.
        guard !connectsWhenShown else { return }

        reconnectTask?.cancel()
        flushPendingTerminalOutputNow()
        cancelPendingTerminalWrites()
        cancelPendingTerminalResizes()
        reconnectAttemptCount = 0
        state = .reconnecting
        appendLine(TerminalLine(text: "Connection lost. Auto-reconnecting...", style: .system))
        let initialConnection = detachSSHConnection(for: .automaticReconnect)

        reconnectTask = Task { [weak self] in
            let maxAttempts = 5
            var connectionToDisconnect = initialConnection

            for attempt in 1...maxAttempts {
                guard !Task.isCancelled, let self else { return }

                await self.awaitLifecycleCleanup()
                await connectionToDisconnect?.disconnect()
                connectionToDisconnect = nil

                self.reconnectAttemptCount = attempt
                let delay = min(UInt64(pow(2.0, Double(attempt - 1))), 30)
                self.appendLine(TerminalLine(
                    text: "Reconnect attempt \(attempt)/\(maxAttempts) in \(delay)s...",
                    style: .system
                ))

                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch { return }

                guard !Task.isCancelled else { return }

                let preparation: SessionConnectionPreparation
                do {
                    guard let reconnectPreparation = self.reconnectPreparation else {
                        throw SSHError.invalidCredentialPreparation
                    }
                    preparation = try await reconnectPreparation(self.server)
                } catch {
                    self.state = .error(error.localizedDescription)
                    self.appendLine(TerminalLine(text: "Auto-reconnect blocked: \(error.localizedDescription)", style: .error))
                    self.reconnectTask = nil
                    return
                }

                guard !Task.isCancelled else { return }
                self.connectionPreparation = preparation
                self.sshConnection = self.makeConfiguredSSHConnection()
                await self.connect()

                if self.state == .connected {
                    self.appendLine(TerminalLine(text: "Reconnected successfully.", style: .system))
                    self.reconnectTask = nil
                    self.automaticReconnectSucceeded?()
                    return
                }

                if attempt < maxAttempts {
                    connectionToDisconnect = self.sshConnection
                    self.sshConnection = nil
                    self.cancelPendingTerminalWrites()
                    self.cancelPendingTerminalResizes()
                    self.state = .reconnecting
                }
            }

            guard let self, !Task.isCancelled else { return }
            let failedConnection = self.sshConnection
            self.sshConnection = nil
            await failedConnection?.disconnect()
            self.state = .error("Reconnect failed after 5 attempts")
            self.appendLine(TerminalLine(text: "Auto-reconnect failed after 5 attempts.", style: .error))
            self.reconnectTask = nil
        }
    }

    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttemptCount = 0
        if state == .reconnecting {
            state = .disconnected
            appendLine(TerminalLine(text: "Auto-reconnect cancelled.", style: .system))
        }
    }
    
    func sendCommand(_ command: String) {
        guard state == .connected else {
            appendLine(TerminalLine(text: "Error: terminal is not connected.", style: .error))
            return
        }
        let data = Data((command + "\n").utf8)
        // Generated commands, suggested fixes, and snippets share the exact
        // same consented input-recording path as keyboard bytes.
        recorder?.recordInput(data)
        enqueueTerminalWrite(data, presentsFailure: true)
    }

    var usesTmux: Bool {
        purpose == .terminal && !tmuxUnavailable && (tmuxSessionName != nil || server.keepsSessionsInTmux)
    }

    /// Types the attach line once the shell is up, after claiming a name the first time. The
    /// workgroup's startup command, when there is one, follows it — only into a session made for
    /// this terminal. One it joins is running something already, and the command would be typed
    /// into that (2026-10-08).
    private func attachTmux() {
        tmuxTask?.cancel()
        tmuxTask = Task { [weak self] in
            guard let self else { return }
            if tmuxSessionName == nil {
                guard await claimNewTmuxSession() else { return }
                if let claimed = tmuxSessionName { tmuxSessionClaimed?(claimed) }
            } else if tmuxClaimsGivenName, let given = tmuxSessionName {
                guard await claimGivenTmuxSession(given) else { return }
            }
            guard state == .connected, !Task.isCancelled, let name = tmuxSessionName else { return }
            let data = Data((TerminalTmux.attachLine(name: name, takeOver: tmuxTakesOver) + "\n").utf8)
            tmuxTakesOver = false
            recorder?.recordInput(data)
            enqueueTerminalWrite(data, presentsFailure: true)
            if tmuxSessionIsNew {
                tmuxSessionIsNew = false
                dispatchStartupCommandIfNeeded()
            } else {
                startupCommandTicket = nil
            }
            // What the session is called and shows (W11): a name given on another device, at once.
            tmuxPaneReadSinceAttach = false
            readTmuxPaneIfDue()
        }
    }

    /// Claims a name for a new terminal: the lowest free `glass-N` when the host's list reads,
    /// numbers far above those in use when it does not. Without the claim, two devices choosing
    /// from one list both attached to the same name (2026-10-08). False when the attach should
    /// not follow: tmux is missing, or the terminal went away.
    private func claimNewTmuxSession() async -> Bool {
        let held = tmuxNamesHeld?() ?? []
        var candidates: [String]?
        do {
            switch TerminalTmux.parse(try await listTmuxSessionsRetryingOnce()) {
            case .unavailable:
                guard state == .connected, !Task.isCancelled else { return false }
                hostHasNoTmux()
                return false
            case .sessions(let sessions):
                tmuxAvailabilityObserved?(true)
                candidates = TerminalTmux.claimCandidates(avoiding: held.union(sessions.map(\.name)))
            case .failed:
                tmuxAvailabilityObserved?(true)
                Logger.ssh.error("tmux answered the session list with something other than a list")
                candidates = TerminalTmux.unlistedCandidates(avoiding: held)
            }
        } catch {
            Logger.ssh.error("tmux list failed: \(error.localizedDescription, privacy: .public)")
        }
        guard state == .connected, !Task.isCancelled else { return false }
        if let candidates {
            if case .created(let name) = await claimTmuxSession(candidates) {
                tmuxSessionName = name
                tmuxSessionIsNew = true
                return true
            }
            guard state == .connected, !Task.isCancelled else { return false }
        }
        // The host could not be asked, or would not say: a number nothing is likely to hold,
        // which the attach line makes. New all the same, so the startup command follows.
        tmuxSessionName = TerminalTmux.unlistedName(avoiding: held.union(candidates ?? []))
        tmuxSessionIsNew = true
        return true
    }

    /// Claims a name this terminal kept: made again when it has ended — and only then does the
    /// startup command run — joined when it is still running.
    private func claimGivenTmuxSession(_ name: String) async -> Bool {
        tmuxClaimsGivenName = false
        let claim = await claimTmuxSession([name])
        guard state == .connected, !Task.isCancelled else { return false }
        switch claim {
        case .created:
            tmuxAvailabilityObserved?(true)
            tmuxSessionIsNew = true
        case .exists:
            tmuxAvailabilityObserved?(true)
        case .unavailable:
            hostHasNoTmux()
            return false
        case .failed:
            // Unknown whether it runs: attach (`-A` makes it if not), and type nothing into it.
            break
        }
        return true
    }

    private func claimTmuxSession(_ candidates: [String]) async -> TerminalTmux.Claim {
        do {
            let output = try await runTmuxCommand(TerminalTmux.claimCommand(candidates: candidates))
            let claim = TerminalTmux.parseClaim(output, candidates: candidates)
            if claim == .failed { Logger.ssh.error("tmux would not make a session under any name it was offered") }
            return claim
        } catch {
            Logger.ssh.error("tmux claim failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// The host has no tmux: this terminal is an ordinary shell, and its startup command runs there.
    private func hostHasNoTmux() {
        tmuxAvailabilityObserved?(false)
        tmuxUnavailable = true
        showLocalNotice("tmux isn't installed on \(server.name), so this terminal stops when you disconnect. "
            + "Install tmux there to keep it running, or turn off Keep Sessions Running with tmux for this server.")
        dispatchStartupCommandIfNeeded()
    }

    /// A terminal without the setting still asks whether the host has tmux, once per connection,
    /// so the server form knows whether the setting can be offered (D44). Nothing is typed.
    private func checkTmuxAvailability() {
        guard purpose == .terminal, tmuxAvailabilityObserved != nil else { return }
        tmuxTask?.cancel()
        tmuxTask = Task { [weak self] in
            guard let self, let output = try? await runTmuxCommand(TerminalTmux.listCommand),
                  !Task.isCancelled, state == .connected else { return }
            tmuxAvailabilityObserved?(TerminalTmux.parse(output) != .unavailable)
        }
    }

    /// Closing this terminal leaves its work running on the host: it is attached to a tmux
    /// session, which outlives the connection and is listed in Active (D44).
    var survivesClose: Bool { usesTmux && tmuxSessionName != nil }

    /// Closing this terminal would stop something: it is connected, or connecting, and not in tmux.
    /// The one rule every "close?" question asks.
    var closeStopsWork: Bool {
        switch state {
        case .connected, .connecting, .reconnecting: !survivesClose
        default: false
        }
    }

    /// Where this shell is standing, for the AI assistant and Open Folder Here. Outside tmux, what
    /// the shell reported over OSC 7. **In tmux those reports stop at tmux**, so the terminal's
    /// value is wherever the shell was before tmux started — usually home — and the assistant
    /// suggested commands for the wrong directory (2026-10-03). tmux is asked instead, and an
    /// unanswered question is "unknown", never the stale value.
    func workingDirectory(reported: String?) async -> String? {
        guard survivesClose, let name = tmuxSessionName else { return reported }
        let path = try? await runTmuxCommand(TerminalTmux.currentPathCommand(name: name))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.flatMap { $0.hasPrefix("/") ? $0 : nil }
    }

    /// Waits for the attach in progress, if any — for tests and for callers that act after it.
    func waitForTmuxAttach() async { await tmuxTask?.value }

    /// The host's tmux sessions, asked again once after a second if the first ask fails: the
    /// connection that has just opened is the one the question travels on.
    private func listTmuxSessionsRetryingOnce() async throws -> String {
        do {
            return try await runTmuxCommand(TerminalTmux.listCommand)
        } catch {
            Logger.ssh.notice("tmux list failed once, asking again: \(error.localizedDescription, privacy: .public)")
            try await Task.sleep(for: .seconds(1))
            return try await runTmuxCommand(TerminalTmux.listCommand)
        }
    }

    func runTmuxCommand(_ command: String) async throws -> String {
        if let tmuxCommandRunner { return try await tmuxCommandRunner(command) }
        guard let sshConnection else { throw SSHError.notConnected }
        return try await sshConnection.executeRemoteCommand(command, maxResponseBytes: 256 * 1024,
                                                            executionTimeout: .seconds(15))
    }

    /// A line shown in this terminal only; nothing is sent to the host.
    private func showLocalNotice(_ text: String) {
        flushPendingTerminalOutputNow()
        emitTerminalChunk(Data("\r\n\u{1B}[2m\(text)\u{1B}[0m\r\n".utf8))
    }

    private func dispatchStartupCommandIfNeeded() {
        guard state == .connected, let ticket = startupCommandTicket else { return }
        // Claim before enqueueing. If the remote receives only part of a write,
        // automatically retrying could execute a destructive command twice.
        startupCommandTicket = nil
        let data = Data((ticket.command + "\n").utf8)
        recorder?.recordInput(data)
        enqueueTerminalWrite(data, presentsFailure: true)
    }
    
    func sendTerminalData(_ data: Data) {
        guard state == .connected else {
            Logger.ssh.debug("Ignoring terminal input while session is not connected")
            return
        }
        recorder?.recordInput(data)
        enqueueTerminalWrite(data, presentsFailure: false)
    }

    func handleCleanRemoteExit() {
        let connectionToDisconnect = detachSSHConnection(for: .cleanRemoteExit)
        flushPendingTerminalOutputNow()
        cancelPendingTerminalWrites()
        cancelPendingTerminalResizes()
        recorder?.finalize()
        connectionProgress = nil
        state = .disconnected
        closeWindowNonce &+= 1
        Task {
            await self.awaitLifecycleCleanup()
            await connectionToDisconnect?.disconnect()
        }
    }
    
    func appendLine(_ line: TerminalLine) {
        output.append(line)
        
        // Manage scrollback
        if output.count > maxScrollback {
            let excess = output.count - maxScrollback
            output.removeFirst(excess)
        }
    }
    
    func clearScreen() {
        let clearSequence = "\u{1b}[2J\u{1b}[H"
        // Preserve bytes that arrived immediately before the user's clear
        // action. SwiftTerm must observe them before the clear sequence so the
        // transport boundary never silently discards remote output.
        flushPendingTerminalOutputNow()
        if let clearData = clearSequence.data(using: .utf8) {
            emitTerminalChunk(clearData)
        }
        output.removeAll()
    }
    
    func reportError(_ message: String) {
        let failedConnection = detachSSHConnection(for: .terminalError)
        appendTransportDisconnectToLifecycleCleanup(failedConnection)
        flushPendingTerminalOutputNow()
        cancelPendingTerminalWrites()
        cancelPendingTerminalResizes()
        recorder?.finalize()
        connectionProgress = nil
        state = .error(message)
        appendLine(TerminalLine(text: "✗ \(message)", style: .error))
    }

    func setConnectionProgress(_ progress: ConnectionProgressStage?) {
        connectionProgress = progress
    }
    
    func feedTerminalData(_ data: Data) {
        pendingTerminalOutput.append(data)
        recorder?.recordOutput(data)
        scheduleTerminalFlush()
    }
    
    func updateTerminalGeometry(rows: Int, columns: Int) {
        let measuredGeometry = TerminalGeometry(measuredRows: rows, columns: columns)
        let clampedRows = measuredGeometry.rows
        let clampedColumns = measuredGeometry.columns
        latestTerminalRows = clampedRows
        latestTerminalColumns = clampedColumns
        if !hasMeasuredTerminalGeometry {
            hasMeasuredTerminalGeometry = true
            initialTerminalGeometryContinuation.yield()
            initialTerminalGeometryContinuation.finish()
        }
        recorder?.recordResize(width: clampedColumns, height: clampedRows)

        sshConnection?.setPreferredTerminalSize(rows: clampedRows, columns: clampedColumns)

        guard state == .connected else { return }
        pendingTerminalResize = (rows: clampedRows, columns: clampedColumns)
        scheduleTerminalResizeDrainIfNeeded()
    }

    private func emitTerminalChunk(_ data: Data) {
        terminalInputNonce &+= 1
        // The emulator belongs to this live session. Feed it independently of
        // view presence so adaptive tab/sidebar reconstruction cannot delay or
        // duplicate remote output.
        terminalHostModel.ingest(data: data, nonce: terminalInputNonce)
        noteOutputForSettle()
    }

    /// One waiting task per burst rather than one per chunk: it sleeps until the latest output is
    /// `outputSettleDelay` old, then announces the quiet once.
    private func noteOutputForSettle() {
        lastOutputInstant = .now
        guard outputSettleTask == nil else { return }
        outputSettleTask = Task { @MainActor [weak self] in
            while let due = self?.outputSettleDue, ContinuousClock.now < due {
                do { try await Task.sleep(until: due, clock: .continuous) } catch { return }
            }
            guard let self else { return }
            outputSettleTask = nil
            outputSettledNonce &+= 1
            // A program may have retitled it, or changed folder or branch (W11).
            readTmuxPaneIfDue()
        }
    }

    private var outputSettleDue: ContinuousClock.Instant? {
        lastOutputInstant.map { $0 + outputSettleDelay }
    }

    private func scheduleTerminalFlush() {
        guard terminalFlushTask == nil else { return }
        let generation = terminalFlushGeneration
        terminalFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.terminalFlushInterval)
            } catch {
                return
            }
            guard generation == self.terminalFlushGeneration else { return }
            self.flushPendingTerminalOutput()
            self.terminalFlushTask = nil
            if !self.pendingTerminalOutput.isEmpty {
                self.scheduleTerminalFlush()
            }
        }
    }

    private func flushPendingTerminalOutput() {
        guard !pendingTerminalOutput.isEmpty else { return }
        let chunk = pendingTerminalOutput
        pendingTerminalOutput.removeAll(keepingCapacity: true)
        emitTerminalChunk(chunk)
    }

    private func flushPendingTerminalOutputNow() {
        terminalFlushGeneration &+= 1
        terminalFlushTask?.cancel()
        terminalFlushTask = nil
        flushPendingTerminalOutput()
    }

    private func enqueueTerminalWrite(_ data: Data, presentsFailure: Bool) {
        guard !data.isEmpty else { return }
        pendingTerminalWrites.append(PendingTerminalWrite(
            data: data,
            presentsFailure: presentsFailure
        ))
        scheduleTerminalWriteDrainIfNeeded()
    }

    private func scheduleTerminalWriteDrainIfNeeded() {
        guard terminalWriteTask == nil, !pendingTerminalWrites.isEmpty else { return }
        let generation = terminalWriteGeneration
        terminalWriteTask = Task { @MainActor [weak self] in
            await self?.drainTerminalWrites(generation: generation)
        }
    }

    private func drainTerminalWrites(generation: UInt64) async {
        while generation == terminalWriteGeneration,
              !Task.isCancelled,
              !pendingTerminalWrites.isEmpty {
            let write = pendingTerminalWrites.removeFirst()
            do {
                if let terminalWriteSink {
                    try await terminalWriteSink(write.data)
                } else if let sshConnection {
                    // Capture the current connection for this write. A
                    // reconnect cancels this generation before replacing it,
                    // so queued bytes can never leak into the next session.
                    try await sshConnection.sendBytes(write.data)
                } else {
                    throw SSHError.notConnected
                }
            } catch {
                guard generation == terminalWriteGeneration, !Task.isCancelled else { return }
                let presentsFailure = write.presentsFailure
                    || pendingTerminalWrites.contains(where: \.presentsFailure)
                pendingTerminalWrites.removeAll(keepingCapacity: true)
                if presentsFailure {
                    appendLine(TerminalLine(
                        text: "Error: \(error.localizedDescription)",
                        style: .error
                    ))
                } else {
                    Logger.ssh.error("Error sending terminal data: \(error)")
                }
                break
            }
        }

        guard generation == terminalWriteGeneration else { return }
        terminalWriteTask = nil
        scheduleTerminalWriteDrainIfNeeded()
    }

    private func cancelPendingTerminalWrites() {
        terminalWriteGeneration &+= 1
        terminalWriteTask?.cancel()
        terminalWriteTask = nil
        pendingTerminalWrites.removeAll(keepingCapacity: true)
    }

    /// Deterministic test/automation seam for ordering-sensitive input paths.
    func waitUntilTerminalWritesComplete() async {
        while let task = terminalWriteTask {
            await task.value
        }
    }

    private func scheduleTerminalResizeDrainIfNeeded() {
        guard terminalResizeTask == nil, pendingTerminalResize != nil else { return }
        let generation = terminalResizeGeneration
        terminalResizeTask = Task { @MainActor [weak self] in
            await self?.drainTerminalResizes(generation: generation)
        }
    }

    private func drainTerminalResizes(generation: UInt64) async {
        while generation == terminalResizeGeneration,
              !Task.isCancelled,
              let resize = pendingTerminalResize {
            // Clear before awaiting. Geometry changes that arrive while this
            // resize is in flight replace this value, so the next iteration
            // sends only the newest dimensions.
            pendingTerminalResize = nil
            do {
                if let terminalResizeSink {
                    try await terminalResizeSink(resize.rows, resize.columns)
                } else if let sshConnection {
                    try await sshConnection.resizeTerminal(
                        rows: resize.rows,
                        columns: resize.columns
                    )
                } else {
                    throw SSHError.notConnected
                }
            } catch {
                guard generation == terminalResizeGeneration, !Task.isCancelled else { return }
                Logger.ssh.error("Failed to resize remote PTY: \(error)")
            }
        }

        guard generation == terminalResizeGeneration else { return }
        terminalResizeTask = nil
        scheduleTerminalResizeDrainIfNeeded()
    }

    private func cancelPendingTerminalResizes() {
        terminalResizeGeneration &+= 1
        terminalResizeTask?.cancel()
        terminalResizeTask = nil
        pendingTerminalResize = nil
    }

    /// Deterministic test/automation seam for resize coalescing.
    func waitUntilTerminalResizesComplete() async {
        while let task = terminalResizeTask {
            await task.value
        }
    }

    private func makeConfiguredSSHConnection() -> SSHConnection {
        let connection = SSHConnection(session: self)
        connection.setPreferredTerminalSize(
            rows: latestTerminalRows,
            columns: latestTerminalColumns
        )
        return connection
    }
}

enum SessionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .error(let message): return "Error: \(message)"
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "circle.dotted"
        case .connected: return "circle.fill"
        case .reconnecting: return "arrow.clockwise.circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .reconnecting: return .yellow
        case .error: return .red
        }
    }
}

enum ConnectionProgressStage: Equatable {
    case resolvingDNS
    case openingSocket(port: Int)
    case negotiatingSecurity
    case negotiatingCompatibility
    case authenticating
    case startingShell

    var tickerLabel: String {
        switch self {
        case .resolvingDNS:
            return "DNS"
        case .openingSocket(let port):
            return "Connecting:\(port)"
        case .negotiatingSecurity:
            return "Negotiating"
        case .negotiatingCompatibility:
            return "Negotiating (Legacy)"
        case .authenticating:
            return "Authenticating"
        case .startingShell:
            return "Starting shell"
        }
    }

    static let orderedFlow: [ConnectionProgressStage] = [
        .resolvingDNS,
        .openingSocket(port: 22),
        .negotiatingSecurity,
        .authenticating,
        .startingShell
    ]

    var flowIndex: Int {
        switch self {
        case .resolvingDNS: return 0
        case .openingSocket: return 1
        case .negotiatingSecurity, .negotiatingCompatibility: return 2
        case .authenticating: return 3
        case .startingShell: return 4
        }
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let style: LineStyle
    let timestamp: Date = Date()
    
    enum LineStyle {
        case output
        case input
        case error
        case system
        case prompt
    }
}

// MARK: - Port Forwarding

enum TunnelStatus: String, Codable {
    case inactive
    case starting
    case active
    case error
    case stopping
}

struct PortForward: Identifiable, Codable {
    let id: UUID
    var type: ForwardType
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
    var status: TunnelStatus = .inactive
    var errorMessage: String?
    let dateCreated: Date

    var isActive: Bool { status == .active || status == .starting }
    
    enum ForwardType: String, Codable {
        case local // -L
        case remote // -R
        case dynamic // -D
        
        var displayName: String {
            switch self {
            case .local: return "Local"
            case .remote: return "Remote"
            case .dynamic: return "Dynamic (SOCKS)"
            }
        }
        
        var description: String {
            switch self {
            case .local: return "Forward local port to remote"
            case .remote: return "Forward remote port to local"
            case .dynamic: return "SOCKS proxy on local port"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        type: ForwardType,
        localPort: Int,
        remoteHost: String = "localhost",
        remotePort: Int
    ) {
        self.id = id
        self.type = type
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.status = .inactive
        self.dateCreated = Date()
    }
    
    var displayString: String {
        switch type {
        case .local:
            return "localhost:\(localPort) → \(remoteHost):\(remotePort)"
        case .remote:
            return "\(remoteHost):\(remotePort) → localhost:\(localPort)"
        case .dynamic:
            return "SOCKS proxy on localhost:\(localPort)"
        }
    }
}

// MARK: - HTML Preview

#if DEBUG
struct HTMLPreviewContext: Identifiable, Hashable, Codable {
    let id: UUID
    let sessionID: UUID
    let url: String
    let autoReload: Bool
    let reloadInterval: TimeInterval
    
    init(
        id: UUID = UUID(),
        sessionID: UUID,
        url: String,
        autoReload: Bool = true,
        reloadInterval: TimeInterval = 2.0
    ) {
        self.id = id
        self.sessionID = sessionID
        self.url = url
        self.autoReload = autoReload
        self.reloadInterval = reloadInterval
    }
}
#endif

// MARK: - SFTP Browser

struct SFTPBrowserContext: Codable, Hashable {
    let sessionID: UUID
    /// Where to open, when the caller knows. "Open Folder Here" passes the shell's own working
    /// directory, so the browser arrives where the user already is instead of at the root and
    /// leaving them to walk back down. Nil keeps the previous behaviour.
    var initialPath: String?

    init(sessionID: UUID, initialPath: String? = nil) {
        self.sessionID = sessionID
        self.initialPath = initialPath
    }
}

// MARK: - Snippets

struct CommandSnippet: Identifiable, Codable {
    let id: UUID
    var name: String
    var command: String
    var description: String
    var tags: [String]
    let dateCreated: Date
    var lastUsed: Date?
    var useCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        description: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.description = description
        self.tags = tags
        self.dateCreated = Date()
        self.lastUsed = nil
        self.useCount = 0
    }
}

// MARK: - Terminal Theme

enum TerminalThemeAppearance: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case light
    case dark

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct TerminalTheme: Identifiable, Codable, Equatable {
    nonisolated static let defaultID = UUID(uuidString: "76DC53ED-1753-43D4-9E3F-2C9B0CE43CD2")!
    /// The built-in theme's identifier until 2026-09-27, still read from saved and synced libraries
    /// and rewritten to `defaultID` (`canonicalize()` re-identifies the built-in record). Never written.
    nonisolated static let legacyDefaultID = UUID(uuidString: "B16B00B5-7E4D-4A51-9A9E-474C41535348")!
    nonisolated static let maximumNameLength = 128
    nonisolated static let maximumFontNameLength = 128
    nonisolated static let minimumFontSize: CGFloat = 10
    nonisolated static let maximumFontSize: CGFloat = 24
    let id: UUID
    var name: String
    var background: CodableColor
    var foreground: CodableColor
    var cursor: CodableColor
    var selection: CodableColor
    
    // ANSI colors
    var black: CodableColor
    var red: CodableColor
    var green: CodableColor
    var yellow: CodableColor
    var blue: CodableColor
    var magenta: CodableColor
    var cyan: CodableColor
    var white: CodableColor
    
    // Bright variants
    var brightBlack: CodableColor
    var brightRed: CodableColor
    var brightGreen: CodableColor
    var brightYellow: CodableColor
    var brightBlue: CodableColor
    var brightMagenta: CodableColor
    var brightCyan: CodableColor
    var brightWhite: CodableColor
    
    var fontName: String
    var fontSize: CGFloat
    /// Optional for backward-compatible decoding of themes created before
    /// canvas appearance became theme metadata. A missing or automatic value
    /// derives a stable light/dark canvas from the theme background instead of
    /// allowing system appearance to wash out an imported terminal palette.
    var preferredAppearance: TerminalThemeAppearance? = nil

    /// ANSI colors in the index order expected by terminal emulators:
    /// normal 0...7 followed by bright 8...15.
    var ansiColors: [CodableColor] {
        [
            black, red, green, yellow, blue, magenta, cyan, white,
            brightBlack, brightRed, brightGreen, brightYellow,
            brightBlue, brightMagenta, brightCyan, brightWhite,
        ]
    }

    var isValidForPersistence: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty
            && trimmedName.count <= Self.maximumNameLength
            && !trimmedName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !trimmedFontName.isEmpty
            && trimmedFontName.count <= Self.maximumFontNameLength
            && fontSize.isFinite
            && (Self.minimumFontSize...Self.maximumFontSize).contains(fontSize)
            && ([background, foreground, cursor, selection] + ansiColors).allSatisfy(\.isValid)
    }

    var resolvedAppearance: TerminalThemeAppearance {
        if let preferredAppearance, preferredAppearance != .automatic {
            return preferredAppearance
        }
        let luminance = (0.2126 * background.red)
            + (0.7152 * background.green)
            + (0.0722 * background.blue)
        return luminance < 0.5 ? .dark : .light
    }

    /// Terminal coverage is controlled exclusively by the opacity setting.
    /// Theme background alpha is retained for backward-compatible decoding but
    /// is never multiplied into the live canvas.
    var canvasBackgroundColor: CodableColor {
        CodableColor(
            sRGBRed: background.red,
            green: background.green,
            blue: background.blue,
            alpha: 1
        )
    }

    var swiftTermTheme: SwiftTermTheme {
        SwiftTermTheme(
            fontSize: max(Self.minimumFontSize, fontSize),
            foreground: (foreground.red, foreground.green, foreground.blue),
            background: (background.red, background.green, background.blue, 0),
            cursor: (cursor.red, cursor.green, cursor.blue),
            fontName: fontName,
            selection: (selection.red, selection.green, selection.blue, selection.alpha),
            ansiColors: ansiColors.map {
                SwiftTermThemeColor(red: $0.red, green: $0.green, blue: $0.blue)
            }
        )
    }

    func reidentified(
        id: UUID = UUID(),
        name: String? = nil
    ) -> TerminalTheme {
        TerminalTheme(
            id: id,
            name: name ?? self.name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            selection: selection,
            black: black,
            red: red,
            green: green,
            yellow: yellow,
            blue: blue,
            magenta: magenta,
            cyan: cyan,
            white: white,
            brightBlack: brightBlack,
            brightRed: brightRed,
            brightGreen: brightGreen,
            brightYellow: brightYellow,
            brightBlue: brightBlue,
            brightMagenta: brightMagenta,
            brightCyan: brightCyan,
            brightWhite: brightWhite,
            fontName: fontName,
            fontSize: fontSize,
            preferredAppearance: preferredAppearance
        )
    }

    static let appleClearDarkForeground = CodableColor(
        sRGBRed: 0.901596844196,
        green: 0.901596844196,
        blue: 0.901596844196
    )
    static let appleClearDarkSelection = CodableColor(
        sRGBRed: 0.200930923223,
        green: 0.304736882448,
        blue: 0.370029002428
    )
    static let appleClearDarkANSIColors = [
        CodableColor(sRGBRed: 0.208221729000, green: 0.258872947300, blue: 0.296137570100),
        CodableColor(sRGBRed: 0.705090082900, green: 0.335715730100, blue: 0.281149064300),
        CodableColor(sRGBRed: 0.424156630500, green: 0.667281834600, blue: 0.441522716500),
        CodableColor(sRGBRed: 0.768627451000, green: 0.674509803900, blue: 0.384313725500),
        CodableColor(sRGBRed: 0.427450980400, green: 0.588235294100, blue: 0.705882352900),
        CodableColor(sRGBRed: 0.741176470600, green: 0.482352941200, blue: 0.803921568600),
        CodableColor(sRGBRed: 0.484715120500, green: 0.795007090900, blue: 0.805706814000),
        CodableColor(sRGBRed: 0.868783575500, green: 0.899543531400, blue: 0.922173947700),
        CodableColor(sRGBRed: 0.276332894900, green: 0.362595777900, blue: 0.426060269100),
        CodableColor(sRGBRed: 0.876132015300, green: 0.424238529000, blue: 0.352688727000),
        CodableColor(sRGBRed: 0.474204848200, green: 0.743332020300, blue: 0.492389116600),
        CodableColor(sRGBRed: 0.898039215700, green: 0.784313725500, blue: 0.447058823500),
        CodableColor(sRGBRed: 0.403921568600, green: 0.709803921600, blue: 0.929411764700),
        CodableColor(sRGBRed: 0.827450980400, green: 0.537254902000, blue: 0.898039215700),
        CodableColor(sRGBRed: 0.517774366200, green: 0.867731615800, blue: 0.879799107100),
        CodableColor(sRGBRed: 0.899579140100, green: 0.935473975100, blue: 0.961882174700),
    ]

    /// Applies the colors shipped in macOS 27 Terminal's Clear Dark profile
    /// and keeps its dark-canvas contrast contract intact.
    /// The profile does not override its cursor, so it follows the foreground.
    /// Window background, identity, name, and font choices remain untouched.
    mutating func applyAppleClearDarkColors() {
        preferredAppearance = .dark
        foreground = Self.appleClearDarkForeground
        cursor = Self.appleClearDarkForeground
        selection = Self.appleClearDarkSelection

        let colors = Self.appleClearDarkANSIColors
        black = colors[0]
        red = colors[1]
        green = colors[2]
        yellow = colors[3]
        blue = colors[4]
        magenta = colors[5]
        cyan = colors[6]
        white = colors[7]
        brightBlack = colors[8]
        brightRed = colors[9]
        brightGreen = colors[10]
        brightYellow = colors[11]
        brightBlue = colors[12]
        brightMagenta = colors[13]
        brightCyan = colors[14]
        brightWhite = colors[15]
    }

    /// The original Glass Terminal defaults were built from unresolved SwiftUI
    /// named colors. On macOS those values encoded as black, except white.
    /// Match every affected color so a customized theme is never rewritten.
    var hasCorruptedLegacyGlassTerminalColors: Bool {
        let opaqueBlack = CodableColor(sRGBRed: 0, green: 0, blue: 0)
        let opaqueWhite = CodableColor(sRGBRed: 1, green: 1, blue: 1)
        let corruptedANSIColors = [
            opaqueBlack, opaqueBlack, opaqueBlack, opaqueBlack,
            opaqueBlack, opaqueBlack, opaqueBlack, opaqueWhite,
            opaqueBlack, opaqueBlack, opaqueBlack, opaqueBlack,
            opaqueBlack, opaqueBlack, opaqueBlack, opaqueWhite,
        ]

        return name == "Glass Terminal"
            && foreground == opaqueWhite
            && cursor == opaqueBlack
            && selection == opaqueBlack
            && ansiColors == corruptedANSIColors
    }
    
    static let `default` = TerminalTheme(
        id: defaultID,
        name: "Glass Terminal",
        background: CodableColor(sRGBRed: 0, green: 0, blue: 0, alpha: 0.3),
        foreground: appleClearDarkForeground,
        cursor: appleClearDarkForeground,
        selection: appleClearDarkSelection,
        black: appleClearDarkANSIColors[0],
        red: appleClearDarkANSIColors[1],
        green: appleClearDarkANSIColors[2],
        yellow: appleClearDarkANSIColors[3],
        blue: appleClearDarkANSIColors[4],
        magenta: appleClearDarkANSIColors[5],
        cyan: appleClearDarkANSIColors[6],
        white: appleClearDarkANSIColors[7],
        brightBlack: appleClearDarkANSIColors[8],
        brightRed: appleClearDarkANSIColors[9],
        brightGreen: appleClearDarkANSIColors[10],
        brightYellow: appleClearDarkANSIColors[11],
        brightBlue: appleClearDarkANSIColors[12],
        brightMagenta: appleClearDarkANSIColors[13],
        brightCyan: appleClearDarkANSIColors[14],
        brightWhite: appleClearDarkANSIColors[15],
        fontName: "SF Mono",
        fontSize: 14,
        preferredAppearance: .dark
    )
}

enum TerminalThemeOrigin: String, Codable, Equatable, Sendable {
    case builtIn
    case custom
    case appleTerminal
}

struct TerminalThemeRecord: Identifiable, Codable, Equatable {
    var theme: TerminalTheme
    var origin: TerminalThemeOrigin
    var modifiedAt: Date
    var deletedAt: Date?

    var id: UUID { theme.id }
    var isBuiltIn: Bool { origin == .builtIn }
    var isDeleted: Bool { deletedAt != nil }

    var changeDate: Date {
        max(modifiedAt, deletedAt ?? .distantPast)
    }
}

struct TerminalThemeLibrary: Codable, Equatable {
    static let currentSchemaVersion = 1
    nonisolated static let maximumThemeCount = 64
    static let maximumRecordCount = 128

    var schemaVersion: Int
    var records: [TerminalThemeRecord]
    var selectedThemeID: UUID
    var selectionModifiedAt: Date

    init(
        records: [TerminalThemeRecord],
        selectedThemeID: UUID,
        selectionModifiedAt: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.records = records
        self.selectedThemeID = selectedThemeID
        self.selectionModifiedAt = selectionModifiedAt
        canonicalize()
    }

    static func initial(
        theme: TerminalTheme = .default,
        at timestamp: Date = Date()
    ) -> TerminalThemeLibrary {
        TerminalThemeLibrary(
            records: [
                TerminalThemeRecord(
                    theme: theme,
                    origin: .builtIn,
                    modifiedAt: timestamp,
                    deletedAt: nil
                )
            ],
            selectedThemeID: theme.id,
            selectionModifiedAt: timestamp
        )
    }

    var activeRecords: [TerminalThemeRecord] {
        records
            .filter { !$0.isDeleted }
            .sorted {
                if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
                let comparison = $0.theme.name.localizedStandardCompare($1.theme.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var selectedTheme: TerminalTheme? {
        records.first { $0.id == selectedThemeID && !$0.isDeleted }?.theme
    }

    mutating func select(_ id: UUID, at date: Date = Date()) -> Bool {
        guard records.contains(where: { $0.id == id && !$0.isDeleted }) else { return false }
        selectedThemeID = id
        selectionModifiedAt = date
        return true
    }

    mutating func upsert(
        _ theme: TerminalTheme,
        origin: TerminalThemeOrigin? = nil,
        at date: Date = Date()
    ) {
        if let index = records.firstIndex(where: { $0.id == theme.id }) {
            records[index].theme = theme
            records[index].modifiedAt = date
            records[index].deletedAt = nil
            if let origin { records[index].origin = origin }
        } else {
            guard activeRecords.count < Self.maximumThemeCount,
                  records.count < Self.maximumRecordCount else { return }
            records.append(
                TerminalThemeRecord(
                    theme: theme,
                    origin: origin ?? .custom,
                    modifiedAt: date,
                    deletedAt: nil
                )
            )
        }
    }

    mutating func delete(_ id: UUID, at date: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id && !$0.isDeleted }),
              !records[index].isBuiltIn,
              activeRecords.count > 1 else {
            return false
        }
        records[index].deletedAt = date
        records[index].modifiedAt = date
        if selectedThemeID == id, let replacement = activeRecords.first {
            selectedThemeID = replacement.id
            selectionModifiedAt = date
        }
        return true
    }

    mutating func merge(_ incoming: TerminalThemeLibrary) {
        guard incoming.schemaVersion == Self.currentSchemaVersion else { return }
        var merged: [UUID: TerminalThemeRecord] = [:]
        for record in records {
            guard let existing = merged[record.id] else {
                merged[record.id] = record
                continue
            }
            if record.changeDate > existing.changeDate
                || (record.changeDate == existing.changeDate
                    && Self.stableRecordKey(record) > Self.stableRecordKey(existing)) {
                merged[record.id] = record
            }
        }
        for record in incoming.records {
            guard let existing = merged[record.id] else {
                merged[record.id] = record
                continue
            }
            if record.changeDate > existing.changeDate
                || (record.changeDate == existing.changeDate
                    && Self.stableRecordKey(record) > Self.stableRecordKey(existing)) {
                merged[record.id] = record
            }
        }
        records = Array(merged.values)
        if incoming.selectionModifiedAt > selectionModifiedAt
            || (incoming.selectionModifiedAt == selectionModifiedAt
                && incoming.selectedThemeID.uuidString > selectedThemeID.uuidString) {
            selectedThemeID = incoming.selectedThemeID
            selectionModifiedAt = incoming.selectionModifiedAt
        }
        canonicalize()
    }

    mutating func canonicalize() {
        schemaVersion = Self.currentSchemaVersion
        let builtInRecords = records.filter { $0.isBuiltIn }
        if !builtInRecords.isEmpty {
            let selectedWasBuiltIn = builtInRecords.contains { $0.id == selectedThemeID }
            let winner = builtInRecords.max {
                if $0.changeDate != $1.changeDate { return $0.changeDate < $1.changeDate }
                return Self.stableRecordKey($0) < Self.stableRecordKey($1)
            }!
            var canonicalBuiltIn = winner
            canonicalBuiltIn.theme = winner.theme.reidentified(id: TerminalTheme.defaultID)
            canonicalBuiltIn.deletedAt = nil
            records.removeAll { $0.isBuiltIn }
            records.append(canonicalBuiltIn)
            if selectedWasBuiltIn { selectedThemeID = TerminalTheme.defaultID }
        }
        var seen = Set<UUID>()
        records = records.filter { seen.insert($0.id).inserted }
        if records.filter({ !$0.isDeleted }).isEmpty {
            let fallback = TerminalTheme.default
            records.append(
                TerminalThemeRecord(
                    theme: fallback,
                    origin: .builtIn,
                    modifiedAt: Date(),
                    deletedAt: nil
                )
            )
            selectedThemeID = fallback.id
            selectionModifiedAt = Date()
        } else if selectedTheme == nil, let first = activeRecords.first {
            selectedThemeID = first.id
            selectionModifiedAt = max(selectionModifiedAt, first.modifiedAt)
        }
    }

    private static func stableRecordKey(_ record: TerminalThemeRecord) -> String {
        let theme = record.theme
        let colors = ([theme.background, theme.foreground, theme.cursor, theme.selection]
            + theme.ansiColors)
            .map { "\($0.red),\($0.green),\($0.blue),\($0.alpha)" }
            .joined(separator: "|")
        return [
            record.origin.rawValue,
            record.deletedAt?.timeIntervalSinceReferenceDate.description ?? "",
            theme.id.uuidString,
            theme.name,
            theme.fontName,
            theme.fontSize.description,
            theme.preferredAppearance?.rawValue ?? "",
            colors,
        ].joined(separator: "|")
    }
}

// Helper for encoding/decoding Color
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    init(sRGBRed red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(
            sRGBRed: Double(resolved.red),
            green: Double(resolved.green),
            blue: Double(resolved.blue),
            alpha: Double(resolved.opacity)
        )
    }
}
// MARK: - SSH Connection

/// UI metadata and terminal geometry do not change an authenticated transport.
/// Endpoint, account, route and trust-policy changes do, including any hop.
struct TerminalWorkgroup: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorTag: ServerColorTag
    var sessionIDs: [UUID]
    var selectedSessionID: UUID?
}

/// A device-local replacement, deliberately excluded from the shared recipe.
struct WorkgroupSSHSubstitution: Codable, Equatable {
    var source: LayoutPreset.SessionIntent
    var serverID: UUID
    var directory: String
    var command: String

    var intent: LayoutPreset.SessionIntent {
        let path = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotedPath = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // One line: startup commands travel through `TerminalStartupCommandTicket`, which rejects
        // newlines because the PTY receives them as separate commands. A single-line group
        // command keeps the script's exit status without a subshell.
        let group: String
        if script.isEmpty {
            group = ""
        } else {
            let body = script.hasSuffix(";") || script.hasSuffix("&") ? script : script + ";"
            group = " && { \(body) }"
        }
        let startup = path.isEmpty ? script : "cd -- \(quotedPath)" + group
        return .init(serverID: serverID, label: source.label, startupCommand: startup)
    }
}

struct LayoutPreset: Identifiable, Codable, Hashable {
    enum OpeningView: String, Codable, CaseIterable, Sendable {
        case tabs, grid, carousel
        var title: String { rawValue.capitalized }
    }
    static let currentSchemaVersion = 4
    nonisolated static let maximumNameLength = 80
    static let maximumSessionCount = 32

    struct SessionIntent: Codable, Hashable {
        static let currentSchemaVersion = 3
        static let maximumLabelLength = 80

        enum Kind: String, Codable, Hashable, Sendable {
            case local
            case ssh
        }

        enum Restoration: Hashable, Codable {
            case freshAuthorizedSession
            case unsupported(String)

            private var rawValue: String {
                switch self {
                case .freshAuthorizedSession:
                    return "freshAuthorizedSession"
                case .unsupported(let value):
                    return value
                }
            }

            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer().decode(String.self)
                self = value == "freshAuthorizedSession"
                    ? .freshAuthorizedSession
                    : .unsupported(value)
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }

        var schemaVersion: Int
        var kind: Kind
        var serverID: UUID?
        var restoration: Restoration
        var label: String?
        var startupCommand: String?
        var localShell: String? = nil
        var localDirectory: String? = nil
        /// W4b (2026-10-08): the tmux session this terminal lives in — on its SSH host, or on the
        /// Mac for a local one — so opening the workgroup attaches to it again rather than starting
        /// a new one. It travels with the workgroup (D51): the session lives on the host, not on
        /// the device. Nil until a terminal opened from the workgroup claims one.
        var tmuxSession: String? = nil

        init(
            schemaVersion: Int = SessionIntent.currentSchemaVersion,
            serverID: UUID,
            restoration: Restoration = .freshAuthorizedSession,
            label: String? = nil,
            startupCommand: String? = nil,
            tmuxSession: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.kind = .ssh
            self.serverID = serverID
            self.restoration = restoration
            self.label = Self.normalizedLabel(label)
            self.startupCommand = Self.normalizedCommand(startupCommand)
            self.tmuxSession = Self.normalizedTmuxSession(tmuxSession)
        }

        init(
            schemaVersion: Int = SessionIntent.currentSchemaVersion,
            kind: Kind,
            serverID: UUID? = nil,
            restoration: Restoration = .freshAuthorizedSession,
            label: String? = nil,
            startupCommand: String? = nil,
            localShell: String? = nil,
            localDirectory: String? = nil,
            tmuxSession: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.kind = kind
            self.localShell = Self.normalizedLocalPath(localShell)
            self.localDirectory = Self.normalizedLocalPath(localDirectory)
            self.serverID = serverID
            self.restoration = restoration
            self.label = Self.normalizedLabel(label)
            self.startupCommand = Self.normalizedCommand(startupCommand)
            self.tmuxSession = Self.normalizedTmuxSession(tmuxSession)
        }

        var isSupported: Bool {
            schemaVersion == Self.currentSchemaVersion
                && restoration == .freshAuthorizedSession
                && ((kind == .local && serverID == nil) || (kind == .ssh && serverID != nil))
                && label == Self.normalizedLabel(label)
                && startupCommand == Self.normalizedCommand(startupCommand)
                && tmuxSession == Self.normalizedTmuxSession(tmuxSession)
                && [localShell, localDirectory].allSatisfy { $0 == nil || (!$0!.isEmpty && !$0!.utf8.contains(0)) }
                && (kind == .local || (localShell == nil && localDirectory == nil))
        }

        /// The same terminal, whatever tmux session it was given: a name a pane claimed and wrote
        /// back does not make it a different pane (a device's SSH substitution, an edit's draft).
        func sameTerminal(as other: Self) -> Bool {
            var mine = self, theirs = other
            mine.tmuxSession = nil
            theirs.tmuxSession = nil
            return mine == theirs
        }

        var needsMigration: Bool { schemaVersion < Self.currentSchemaVersion }

        func migratedToCurrentSchema() -> Self {
            guard needsMigration else { return self }
            var migrated = self
            migrated.schemaVersion = Self.currentSchemaVersion
            migrated.label = Self.normalizedLabel(label)
            migrated.startupCommand = Self.normalizedCommand(startupCommand)
            return migrated
        }

        private static func normalizedLabel(_ value: String?) -> String? {
            guard let value else { return nil }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  !normalized.utf8.contains(0),
                  normalized.count <= maximumLabelLength else { return nil }
            return normalized
        }

        private static func normalizedCommand(_ value: String?) -> String? {
            TerminalStartupCommandTicket(command: value)?.command
        }

        private static func normalizedLocalPath(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }

        /// A name tmux would take, else none — as an unreadable label or command is read as none:
        /// the terminal then claims a new session, and the workgroup still opens.
        private static func normalizedTmuxSession(_ value: String?) -> String? {
            value.flatMap { TerminalTmux.isValidSessionName($0) ? $0 : nil }
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case kind
            case serverID
            case restoration
            case label
            case startupCommand
            case localShell, localDirectory
            case tmuxSession
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .ssh
            localShell = Self.normalizedLocalPath(try container.decodeIfPresent(String.self, forKey: .localShell))
            localDirectory = Self.normalizedLocalPath(try container.decodeIfPresent(String.self, forKey: .localDirectory))
            serverID = try container.decodeIfPresent(UUID.self, forKey: .serverID)
            restoration = try container.decodeIfPresent(Restoration.self, forKey: .restoration)
                ?? .freshAuthorizedSession
            label = Self.normalizedLabel(try container.decodeIfPresent(String.self, forKey: .label))
            startupCommand = Self.normalizedCommand(
                try container.decodeIfPresent(String.self, forKey: .startupCommand)
            )
            // Optional and without a schema change, so a build from before W4b still reads the
            // workgroup; it drops the name only if it saves the workgroup again.
            tmuxSession = Self.normalizedTmuxSession(try container.decodeIfPresent(String.self, forKey: .tmuxSession))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(serverID, forKey: .serverID)
            try container.encode(restoration, forKey: .restoration)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(startupCommand, forKey: .startupCommand)
            try container.encodeIfPresent(localShell, forKey: .localShell)
            try container.encodeIfPresent(localDirectory, forKey: .localDirectory)
            try container.encodeIfPresent(tmuxSession, forKey: .tmuxSession)
        }
    }

    struct WorkspaceLayout: Codable, Hashable {
        enum Axis: String, Codable, Hashable { case horizontal, vertical }
        indirect enum Node: Codable, Hashable {
            case session(Int)
            case split(axis: Axis, fraction: Double, first: Node, second: Node)

            private enum CodingKeys: String, CodingKey { case session, split }
            private enum SessionKeys: String, CodingKey { case index = "_0" }
            private enum SplitKeys: String, CodingKey { case axis, fraction, first, second }

            init(from decoder: Decoder) throws {
                // Check before descending, rather than recursively decoding an
                // arbitrarily deep tree and validating only afterward.
                let depth = 1 + decoder.codingPath.filter {
                    $0.stringValue == "first" || $0.stringValue == "second"
                }.count
                guard depth <= 12 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                        debugDescription: "A workspace split layout may be at most 12 levels deep."))
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                guard container.allKeys.count == 1 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                        debugDescription: "A workspace node requires exactly one variant."))
                }
                if container.contains(.session) {
                    let value = try container.nestedContainer(keyedBy: SessionKeys.self, forKey: .session)
                    self = .session(try value.decode(Int.self, forKey: .index))
                } else {
                    let value = try container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
                    let fraction = try value.decode(Double.self, forKey: .fraction)
                    guard fraction.isFinite, (0.1...0.9).contains(fraction) else {
                        throw DecodingError.dataCorruptedError(forKey: .fraction, in: value,
                            debugDescription: "Invalid workspace split position.")
                    }
                    self = .split(axis: try value.decode(Axis.self, forKey: .axis), fraction: fraction,
                                  first: try value.decode(Node.self, forKey: .first),
                                  second: try value.decode(Node.self, forKey: .second))
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .session(let index):
                    var value = container.nestedContainer(keyedBy: SessionKeys.self, forKey: .session)
                    try value.encode(index, forKey: .index)
                case let .split(axis, fraction, first, second):
                    var value = container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
                    try value.encode(axis, forKey: .axis)
                    try value.encode(fraction, forKey: .fraction)
                    try value.encode(first, forKey: .first)
                    try value.encode(second, forKey: .second)
                }
            }

            fileprivate func indices(depth: Int = 1) -> [Int]? {
                guard depth <= 12 else { return nil }
                switch self {
                case .session(let index): return [index]
                case let .split(_, fraction, first, second):
                    guard fraction.isFinite, (0.1...0.9).contains(fraction),
                          let left = first.indices(depth: depth + 1),
                          let right = second.indices(depth: depth + 1) else { return nil }
                    return left + right
                }
            }
        }
        struct Tab: Codable, Hashable {
            var label: String?
            var root: Node
            var focusedSessionIndex: Int
        }
        var tabs: [Tab]
        var selectedTabIndex: Int

        func isValid(sessionCount: Int) -> Bool {
            guard (1...LayoutPreset.maximumSessionCount).contains(sessionCount),
                  !tabs.isEmpty, tabs.count <= sessionCount,
                  tabs.indices.contains(selectedTabIndex) else { return false }
            var all: [Int] = []
            for tab in tabs {
                guard let indices = tab.root.indices(), indices.contains(tab.focusedSessionIndex) else { return false }
                all += indices
            }
            return all.sorted() == Array(0..<sessionCount)
        }
    }

    let id: UUID
    var name: String
    var colorTag: ServerColorTag
    private(set) var schemaVersion: Int
    var sessionIntents: [SessionIntent]
    var workspaceLayout: WorkspaceLayout? = nil
    var openingView: OpeningView = .tabs
    var autoFocusOnActivity = false
    /// Nil lets the grid choose its layout; otherwise a preferred width in points.
    var gridCardWidth: Double? = nil
    let createdAt: Date
    var lastUsed: Date?
    /// When it was last saved, here or on another device: its sync clock (2026-10-08). Nil for a
    /// workgroup saved before workgroups synced, which counts from `createdAt`.
    var modifiedAt: Date? = nil

    init(
        id: UUID = UUID(),
        name: String,
        colorTag: ServerColorTag = .blue,
        serverIDs: [UUID],
        createdAt: Date = Date(),
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.colorTag = colorTag
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionIntents = serverIDs.prefix(Self.maximumSessionCount).map {
            SessionIntent(serverID: $0)
        }
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }

    init(
        id: UUID = UUID(),
        name: String,
        colorTag: ServerColorTag = .blue,
        sessionIntents: [SessionIntent],
        workspaceLayout: WorkspaceLayout? = nil,
        createdAt: Date = Date(),
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.colorTag = colorTag
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionIntents = Array(sessionIntents.prefix(Self.maximumSessionCount))
        self.workspaceLayout = workspaceLayout
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }

    /// Compatibility view used by callers that only need endpoint identities.
    /// Repeated IDs are intentional: each entry represents a separate session.
    var serverIDs: [UUID] {
        sessionIntents.compactMap(\.serverID)
    }

    /// W4b: the tmux sessions saved workgroups hold on one machine — an SSH server, or this Mac
    /// when `serverID` is nil. A new terminal there never takes one, though nothing may be
    /// running it: the workgroup would attach to that terminal's work next time it opens.
    static func tmuxSessionsHeld(in presets: [LayoutPreset], serverID: UUID?) -> Set<String> {
        Set(presets.flatMap(\.sessionIntents).filter { intent in
            serverID == nil ? intent.kind == .local : (intent.kind == .ssh && intent.serverID == serverID)
        }.compactMap(\.tmuxSession))
    }

    var needsMigration: Bool {
        schemaVersion < Self.currentSchemaVersion
            || sessionIntents.contains(where: \.needsMigration)
    }

    var isValidForPersistence: Bool {
        schemaVersion == Self.currentSchemaVersion
            && name == Self.normalizedName(name)
            && !sessionIntents.isEmpty
            && sessionIntents.count <= Self.maximumSessionCount
            && sessionIntents.allSatisfy(\.isSupported)
            && (workspaceLayout?.isValid(sessionCount: sessionIntents.count) ?? true)
    }

    func migratedToCurrentSchema() -> LayoutPreset {
        guard needsMigration else { return self }
        var migrated = self
        migrated.schemaVersion = Self.currentSchemaVersion
        migrated.name = Self.normalizedName(name)
        migrated.sessionIntents = Array(
            sessionIntents.map { $0.migratedToCurrentSchema() }
                .prefix(Self.maximumSessionCount)
        )
        return migrated
    }

    private static func normalizedName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Workgroup" }
        return String(normalized.prefix(maximumNameLength))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorTag
        case schemaVersion
        case sessionIntents
        case workspaceLayout
        case openingView
        case autoFocusOnActivity
        case gridCardWidth
        case serverIDs
        case createdAt
        case lastUsed
        case modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = Self.normalizedName(try container.decode(String.self, forKey: .name))
        colorTag = try container.decodeIfPresent(ServerColorTag.self, forKey: .colorTag) ?? .blue
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        workspaceLayout = try container.decodeIfPresent(WorkspaceLayout.self, forKey: .workspaceLayout)
        openingView = try container.decodeIfPresent(OpeningView.self, forKey: .openingView) ?? .tabs
        autoFocusOnActivity = try container.decodeIfPresent(Bool.self, forKey: .autoFocusOnActivity) ?? false
        gridCardWidth = try container.decodeIfPresent(Double.self, forKey: .gridCardWidth).map { min(720, max(220, $0)) }

        if let decodedIntents = try container.decodeIfPresent([SessionIntent].self, forKey: .sessionIntents) {
            sessionIntents = decodedIntents
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion
        } else {
            let legacyServerIDs = try container.decodeIfPresent([UUID].self, forKey: .serverIDs) ?? []
            sessionIntents = legacyServerIDs.map { SessionIntent(serverID: $0) }
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorTag, forKey: .colorTag)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionIntents, forKey: .sessionIntents)
        try container.encodeIfPresent(workspaceLayout, forKey: .workspaceLayout)
        try container.encode(openingView, forKey: .openingView)
        try container.encode(autoFocusOnActivity, forKey: .autoFocusOnActivity)
        try container.encodeIfPresent(gridCardWidth, forKey: .gridCardWidth)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsed, forKey: .lastUsed)
        try container.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
    }
}
