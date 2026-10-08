//
//  MacWorkspaceTabDrag.swift
//  Glass Power Tools — GlassTerminal
//
//  Terminal tabs dragged between windows (owner, 2026-10-08: "draggable tabs for terminal to
//  consolidate multiple windows"). A tab's sidebar row drags out; dropped on another terminal
//  window's sidebar, the tab moves there with its terminals running, and a window whose last tab
//  leaves closes. Within one window the same drag reorders. "Move Tab to New Window" is the other
//  direction and keeps its broker; between two open windows the move is direct. Tabs selected
//  together in the sidebar drag together, one payload each (W8, 2026-10-08).
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

    /// Every dragged tab among `providers`, in their order, delivered together on the main actor
    /// once each has loaded: dragging one of several selected rows carries a provider per row
    /// (W8), and they must land as one move, not one at a time in whatever order they load.
    @MainActor
    static func load(from providers: [NSItemProvider], _ completion: @escaping @MainActor ([MacWorkspaceTabDrag]) -> Void) {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(type.identifier) }
        guard !matching.isEmpty else { return }
        let gathered = Gathered(count: matching.count, completion)
        for (index, provider) in matching.enumerated() {
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                let drag = data.flatMap { try? JSONDecoder().decode(MacWorkspaceTabDrag.self, from: $0) }
                Task { @MainActor in gathered.add(drag, at: index) }
            }
        }
    }

    /// The tabs of one drop as they load; delivered once every provider has answered.
    @MainActor private final class Gathered {
        private var drags: [MacWorkspaceTabDrag?]
        private var waiting: Int
        private let completion: @MainActor ([MacWorkspaceTabDrag]) -> Void

        init(count: Int, _ completion: @escaping @MainActor ([MacWorkspaceTabDrag]) -> Void) {
            drags = Array(repeating: nil, count: count)
            waiting = count
            self.completion = completion
        }

        func add(_ drag: MacWorkspaceTabDrag?, at index: Int) {
            drags[index] = drag
            waiting -= 1
            guard waiting == 0 else { return }
            let loaded = drags.compactMap { $0 }
            if !loaded.isEmpty { completion(loaded) }
        }
    }
}
#endif
