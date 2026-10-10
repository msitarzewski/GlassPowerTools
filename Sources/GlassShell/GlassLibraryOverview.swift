//
//  GlassLibraryOverview.swift
//  Glass Power Tools — GlassShell
//
//  What the library's detail shows when no host is selected (D41, 2026-09-30): how many machines,
//  services, favourites and collections there are, and how this device has been used — connections
//  per day for the last 30 days and the machines used most. The history is this device's own
//  (`GlassShellPreferences.connectionHistory`) and is never synced.
//

import SwiftUI
import Charts
import GlassConnectionKit
import GlassConnectionUI

/// The overview's figures, worked out from the library and the history.
public struct GlassLibraryStatistics: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var date: Date
        public var kind: HostServiceKind
        public var count: Int
        public var id: String { "\(date.timeIntervalSinceReferenceDate)-\(kind.rawValue)" }
    }

    public struct Usage: Equatable, Sendable, Identifiable {
        public var hostID: HostID
        public var name: String
        public var count: Int
        public var id: HostID { hostID }
    }

    public var machines: Int
    public var services: Int
    public var servicesByKind: [HostServiceKind: Int]
    public var favorites: Int
    public var collections: Int
    /// Connections per day and kind, the last `days` days, oldest first; days without any omitted.
    public var perDay: [Day]
    /// Machines by connections in the same window, most first, at most five.
    public var mostUsed: [Usage]
    public var connectionsInWindow: Int

    public static func make(hosts: [GlassShellHost], isFavorite: (HostID) -> Bool,
                            history: [GlassShellPreferences.ConnectionEvent],
                            now: Date = Date(), days: Int = 30,
                            calendar: Calendar = .current) -> GlassLibraryStatistics {
        var byKind: [HostServiceKind: Int] = [:]
        for service in hosts.flatMap(\.services) { byKind[service.kind, default: 0] += 1 }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let window = history.filter { $0.date >= start && $0.date <= now }

        var buckets: [Date: [HostServiceKind: Int]] = [:]
        for event in window {
            buckets[calendar.startOfDay(for: event.date), default: [:]][event.kind, default: 0] += 1
        }
        let perDay = buckets.keys.sorted().flatMap { date in
            HostServiceKind.allCases.compactMap { kind in
                buckets[date]?[kind].map { Day(date: date, kind: kind, count: $0) }
            }
        }

        let names = Dictionary(hosts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        var perHost: [HostID: Int] = [:]
        for event in window where names[event.hostID] != nil { perHost[event.hostID, default: 0] += 1 }
        let mostUsed = perHost
            .map { Usage(hostID: $0.key, name: names[$0.key] ?? "", count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(5)

        return GlassLibraryStatistics(
            machines: hosts.count,
            services: hosts.reduce(0) { $0 + $1.services.count },
            servicesByKind: byKind,
            favorites: hosts.filter { isFavorite($0.id) }.count,
            collections: Set(hosts.flatMap(\.tags)).count,
            perDay: perDay,
            mostUsed: Array(mostUsed),
            connectionsInWindow: window.count)
    }
}

struct GlassLibraryOverview: View {
    let statistics: GlassLibraryStatistics
    let onSelectHost: (HostID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your Library").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    metric("Machines", statistics.machines, "server.rack")
                    metric("Services", statistics.services, "square.stack.3d.up")
                    metric("Favorites", statistics.favorites, "star")
                    metric("Collections", statistics.collections, "folder")
                }
                if !statistics.servicesByKind.isEmpty {
                    HStack(spacing: 20) {
                        ForEach(HostServiceKind.allCases, id: \.self) { kind in
                            if let count = statistics.servicesByKind[kind] {
                                Label {
                                    Text("\(count) \(GlassServicePresentation.displayName(for: kind))")
                                } icon: {
                                    GlassServiceIcon(GlassServicePresentation.symbol(for: kind))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                connectionsSection
                if !statistics.mostUsed.isEmpty { mostUsedSection }
            }
            #if os(visionOS)
            // Apple's own margins for the window it is in.
            .scenePadding()
            #else
            .padding(24)
            #endif
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("library-overview")
    }

    private func metric(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value, format: .number).font(.title.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections, last 30 days").font(.headline)
            if statistics.perDay.isEmpty {
                Text("Connections you make on this device appear here. They are kept on this device only.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(statistics.perDay) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Connections", day.count))
                        .foregroundStyle(by: .value("Service", GlassServicePresentation.displayName(for: day.kind)))
                }
                .frame(height: 180)
                .accessibilityLabel("Connections per day, last 30 days")
                Text("\(statistics.connectionsInWindow) connection\(statistics.connectionsInWindow == 1 ? "" : "s"), kept on this device only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var mostUsedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most used").font(.headline)
            ForEach(statistics.mostUsed) { usage in
                Button {
                    onSelectHost(usage.hostID)
                } label: {
                    HStack {
                        Text(usage.name)
                        Spacer()
                        Text("\(usage.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this machine")
            }
        }
    }
}
