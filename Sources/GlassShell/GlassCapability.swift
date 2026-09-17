import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// How a capability's `open` ended, reported back to the shell once, at the first terminal
/// state. Only `.connected` counts as a connection: the shell stamps "last connected" on it and
/// on nothing else, so a failed or cancelled attempt never shows as a recent connection.
public enum GlassCapabilityOutcome: Sendable, Equatable {
    /// A live session was established.
    case connected
    /// The attempt ended with an error the capability has already shown the user.
    case failed(String)
    /// The user backed out (cancelled a prompt, closed a setup form) or nothing was attempted.
    case dismissed
}

/// What the shell knows about the host while a capability sets a service up or connects. The
/// host's address is the one thing every service shares: the shell collects it on the host, before
/// any setup form opens, so a capability only ever reads it. Capabilities never write the catalog.
public struct GlassCapabilityHostAccess: Sendable {
    /// The host's address (DNS name or IP). Nil only for a record another family app wrote
    /// without one; a service created in this app always has a host with an address.
    public let address: String?

    /// Supplied by the shell when this host has an SSH service whose capability can open a
    /// forward. Nil means no forward is possible and the caller must connect directly or say so.
    private let openForward: (@MainActor @Sendable (String, Int) async throws -> any GlassHostPortForward)?

    /// Supplied by the shell alongside `openForward`, from the same capability.
    private let resolveTrust: (@MainActor @Sendable () async -> GlassHostTrustOutcome)?

    public init(address: String?,
                openForward: (@MainActor @Sendable (String, Int) async throws -> any GlassHostPortForward)? = nil,
                resolveTrust: (@MainActor @Sendable () async -> GlassHostTrustOutcome)? = nil) {
        self.address = address
        self.openForward = openForward
        self.resolveTrust = resolveTrust
    }

    /// Whether `forwardPort` can succeed at all: the host has an SSH service and a registered
    /// capability owns it. Ask before offering the user a "connect through SSH" choice.
    public var canForwardPorts: Bool { openForward != nil }

    /// Borrows the host's own SSH service to open a local port that reaches `remoteHost:port`
    /// **from the host's machine** — the D7 replacement for a per-service SSH configuration.
    /// The caller closes the returned forward when it is finished with it.
    ///
    /// `remoteHost` defaults to loopback because the common case is a service listening only on
    /// the machine itself. The caller never learns which capability served the request and never
    /// imports it: the shell brokers this.
    public func forwardPort(toHost remoteHost: String = "127.0.0.1",
                            port: Int) async throws -> any GlassHostPortForward {
        guard let openForward else { throw GlassPortForwardError.unavailable }
        guard (1...65_535).contains(port) else { throw GlassPortForwardError.invalidPort(port) }
        return try await openForward(remoteHost, port)
    }

    /// Settles this machine's SSH host-key trust now, prompting if it is not yet pinned (D14).
    /// Safe to call when the key is already trusted: it returns `.trusted` without prompting.
    ///
    /// Meant for the moment a service is *set up* to tunnel, so that connecting later simply
    /// works. It resolves and reports; it never blocks the caller's own save, and `.declined`
    /// is a legitimate answer rather than a failure.
    public func resolveHostTrust() async -> GlassHostTrustOutcome {
        guard let resolveTrust else { return .unavailable }
        return await resolveTrust()
    }
}

/// How a request to settle a machine's SSH host-key trust ended. Three cases rather than a
/// boolean, because the setup sheet must say something different about each — and because a
/// **changed** host key reaching the user as the same `false` as "there was nobody to ask"
/// would be precisely the swallowed error the project rules forbid.
public enum GlassHostTrustOutcome: Sendable, Equatable {
    /// Already pinned, or the user reviewed the fingerprint and accepted it just now.
    case trusted
    /// The user declined. Expected, not an error: do not present it as a failure.
    case declined
    /// Nothing could be asked — no SSH service, no capability owns `.ssh`, or no prompt could
    /// be shown (the user has host-key verification set to strict).
    case unavailable
}

