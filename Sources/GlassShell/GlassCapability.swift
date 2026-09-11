import SwiftUI
import GlassConnectionKit

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
    /// The host's address (DNS name or IP). Present whenever the shell opens a setup; nil only
    /// for a connect on a legacy host record that has no address and whose service already
    /// exists on the capability's side.
    public let address: String?

    public init(address: String?) {
        self.address = address
    }
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
    /// True when opening `service` would present a setup form (the capability holds nothing for
    /// it yet). The shell then makes sure the host has an address first, so no setup form ever
    /// asks for one. Default: false.
    func needsSetup(service: HostServiceLink, host: HostProfile) -> Bool
    /// The address the capability already stores for `service`, if any — a record saved by the
    /// source app before hosts carried an address. The shell adopts it onto the host so the
    /// machine's identity is defined once, at the host. Default: nil.
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String?

    /// Settings pages the capability contributes to the one settings surface, appended after the
    /// shell's own pages. Default: none.
    var settingsPages: [GlassCapabilitySettingsPage] { get }
    /// Controls the capability adds to the library toolbar (e.g. a quick-connect). Default: none.
    func libraryToolbarItems() -> AnyView
    /// Actions shown beside a service's Connect in the host detail, asked only for the
    /// capability's own kind. `host` is the catalog record that owns the service. Default: none.
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView
}

public extension GlassCapability {
    func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        open(service: service, host: host, report: report)
    }
    func hostAddressDidChange(host: HostProfile, address: String?) {}
    func needsSetup(service: HostServiceLink, host: HostProfile) -> Bool { false }
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String? { nil }
    var settingsPages: [GlassCapabilitySettingsPage] { [] }
    func libraryToolbarItems() -> AnyView { AnyView(EmptyView()) }
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView { AnyView(EmptyView()) }
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
    public static func symbolName(for kind: HostServiceKind) -> String {
        switch kind {
        case .ssh: "terminal"
        case .database: "externaldrive"
        case .rdp: "display"
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
    public func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView {
        capability(for: service.kind)?.serviceDetailActions(service: service, host: host) ?? AnyView(EmptyView())
    }
}

/// What the shell shows when a service's capability is not in this build.
/// Deliberately not a session: it says exactly what is missing.
/// The shell must collect the host's address before it can continue. `endpointID` is the service
/// whose connect was interrupted (resumed once the address is saved), nil when the user simply
/// asked to set the address from the host detail.
public struct GlassShellAddressRequest: Identifiable, Sendable {
    public let host: GlassShellHost
    public let endpointID: EndpointID?
    public var id: HostID { host.id }

    public init(host: GlassShellHost, endpointID: EndpointID?) {
        self.host = host
        self.endpointID = endpointID
    }
}

public struct GlassShellPlaceholderRequest: Identifiable, Hashable, Sendable {
    public let host: HostProfile
    public let service: HostServiceLink
    public var id: EndpointID { service.endpointID }
}

public struct GlassShellPlaceholderSession: View {
    let request: GlassShellPlaceholderRequest
    @Environment(\.dismiss) private var dismiss

    public init(request: GlassShellPlaceholderRequest) { self.request = request }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(request.service.displayName, systemImage: GlassServicePresentation.symbolName(for: request.service.kind))
            } description: {
                Text("\(GlassServicePresentation.displayName(for: request.service.kind)) is not part of this build yet. \(request.host.displayName) and this service are saved; nothing was connected.")
            }
            .navigationTitle(request.host.displayName)
            .accessibilityIdentifier("placeholder-session")
            // Toolbar, not the unavailable view's actions slot: on visionOS the identified
            // container is exposed as one element and swallows buttons inside it.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("placeholder-done")
                }
            }
        }
        #if os(visionOS) || os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
