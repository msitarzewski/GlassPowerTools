//
//  MacWorkspaceTabDrag.swift
//  Glass Power Tools — GlassTerminal
//
//  Terminal tabs dragged between windows (owner, 2026-10-08: "draggable tabs for terminal to
//  consolidate multiple windows"). A tab's sidebar row drags out; dropped on another terminal
//  window's sidebar, the tab moves there with its terminals running, and a window whose last tab
//  leaves closes. Within one window the same drag reorders. "Move Tab to New Window" is the other
//  direction and keeps its broker; between two open windows the move is direct.
//

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Which tab, in which window. Only this app's windows read it, so nothing else accepts it.
nonisolated struct MacWorkspaceTabDrag: Codable, Equatable, Sendable {
    var windowID: UUID
    var workspaceID: UUID

    static let type = UTType(exportedAs: "com.glasspowertools.terminal-tab")

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: Self.type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }

    /// The first dragged tab among `providers`, delivered on the main actor.
    static func load(from providers: [NSItemProvider], _ completion: @escaping @MainActor (MacWorkspaceTabDrag) -> Void) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else { return }
        _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data, let drag = try? JSONDecoder().decode(MacWorkspaceTabDrag.self, from: data) else { return }
            Task { @MainActor in completion(drag) }
        }
    }
}
#endif
