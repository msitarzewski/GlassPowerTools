//
//  GlassLibraryOverview.swift
//  Glass Power Tools — GlassShell
//
//  What the library's detail shows when no host is selected (D41, 2026-09-30): how many machines,
//  services, favourites and collections there are, and how they have been used — connections per
//  day for the last 30 days and the machines used most. On every device, added up, or on one chosen
//  (D81, 2026-10-17): each device's history stays on it, and its counts per day travel
//  (`GlassUsagePayload`).
//
//  Time in use first (2026-10-20, the owner: "this show half truths! … I've had tmux sessions
//  running for days in a row now and that's not reflected"): a connection is counted once, however
//  long it stays open, so the chart opens on the minutes sessions had input or output
//  (`GlassShellModel.countMinuteInUse`), with connections a choice beside it.
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
        /// Minutes in use that day through that kind (2026-10-20).
        public var minutes: Int = 0
        public var id: String { "\(date.timeIntervalSinceReferenceDate)-\(kind.rawValue)" }
    }

    public struct Usage: Equatable, Sendable, Identifiable {
        public var hostID: HostID
        public var name: String
        public var count: Int
        public var minutes: Int = 0
        public var id: HostID { hostID }
    }

    public var machines: Int
    public var services: Int
    public var servicesByKind: [HostServiceKind: Int]
    public var favorites: Int
    public var collections: Int
    /// Connections and minutes in use per day and kind, the last `days` days, oldest first; days
    /// with neither omitted.
    public var perDay: [Day]
    /// Machines by connections in the same window, most first, at most five.
    public var mostUsed: [Usage]
    /// Machines by time in use in the same window, most first, at most five (2026-10-20).
    public var mostUsedByTime: [Usage] = []
    public var connectionsInWindow: Int
    public var minutesInWindow: Int = 0

    public static func make(hosts: [GlassShellHost], isFavorite: (HostID) -> Bool,
                            history: [GlassShellPreferences.ConnectionEvent],
                            now: Date = Date(), days: Int = 30,
                            calendar: Calendar = .current) -> GlassLibraryStatistics {
        make(hosts: hosts, isFavorite: isFavorite,
             counts: history.map { GlassUsageCount(date: $0.date, hostID: $0.hostID, kind: $0.kind, count: 1) },
             now: now, days: days, calendar: calendar)
    }

    /// The same from counts — this device's connections and other devices' days (D81).
    public static func make(hosts: [GlassShellHost], isFavorite: (HostID) -> Bool,
                            counts: [GlassUsageCount],
                            now: Date = Date(), days: Int = 30,
                            calendar: Calendar = .current) -> GlassLibraryStatistics {
        var byKind: [HostServiceKind: Int] = [:]
        for service in hosts.flatMap(\.services) { byKind[service.kind, default: 0] += 1 }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let window = counts.filter { $0.date >= start && $0.date <= now }

        var buckets: [Date: [HostServiceKind: (count: Int, minutes: Int)]] = [:]
        for event in window {
            let day = calendar.startOfDay(for: event.date)
            let sum = buckets[day]?[event.kind] ?? (0, 0)
            buckets[day, default: [:]][event.kind] = (sum.count + event.count, sum.minutes + event.minutes)
        }
        let perDay = buckets.keys.sorted().flatMap { date in
            HostServiceKind.allCases.compactMap { kind in
                buckets[date]?[kind].map { Day(date: date, kind: kind, count: $0.count, minutes: $0.minutes) }
            }
        }

        let names = Dictionary(hosts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        var perHost: [HostID: (count: Int, minutes: Int)] = [:]
        for event in window where names[event.hostID] != nil {
            let sum = perHost[event.hostID] ?? (0, 0)
            perHost[event.hostID] = (sum.count + event.count, sum.minutes + event.minutes)
        }
        let usages = perHost.map { Usage(hostID: $0.key, name: names[$0.key] ?? "", count: $0.value.count,
                                         minutes: $0.value.minutes) }
        let mostUsed = usages.filter { $0.count > 0 }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(5)
        let mostUsedByTime = usages.filter { $0.minutes > 0 }
            .sorted { ($0.minutes, $1.name) > ($1.minutes, $0.name) }
            .prefix(5)

        return GlassLibraryStatistics(
            machines: hosts.count,
            services: hosts.reduce(0) { $0 + $1.services.count },
            servicesByKind: byKind,
            favorites: hosts.filter { isFavorite($0.id) }.count,
            collections: Set(hosts.flatMap(\.tags)).count,
            perDay: perDay,
            mostUsed: Array(mostUsed),
            mostUsedByTime: Array(mostUsedByTime),
            connectionsInWindow: window.reduce(0) { $0 + $1.count },
            minutesInWindow: window.reduce(0) { $0 + $1.minutes })
    }
}

