import SwiftUI
import GlassConnectionKit

/// A capability owns one service kind. The shell routes `connect` through it;
/// the capability declares its own scenes statically in the app target.
@MainActor
public protocol GlassCapability: AnyObject {
    var kind: HostServiceKind { get }
    var displayName: String { get }
    var symbolName: String { get }
    func open(service: HostServiceLink, host: HostProfile)
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
}

/// What the shell shows when a service's capability is not in this build.
/// Deliberately not a session: it says exactly what is missing.
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
