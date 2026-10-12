//
//  ActiveWidget.swift
//  Glass Power Tools — Widgets
//
//  What is running: sessions open in the app, and sessions left running on machines (tmux,
//  detached, open on another device), by machine. A tap opens Active. The counts are as of the
//  last time the app wrote them, and the widget says when that was.
//

import SwiftUI
import WidgetKit
import GlassWidgetData

struct ActiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Active", provider: SnapshotProvider()) { entry in
            ActiveWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active")
        .description("What's open in Glass Power Tools, and what's running on your machines.")
        .supportedFamilies(Self.families)
        .glassOnVisionPro()
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct ActiveWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot ?? GlassWidgetSnapshot(writtenAt: entry.date)
        Button(intent: GlassShowActiveIntent()) {
            content(snapshot)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ snapshot: GlassWidgetSnapshot) -> some View {
        switch family {
        // The Lock Screen's sizes; Vision Pro has none.
        #if !os(visionOS)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill").font(.caption).widgetAccentable()
                    Text("\(snapshot.openCount)").font(.title3.weight(.semibold)).minimumScaleFactor(0.6)
                }
            }
        case .accessoryInline:
            Label(Self.summary(snapshot), systemImage: "bolt.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Active", systemImage: "bolt.fill")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(Self.summary(snapshot)).font(.caption)
                if let first = snapshot.active.first {
                    Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text("\(snapshot.openCount)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("open").font(.caption).foregroundStyle(.secondary)
                if snapshot.runningCount > 0 {
                    Text("\(snapshot.runningCount) running on machines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Active", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .widgetAccentable()
                    Spacer()
                    Text(Self.summary(snapshot)).font(.caption).foregroundStyle(.secondary)
                }
                if snapshot.active.isEmpty {
                    Text("Nothing open").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(snapshot.active.prefix(3)) { machine in
                    HStack(spacing: 6) {
                        ForEach(machine.kinds, id: \.self) { kind in
                            Image(systemName: kind.symbolName).font(.caption).foregroundStyle(.tint)
                        }
                        Text(machine.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(Self.counts(open: machine.open, running: machine.running))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                // Honest about age: the counts are the app's as it last wrote them.
                if entry.snapshot != nil {
                    (Text("Updated ") + Text(snapshot.writtenAt, style: .relative) + Text(" ago"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    static func summary(_ snapshot: GlassWidgetSnapshot) -> String {
        counts(open: snapshot.openCount, running: snapshot.runningCount)
    }

    static func counts(open: Int, running: Int) -> String {
        switch (open, running) {
        case (0, 0): "Nothing open"
        case (_, 0): "\(open) open"
        case (0, _): "\(running) running"
        default: "\(open) open · \(running) running"
        }
    }
}

#Preview(as: .systemMedium) {
    ActiveWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