struct GlassLibraryOverview: View {
    let hosts: [GlassShellHost]
    let isFavorite: (HostID) -> Bool
    /// Every device's connections, this one first (`GlassShellModel.usageByDevice`).
    let devices: [GlassDeviceUsage]
    let onSelectHost: (HostID) -> Void
    /// The device whose connections are shown; nil for all of them, added up.
    @State private var chosenDevice: String?
    /// What the chart and Most Used measure: time in use unless connections are chosen.
    @State private var measure: GlassUsageMeasure = .time
    /// Where a tile's word starts, past its symbol. It grows with the text, as the symbol does: at
    /// a fixed 24 points the symbol lay over the word at the largest sizes (2026-10-19).
    @ScaledMetric(relativeTo: .subheadline) private var metricSymbolColumn: CGFloat = 24

    /// The devices to choose from: this one, and each other with connections in the last 30 days.
    private var listed: [GlassDeviceUsage] {
        let start = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return devices.filter { $0.isThisDevice || $0.counts.contains { $0.date >= start } }
    }

    /// The chosen device while it is listed; nil, every device, otherwise.
    private var shownDevice: GlassDeviceUsage? {
        chosenDevice.flatMap { id in listed.first { $0.id == id } }
    }

    private var statistics: GlassLibraryStatistics {
        .make(hosts: hosts, isFavorite: isFavorite, counts: (shownDevice.map { [$0] } ?? listed).flatMap(\.counts))
    }