/// A local TCP port that proxies to a service reachable from the host's machine. Opened by the
/// capability that owns the host's SSH service, used by another capability that never imports it.
public protocol GlassHostPortForward: AnyObject, Sendable {
    /// The port on this device to connect to. Always a real bound port, never a request.
    var localPort: Int { get }
    /// Tears the forward down. Calling it more than once is harmless.
    func close() async
}

public enum GlassPortForwardError: Error, LocalizedError {
    /// The host has no SSH service, no capability owns `.ssh`, or the host is this device.
    case unavailable
    case invalidPort(Int)
    /// The machine's SSH host key is not trusted yet. A background tunnel must not prompt for a
    /// fingerprint and must never trust one silently, so the user is sent to the Terminal service.
    case hostNotTrusted(name: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "This machine has no Terminal service to tunnel through. Add one, or connect directly."
        case .invalidPort(let port):
            "\(port) is not a usable TCP port."
        case .hostNotTrusted(let name):
            "The SSH host key for \(name) has not been trusted on this device. Connect its Terminal service once to review the fingerprint, then try again."
        }
    }
}

/// One problem that blocks saving a service draft: which field, and what to tell the user.
public struct GlassSetupIssue: Identifiable, Hashable, Sendable {
    /// A stable key for the field (also the suffix of its accessibility identifier).
    public let field: String
    public let message: String
    public var id: String { field }

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

/// A service being set up or edited in the shell's host sheet. The capability owns the draft
/// (its fields, validation and persistence); the shell owns the sheet, the host's identity and
/// the order of operations. A draft never carries the host's address: the shell passes it in at
/// commit time, because the address is defined once, on the host.
@MainActor
public protocol GlassServiceDraft: AnyObject {
    var kind: HostServiceKind { get }
    /// The name the shell records on the service link. The capability derives a sensible
    /// default from the host so the user never has to type one.
    func serviceDisplayName(hostName: String) -> String
    /// The fields a service cannot be created without, as rows of a grouped `Form` section.
    func requiredFields() -> AnyView
    /// Everything optional, shown under the sheet's "Advanced" disclosure.
    func advancedFields() -> AnyView
    /// Problems that block Save. Called with the host's address so a draft can validate what
    /// it will commit; empty means the draft can be committed.
    func validate(address: String) -> [GlassSetupIssue]
    /// Reveal every validation message and move focus to the first invalid field.
    func focusFirstIssue(_ issues: [GlassSetupIssue])
    /// Create or update the service's configuration and credentials, keyed by `endpointID`,
    /// which is the link the shell records on the host.
    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws
    /// Undo a `commit` that created a new service, when a later step of the same save failed.
    func rollback(endpointID: EndpointID) async
}

/// A capability owns one service kind. The shell routes `connect` through it;
/// the capability declares its own scenes statically in the app target.
/// What authenticates one service.
///
/// The distinction that matters is **shared or not**. A password belongs to the service that uses
/// it and to nothing else, so deleting that service ends the story. A key is shared: the same key
/// can authenticate a terminal on `oscar` and another on `juliet`, which is why deleting one of
/// them must leave the key alone, and why a key manager has to be able to say who is using it.
public enum GlassServiceCredential: Sendable, Equatable {
    /// Something belonging to this service alone — a password. Nothing else references it.
    case ownedByService
    /// A shared key, and whether that key can leave this device.
    case sharedKey(id: UUID, deviceBound: Bool)
    /// This build cannot read the service's configuration, so it cannot say what authenticates it.
    ///
    /// **Counted separately, never folded into "uses nothing".** A record written by a newer build
    /// would otherwise make a key that is genuinely in use look unused — and then someone deletes
    /// it. A zero only ever proves where you looked.
    case unreadable

