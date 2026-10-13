//
//  MachineWidget.swift
//  Glass Power Tools — Widgets
//
//  One machine you choose, with a button for each of its services and what is open on it (D72,
//  2026-10-13) — on iPhone, iPad, the Mac and Vision Pro, where it can stand in the room beside the
//  machine's own windows. Without a choice it shows the first of your favourites and recent ones.
//

import AppIntents
import SwiftUI
import WidgetKit
import GlassWidgetData

struct MachineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Machine", intent: GlassMachineWidgetConfiguration.self,
                               provider: MachineProvider()) { entry in
            MachineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Machine")
        .description("One machine and its services. Tap a service to connect.")
        .supportedFamilies(Self.families)
        .glassOnVisionPro()
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct MachineEntry: TimelineEntry {
    let date: Date
    let machine: GlassWidgetSnapshot.Machine?
    let active: GlassWidgetSnapshot.ActiveMachine?
    /// A machine was chosen and is no longer in the library.
    let isMissing: Bool

    static func make(_ snapshot: GlassWidgetSnapshot?, chosen: UUID?) -> MachineEntry {
        let machine: GlassWidgetSnapshot.Machine?
        if let chosen {
            machine = snapshot?.machines.first { $0.id == chosen }
        } else {
            machine = snapshot?.machines(limit: 1).first
        }
        let active = machine.flatMap { found in snapshot?.active.first { $0.machineID == found.id } }
        return MachineEntry(date: .now, machine: machine, active: active,
                            isMissing: chosen != nil && snapshot != nil && machine == nil)
    }
}

struct MachineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MachineEntry {
        .make(.sample, chosen: nil)
    }

    func snapshot(for configuration: GlassMachineWidgetConfiguration, in context: Context) async -> MachineEntry {
        let stored = GlassWidgetStore.read()
        return .make(stored ?? (context.isPreview ? .sample : nil), chosen: configuration.machine?.id)
    }

    func timeline(for configuration: GlassMachineWidgetConfiguration, in context: Context) async -> Timeline<MachineEntry> {
        let entry = MachineEntry.make(GlassWidgetStore.read(), chosen: configuration.machine?.id)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600)))
    }
}

struct MachineWidgetView: View {
    let entry: MachineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let machine = entry.machine {
            switch family {
            #if !os(visionOS)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(machine.name, systemImage: "server.rack")
                        .font(.caption.weight(.semibold))
                        .widgetAccentable()
                    HStack(spacing: 6) {
                        ForEach(machine.services.prefix(4)) { Image(systemName: $0.kind.symbolName) }
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Button(intent: GlassShowMachineIntent(machine: machine.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(machine.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    services(machine)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if entry.isMissing {
            WidgetEmptyState(title: "Machine not found",
                             detail: "It is no longer in your library. Edit the widget to choose another.",
                             symbol: "server.rack")
        } else {
            WidgetEmptyState(title: "No machines yet",
                             detail: "Add one in Glass Power Tools, then edit the widget to choose it.",
                             symbol: "server.rack")
        }
    }

    private var status: String {
        guard let active = entry.active, active.open + active.running > 0 else { return "Nothing open" }
        var parts: [String] = []
        if active.open > 0 { parts.append("\(active.open) open") }
        if active.running > 0 { parts.append("\(active.running) running") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func services(_ machine: GlassWidgetSnapshot.Machine) -> some View {
        let shown = Array(machine.services.prefix(family == .systemSmall ? 3 : 4))
        let layout = family == .systemSmall
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(shown) { service in
                Button(intent: GlassConnectServiceIntent(machine: machine.id, service: service.id)) {
                    Label(service.name, systemImage: service.kind.symbolName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: family == .systemSmall ? .infinity : nil, alignment: .leading)
                        .background(.tint.opacity(0.18), in: Capsule())
                        .widgetAccentable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Connect to \(service.name)")
            }
        }
    }
}

#Preview(as: .systemMedium) {
    MachineWidget()
} timeline: {
    MachineEntry.make(.sample, chosen: nil)
}
