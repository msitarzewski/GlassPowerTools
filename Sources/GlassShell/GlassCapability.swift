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

    public init(address: String?) {
        self.address = address
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
    /// The shell removed `service` from `host`: delete whatever the capability stored for it
    /// (configuration, credentials). Default: nothing.
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws

    /// Settings pages the capability contributes to the one settings surface, appended after the
    /// shell's own pages. Default: none.
    var settingsPages: [GlassCapabilitySettingsPage] { get }
    /// Controls the capability adds to the library toolbar (e.g. a quick-connect). Default: none.
    func libraryToolbarItems() -> AnyView
    /// Actions shown beside a service's Connect in the host detail, asked only for the
    /// capability's own kind. `host` is the catalog record that owns the service. Default: none.
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView

    /// Peer rows the capability contributes to the host detail below its services: tools that a
    /// configured service makes available rather than services of their own. The terminal offers
    /// Files (SFTP) when the server supports it; Stage 5's editor joins here.
    func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool]
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
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String? { nil }
    /// A capability that has not adopted the setup contract yet: the sheet shows why and Save
    /// refuses, so no half-made service can be created through it.
    func makeSetupDraft() -> any GlassServiceDraft { GlassUnavailableServiceDraft(kind: kind, capabilityName: displayName) }
    func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? { nil }
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws {}
    var settingsPages: [GlassCapabilitySettingsPage] { [] }
    func libraryToolbarItems() -> AnyView { AnyView(EmptyView()) }
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView { AnyView(EmptyView()) }
    func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] { [] }
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

    /// The owning capability's detail actions for a service, or nothing if no capability owns
    /// its kind. Only that capability is asked.
    public func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] {
        capability(for: service.kind)?.serviceTools(service: service, host: host) ?? []
    }

    public func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView {
        capability(for: service.kind)?.serviceDetailActions(service: service, host: host) ?? AnyView(EmptyView())
    }
}
