//
//  GlassPowerToolsWidgets.swift
//  Glass Power Tools — Widgets
//
//  Machines and Active (2026-10-12), on iPhone, iPad, Vision Pro and the Mac. Both read the
//  snapshot the app writes into the App Group container (`GlassWidgetStore`), and a tap is an App
//  Intent that the app carries out (`GlassWidgetIntents`). They replace "Recent Servers", which
//  read a list nothing has written since D26.
//

import AppIntents
import SwiftUI
import WidgetKit
import GlassWidgetData

@main
struct GlassPowerToolsWidgets: WidgetBundle {
    var body: some Widget {
        MachinesWidget()
        ActiveWidget()
    }
}

/// The widget intents, as part of the extension too: its buttons name them.
struct GlassPowerToolsWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [GlassWidgetIntents.self] }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// Nil when the app has written none yet.
    let snapshot: GlassWidgetSnapshot?
}

/// One entry, the snapshot as it is now. The app reloads the widgets when it writes a new one;
/// the hourly reload is only a backstop.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // The gallery shows what this widget looks like with machines in it, before there are any.
        let stored = GlassWidgetStore.read()
        completion(SnapshotEntry(date: .now, snapshot: stored ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: GlassWidgetStore.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

extension GlassWidgetSnapshot {
    /// The gallery's and the placeholder's: generic names, never shown as the person's own.
    static var sample: GlassWidgetSnapshot {
        let now = Date.now
        func machine(_ name: String, favorite: Bool, ago: TimeInterval, _ kinds: [ServiceKind]) -> Machine {
            Machine(id: UUID(), name: name, isFavorite: favorite, lastConnected: now.addingTimeInterval(-ago),
                    services: kinds.map { Service(id: UUID(), kind: $0, name: $0.title) })
        }
        return GlassWidgetSnapshot(writtenAt: now, machines: [
            machine("Web Server", favorite: true, ago: 300, [.terminal, .database]),
            machine("Studio Mac", favorite: true, ago: 7200, [.terminal, .desktop]),
            machine("Build Box", favorite: false, ago: 900, [.terminal]),
            machine("Reports", favorite: false, ago: 86_400, [.database]),
        ], active: [
            ActiveMachine(machineID: nil, name: "Web Server", open: 2, running: 3, kinds: [.terminal, .database]),
            ActiveMachine(machineID: nil, name: "Studio Mac", open: 1, running: 0, kinds: [.desktop]),
        ])
    }
}

extension WidgetConfiguration {
    /// Apple's glass on Vision Pro, as every window of the app has it.
    func glassOnVisionPro() -> some WidgetConfiguration {
        #if os(visionOS)
        return self.widgetTexture(.glass).supportedMountingStyles([.elevated, .recessed])
        #else
        return self
        #endif
    }
}

/// The app's name and a hint, for a widget with nothing to show yet.
struct WidgetEmptyState: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
