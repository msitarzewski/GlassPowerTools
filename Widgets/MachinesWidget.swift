//
//  MachinesWidget.swift
//  Glass Power Tools — Widgets
//
//  Favourite and recent machines, each with its services: a service's button connects to it, as
//  the library row's does, and a machine's name shows it in the library.
//

import SwiftUI
import WidgetKit
import GlassWidgetData

struct MachinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Machines", provider: SnapshotProvider()) { entry in
            MachinesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Machines")
        .description("Your favourite and recent machines. Tap a service to connect.")
        .supportedFamilies(Self.families)
        .glassOnVisionPro()
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct MachinesWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var rows: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        case .systemLarge: 9
        #if !os(visionOS)
        case .accessoryRectangular: 3
        #endif
        default: 1
        }
    }

    var body: some View {
        let machines = entry.snapshot?.machines(limit: rows) ?? []
        switch family {
        // The Lock Screen's sizes; Vision Pro has none.
        #if !os(visionOS)
        case .accessoryInline:
            inline(machines.first, total: entry.snapshot?.machines.count ?? 0)
        case .accessoryRectangular:
            rectangular(machines)
        #endif
        default:
            if machines.isEmpty {
                WidgetEmptyState(title: "No machines yet",
                                 detail: "Add one in Glass Power Tools, and your favourites and recent ones appear here.",
                                 symbol: "server.rack")
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                    if family != .systemSmall {
                        Label("Machines", systemImage: "server.rack")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(machines) { machine in
                        MachineRow(machine: machine, compact: family == .systemSmall,
                                   showsWhen: family != .systemSmall)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func inline(_ machine: GlassWidgetSnapshot.Machine?, total: Int) -> some View {
        if let machine {
            Label("\(machine.name)\(total > 1 ? " +\(total - 1)" : "")", systemImage: "server.rack")
        } else {
            Label("No machines", systemImage: "server.rack")
        }
    }

    private func rectangular(_ machines: [GlassWidgetSnapshot.Machine]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Machines", systemImage: "server.rack")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if machines.isEmpty {
                Text("None yet").font(.caption)
            }
            ForEach(machines) { machine in
                HStack(spacing: 3) {
                    if machine.isFavorite { Image(systemName: "star.fill").font(.system(size: 8)) }
                    Text(machine.name).font(.caption).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A machine: its name, which shows it, and a button for each service, which connects.
struct MachineRow: View {
    let machine: GlassWidgetSnapshot.Machine
    let compact: Bool
    let showsWhen: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: GlassShowMachineIntent(machine: machine.id)) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if machine.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .widgetAccentable()
                        }
                        Text(machine.name)
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    if showsWhen, let last = machine.lastConnected {
                        Text(last, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(machine.services.prefix(compact ? 1 : 3)) { service in
                Button(intent: GlassConnectServiceIntent(machine: machine.id, service: service.id)) {
                    Image(systemName: service.kind.symbolName)
                        .font(compact ? .caption : .body)
                        .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
                        .background(.tint.opacity(0.18), in: Circle())
                        .widgetAccentable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Connect to \(service.name)")
            }
        }
    }
}

#Preview(as: .systemMedium) {
    MachinesWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
    SnapshotEntry(date: .now, snapshot: nil)
}