    /// Whether this service can appear on other devices.
    public var isDeviceBound: Bool {
        if case .sharedKey(_, let deviceBound) = self { return deviceBound }
        return false
    }
}

@MainActor
public protocol GlassCapability: AnyObject {
    var kind: HostServiceKind { get }
    var displayName: String { get }
    var symbolName: String { get }
    /// Open the service. `report` is called exactly once, on the main actor, when the attempt
    /// reaches a terminal state; it may run long after `open` returns (trust prompt, password).
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void)
    /// `open` with access to the host record. The shell calls this one; the default forwards to
    /// `open(service:host:report:)` for capabilities that never need the host's address.
    func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void)
    /// The host's address changed in the shell (or was set for the first time). A capability
    /// that stores an address per service updates every service of `host` it owns, so the user
    /// edits the machine's identity once. `address` is nil when it was cleared. Default: nothing.
    func hostAddressDidChange(host: HostProfile, address: String?)
    /// The address the capability already stores for `service`, if any — a record saved by the
    /// source app before hosts carried an address. The shell adopts it onto the host so the
    /// machine's identity is defined once, at the host. Default: nil.
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String?

    /// A draft for a new service of this kind, composed into the shell's host sheet. A service
    /// is created complete — configuration and credentials with it — so no capability may
    /// answer nil here: the shell shows a kind without a capability as a disabled tab instead.
    func makeSetupDraft() -> any GlassServiceDraft
    /// A draft loaded from an existing service, for the sheet's edit mode; nil when the
    /// capability holds nothing for it (the link is broken and the user is told so).
    func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)?
    /// A draft built from a record this capability parsed out of another tool's file, for the
    /// sheet's import flow. `configuration` is the capability's own encoding, so only the
    /// capability that produced it can read it. Nil when it cannot be decoded — the sheet then
    /// opens empty rather than refusing, because a machine the user can finish by hand is better
    /// than a dead end. Default: nil, for capabilities that import nothing.
    func setupDraft(importing configuration: Data) -> (any GlassServiceDraft)?
    /// What authenticates this service, as far as anything outside the capability needs to know.
    ///
    /// One question rather than two, because both answers come from the same lookup: whether the
    /// service can travel (D26 stage 3) and which shared credential it references (D28's "used by")
    /// are both *what is this service's credential*, and asking twice would walk the same path
    /// twice and let the two answers disagree.
    ///
    /// **Derived, never stored.** Asked again every time it matters. A stored flag would drift the
    /// moment a terminal switched from a hardware key to a password: it would either leak a
    /// connection that cannot work, or strand one that can. Default: `.ownedByService`.
    func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential

    /// The shell removed `service` from `host`: delete whatever the capability stored for it
    /// (configuration, credentials). Default: nothing.
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws

    /// Opens a local port reaching `remoteHost:port` **from `host`'s machine**, over this
    /// capability's own transport and this host's existing trust. Only the capability that owns
    /// `.ssh` implements it; the shell calls it on behalf of others so that, for example, the
    /// database capability can tunnel without importing the terminal. Default: throws
    /// `GlassPortForwardError.unavailable`.
    ///
    /// Isolated to the main actor like the rest of the protocol, so an implementation must do
    /// the network work by awaiting its own transport actor — never synchronously here.
    func openPortForward(host: HostProfile, toHost remoteHost: String,
                         port: Int) async throws -> any GlassHostPortForward

    /// Settles `host`'s SSH host-key trust, prompting if needed, using this capability's own
    /// prompt (D14). Only the capability that owns `.ssh` implements it; the shell calls it on
    /// behalf of others, so a database service can have its machine's fingerprint reviewed at
    /// setup time without importing the capability that owns the connection. Default:
    /// `.unavailable` — the same refusing default as `openPortForward`.
    func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome

    /// Settings pages the capability contributes to the one settings surface, appended after the
    /// shell's own pages. Default: none.
    var settingsPages: [GlassCapabilitySettingsPage] { get }
    /// Controls the capability adds to the library toolbar (e.g. a quick-connect). Default: none.
    func libraryToolbarItems() -> AnyView

    /// The catalog has been read from disk and is answering honestly.
    ///
    /// A capability that keeps an in-memory index of its own records — the terminal's saved-server
    /// list — builds it here rather than when the store is attached. The composition root attaches
    /// while the app is still being constructed, and at that moment every read answers "nothing",
    /// which is indistinguishable from an empty library. Called after every `load()`, so it must be
    /// idempotent. Default: nothing to do.
    func catalogDidLoad()

    /// Surfaces the capability contributes to the library's sidebar, beside Collections.
    ///
    /// For things that span the whole fleet rather than belonging to one machine — Workgroups,
    /// which is a saved layout of sessions across several hosts, and Network, which lists a
    /// Tailscale tailnet. glas.sh listed both as sidebar sections and switched its results and
    /// detail on the selected mode; the merge moved Workgroups to a window of its own, which is
    /// how it stopped reading as part of the library. Default: none.
    func libraryPanels() -> [GlassLibraryPanel]
    /// Actions shown beside a service's Connect in the host detail, asked only for the
    /// capability's own kind. `host` is the catalog record that owns the service. Default: none.
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView

    /// Peer rows the capability contributes to the host detail below its services: tools that a
    /// configured service makes available rather than services of their own. The terminal offers
    /// Files (SFTP) when the server supports it; Stage 5's editor joins here.
    func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool]

    /// Services this capability provides on the built-in local host (D8) with nothing to set up
    /// and nothing stored: the Mac's own shell is one. The endpoint ids **must be constants** —
    /// the shell writes no record for them, and the capability recognises them again in `open`.
    /// Returning services here for a platform that has none is the dishonest case to avoid: the
    /// Mac's local shell exists, an iPhone's does not. Default: none.
    func builtInLocalServices() -> [HostServiceLink]

    /// Whether the user may add a service of this kind to the local host through the setup sheet.
    /// Default: `true` — the user's answer to "which kinds belong on This Mac?" was "all of them",
    /// so a capability opts out rather than in. The terminal opts out: its local service is the
    /// built-in shell above, and a second way to make one would only be a worse one.
    var supportsLocalSetup: Bool { get }
}