    var body: some View {
        let statistics = statistics
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if !os(visionOS)
                Text("Your Library").font(.largeTitle.bold())
                #endif
                metrics(statistics)
                if !statistics.servicesByKind.isEmpty {
                    // In a line, or one under another where they do not fit: at the largest text
                    // sizes a line of three broke "Desktop" a letter or two to a line (2026-10-19).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { serviceCounts(statistics) }
                        VStack(alignment: .leading, spacing: 8) { serviceCounts(statistics) }
                    }
                }
                usageSection(statistics)
                if !mostUsed(statistics).isEmpty { mostUsedSection(statistics) }
            }
            .glassDetailPageInsets()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("library-overview")
        // The column's own title, level with the sidebar's "All Connections" (owner: "let's keep
        // all tiles and shapes aligned"). It was text inside the scroll view, which sat higher
        // than the sidebar's title; then the column's navigation title (6d132e9); now our own
        // column's header, at the same height (W33).
        .glassSpatialColumn("Your Library")
    }

    @ViewBuilder private func serviceCounts(_ statistics: GlassLibraryStatistics) -> some View {
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

    /// The four figures, in one even row, or two even rows of two where the column is narrow:
    /// every tile the same width, so their edges line up with the chart and the list below. An
    /// adaptive grid left three on one row and one under it, short of the right-hand edge. Where
    /// two do not fit side by side, at the largest text sizes, one to a row: two to a row broke
    /// "Ma-chines" and "Collec-tions" (2026-10-19).
    private func metrics(_ statistics: GlassLibraryStatistics) -> some View {
        let machines = metric("Machines", statistics.machines, "server.rack")
        let services = metric("Services", statistics.services, "square.stack.3d.up")
        let favorites = metric("Favorites", statistics.favorites, "star")
        let collections = metric("Collections", statistics.collections, "folder")
        return ViewThatFits(in: .horizontal) {
            GlassEqualWidthRow(spacing: 12) {
                machines; services; favorites; collections
            }
            VStack(spacing: 12) {
                GlassEqualWidthRow(spacing: 12) { machines; services }
                GlassEqualWidthRow(spacing: 12) { favorites; collections }
            }
            VStack(spacing: 12) {
                machines; services; favorites; collections
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The words set the line's height and the symbol sits over its start: the four symbols
            // differ in height, and side by side they set each tile's label a little lower or higher.
            Text(title)
                .padding(.leading, metricSymbolColumn)
                .overlay(alignment: .leading) { Image(systemName: symbol) }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value, format: .number).font(.title.bold()).monospacedDigit()
        }
        // The row's width and height, so every tile in it is the same shape.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// The days the chart shows for the measure chosen: those with time in use, or with connections.
    private func shownDays(_ statistics: GlassLibraryStatistics) -> [GlassLibraryStatistics.Day] {
        statistics.perDay.filter { measure == .time ? $0.minutes > 0 : $0.count > 0 }
    }

    private func mostUsed(_ statistics: GlassLibraryStatistics) -> [GlassLibraryStatistics.Usage] {
        measure == .time ? statistics.mostUsedByTime : statistics.mostUsed
    }

    private func usageSection(_ statistics: GlassLibraryStatistics) -> some View {
        let days = shownDays(statistics)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(measure == .time ? "Time in use, last 30 days" : "Connections, last 30 days").font(.headline)
                Spacer(minLength: 8)
                // All of them first, then each device by the name it was given (the owner: "use the
                // device name, not the product. I might have two vision pros").
                if listed.count > 1 {
                    Picker("Device", selection: $chosenDevice) {
                        Text("All Devices").tag(String?.none)
                        ForEach(listed) { device in
                            Text(device.name).tag(String?.some(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Device")
                    .accessibilityIdentifier("library-overview-device")
                }
            }
            Picker("Measure", selection: $measure) {
                Text("Time in Use").tag(GlassUsageMeasure.time)
                Text("Connections").tag(GlassUsageMeasure.connections)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Measure")
            .accessibilityIdentifier("library-overview-measure")
            if days.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                Chart(days) { day in
                    if measure == .time {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", Double(day.minutes) / 60))
                            .foregroundStyle(by: .value("Service", GlassServicePresentation.displayName(for: day.kind)))
                    } else {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Connections", day.count))
                            .foregroundStyle(by: .value("Service", GlassServicePresentation.displayName(for: day.kind)))
                    }
                }
                .frame(height: 180)
                .accessibilityLabel(measure == .time ? "Hours in use per day, last 30 days"
                                                     : "Connections per day, last 30 days")
                Text(caption(statistics))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var emptyText: String {
        switch measure {
        case .time:
            shownDevice.map { "No time in use on \($0.name) in the last 30 days." }
                ?? "Time in sessions on any of your devices appears here: each minute with input or output counts."
        case .connections:
            shownDevice.map { "No connections on \($0.name) in the last 30 days." }
                ?? "Connections you make on any of your devices appear here, counted per day."
        }
    }

    /// "41 hours in use on 3 devices", "142 connections on 3 devices", or on the one chosen.
    private func caption(_ statistics: GlassLibraryStatistics) -> String {
        let figure: String
        switch measure {
        case .time:
            figure = GlassUsageMeasure.spoken(minutes: statistics.minutesInWindow) + " in use"
        case .connections:
            let total = statistics.connectionsInWindow
            figure = "\(total) connection\(total == 1 ? "" : "s")"
        }
        if let shownDevice { return "\(figure) on \(shownDevice.name)." }
        let start = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        let used = listed.filter { device in
            device.counts.contains { $0.date >= start && (measure == .time ? $0.minutes > 0 : $0.count > 0) }
        }
        if used.count == 1, let only = used.first { return "\(figure) on \(only.name)." }
        return "\(figure) on \(used.count) devices."
    }

    private func mostUsedSection(_ statistics: GlassLibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most used").font(.headline)
            ForEach(mostUsed(statistics)) { usage in
                Button {
                    onSelectHost(usage.hostID)
                } label: {
                    HStack {
                        Text(usage.name)
                        Spacer()
                        Text(measure == .time ? GlassUsageMeasure.short(minutes: usage.minutes) : "\(usage.count)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this machine")
            }
        }
    }
}

/// What the overview's chart measures (2026-10-20).
enum GlassUsageMeasure: Hashable {
    /// Minutes a session had input or output.
    case time
    /// Connections made from the library.
    case connections

    /// "25 minutes", "1 hour", "41 hours": whole hours from an hour up.
    static func spoken(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = Int((Double(minutes) / 60).rounded())
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }

    /// "45 min", "2.5 h", "41 h", for a row's figure.
    static func short(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            return tenths == tenths.rounded() ? "\(Int(tenths)) h" : "\(tenths) h"
        }
        return "\(Int(hours.rounded())) h"
    }
}

/// Where a detail column's scrolling page sets its content: the overview, and Active's when
/// nothing is open. Each draws its own large title as the first line of the page.
private struct GlassDetailPageInsets: ViewModifier {
    #if os(visionOS)
    /// Where visionOS sets a column's navigation title from the column's leading edge, measured in
    /// the visionOS 27 simulator; the page's left edge follows it.
    static let titleInset: CGFloat = 24
    #endif

    func body(content: Content) -> some View {
        content
            #if os(visionOS)
            // Level with the column's title on the left (visionOS sets it 24 points in), and at
            // least the terminal's margin from the window's own edges, right and bottom (owner,
            // 2026-10-10: "I like the minimum space that terminal provides as a margin").
            .padding(.leading, Self.titleInset)
            .padding(.trailing, GlassWindowShape.spatialNestedCanvasInset)
            .padding(.bottom, GlassWindowShape.spatialNestedCanvasInset)
            #elseif os(iOS)
            // **Level with the list's "All Connections"** on an iPad or an unfolded iPhone Duo
            // (2026-10-12; the owner drew a line between the two titles, 20 points apart). That title
            // is the list column's system large title; a detail column's own is inline by default, so
            // this one stays ours, raised to the same line: measured on the Duo, the 24-point inset
            // put it 20 points low.
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, GlassDetailColumnTitleMetrics.top)
            #else
            .padding(24)
            #endif
    }
}

extension View {
    /// This detail column page's insets: its title on the list column's title line, and its
    /// edges where the overview's are.
    func glassDetailPageInsets() -> some View { modifier(GlassDetailPageInsets()) }
}