/// A tool a service makes available: its own row in the host detail, with the service it rides.
public struct GlassServiceTool: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let subtitle: String?
    public let open: @MainActor @Sendable () -> Void

    public init(id: String, title: String, symbolName: String, subtitle: String? = nil,
                open: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.subtitle = subtitle
        self.open = open
    }
}

public extension GlassCapability {
    func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        open(service: service, host: host, report: report)
    }
    func hostAddressDidChange(host: HostProfile, address: String?) {}
    func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential { .ownedByService }
    func libraryPanels() -> [GlassLibraryPanel] { [] }
    func catalogDidLoad() {}
    func setupDraft(importing configuration: Data) -> (any GlassServiceDraft)? { nil }
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String? { nil }
    /// A capability that has not adopted the setup contract yet: the sheet shows why and Save
    /// refuses, so no half-made service can be created through it.
    func makeSetupDraft() -> any GlassServiceDraft { GlassUnavailableServiceDraft(kind: kind, capabilityName: displayName) }
    func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? { nil }
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws {}
    func openPortForward(host: HostProfile, toHost remoteHost: String,
                         port: Int) async throws -> any GlassHostPortForward {
        throw GlassPortForwardError.unavailable
    }
    func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome { .unavailable }
    var settingsPages: [GlassCapabilitySettingsPage] { [] }
    func libraryToolbarItems() -> AnyView { AnyView(EmptyView()) }
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView { AnyView(EmptyView()) }
    func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] { [] }
    func builtInLocalServices() -> [HostServiceLink] { [] }
    var supportsLocalSetup: Bool { true }
}

/// The draft of a capability that offers no setup. Honest, not a stub: it says so in the
/// sheet and blocks Save.
@MainActor
public final class GlassUnavailableServiceDraft: GlassServiceDraft {
    public let kind: HostServiceKind
    private let capabilityName: String

    public init(kind: HostServiceKind, capabilityName: String) {
        self.kind = kind
        self.capabilityName = capabilityName
    }

    public func serviceDisplayName(hostName: String) -> String { "\(capabilityName) on \(hostName)" }
    public func requiredFields() -> AnyView {
        AnyView(Text("\(capabilityName) cannot be set up from here yet.").foregroundStyle(.secondary))
    }
    public func advancedFields() -> AnyView { AnyView(EmptyView()) }
    public func validate(address: String) -> [GlassSetupIssue] {
        [GlassSetupIssue(field: "setup", message: "\(capabilityName) cannot be set up from here yet.")]
    }
    public func focusFirstIssue(_ issues: [GlassSetupIssue]) {}
    public func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        throw GlassShellError.invalidName
    }
    public func rollback(endpointID: EndpointID) async {}
}

/// One settings page owned by a capability. `id` must be stable and unique across capabilities;
/// it is the selection key and part of the page's accessibility identifier.
public struct GlassCapabilitySettingsPage: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let makeView: @MainActor () -> AnyView

    public init(id: String, title: String, systemImage: String, makeView: @escaping @MainActor () -> AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.makeView = makeView
    }
}

/// Presentation symbols for service kinds, used by the row accessory, the
/// picker and the placeholder. One place so no capability invents its own.
public enum GlassServicePresentation {
    /// Terminal and desktop are SF Symbols; the database is Heroicons' `circle-stack`, vendored
    /// in the kit (`GlassServiceIcon`). Draw these with `GlassServiceIcon`, not `Image(systemName:)`.
    public static func symbol(for kind: HostServiceKind) -> GlassServiceSymbol {
        switch kind {
        case .ssh: .system("terminal")
        case .database: .circleStack
        case .rdp: .system("display")
        }
    }

    public static func displayName(for kind: HostServiceKind) -> String {
        switch kind {
        case .ssh: "Terminal"
        case .database: "Database"
        case .rdp: "Desktop"
        }
    }
}

@MainActor @Observable
public final class GlassCapabilityRegistry {
    private var capabilities: [HostServiceKind: any GlassCapability] = [:]

    public init() {}

    public func register(_ capability: any GlassCapability) {
        capabilities[capability.kind] = capability
    }

    public func capability(for kind: HostServiceKind) -> (any GlassCapability)? {
        capabilities[kind]
    }

    public var registeredKinds: [HostServiceKind] {
        HostServiceKind.allCases.filter { capabilities[$0] != nil }
    }

    /// Registered capabilities in kind order, so contributed UI is stable across launches.
    public var registered: [any GlassCapability] {
        registeredKinds.compactMap { capabilities[$0] }
    }

    /// Every capability's settings pages, in kind order.
    public var settingsPages: [GlassCapabilitySettingsPage] {
        registered.flatMap(\.settingsPages)
    }

    /// Every capability's built-in local services (D8), in kind order, with any capability that
    /// returns a duplicate endpoint id ignored for the duplicate — a constant id belongs to one
    /// capability, and a host record refuses a repeated endpoint anyway.
    public var builtInLocalServices: [HostServiceLink] {
        var seen = Set<EndpointID>()
        return registered.flatMap { $0.builtInLocalServices() }
            .filter { seen.insert($0.endpointID).inserted }
    }

    /// The kinds the user may add to the local host through the setup sheet: registered, and not
    /// opted out. A kind with no capability in this build is absent here as it is anywhere else.
    public var localSetupKinds: [HostServiceKind] {
        registered.filter(\.supportsLocalSetup).map(\.kind)
    }

    /// The owning capability's detail actions for a service, or nothing if no capability owns
    /// its kind. Only that capability is asked.
    public func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] {
        capability(for: service.kind)?.serviceTools(service: service, host: host) ?? []
    }

    public func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView {
        capability(for: service.kind)?.serviceDetailActions(service: service, host: host) ?? AnyView(EmptyView())
    }
}
