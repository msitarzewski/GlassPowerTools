//
//  GlassActiveSnippet.swift
//  Glass Power Tools — GlassWidgetData
//
//  "What's open in Glass Power Tools?" answered in place (D72, 2026-10-13): Siri, Spotlight and
//  Shortcuts show a card of the machines with something open or running, each with how much, and a
//  button that shows it in the library — without opening the app to ask. On every platform, Vision
//  Pro included. Read from the snapshot the widgets read.
//

import AppIntents
import SwiftUI

/// What is open and running, said and shown.
public struct GlassWhatsOpenIntent: AppIntent {
    public static let title: LocalizedStringResource = "What's Open"
    public static let description = IntentDescription("Says what is open and running in Glass Power Tools, without opening it.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = GlassEntitySource.snapshot()
        return .result(dialog: "\(Self.sentence(for: snapshot))", view: GlassActiveSnippet(snapshot: snapshot))
    }

    /// One sentence for Siri to say.
    static func sentence(for snapshot: GlassWidgetSnapshot?) -> String {
        guard let snapshot else { return "Open Glass Power Tools once, and it can tell you what's open." }
        let machines = snapshot.active.filter { $0.open + $0.running > 0 }
        guard !machines.isEmpty else { return "Nothing is open or running." }
        let open = snapshot.openCount, running = snapshot.runningCount
        var parts: [String] = []
        if open > 0 { parts.append("\(open) open") }
        if running > 0 { parts.append("\(running) running") }
        let on = machines.count == 1 ? "on \(machines[0].name)" : "on \(machines.count) machines"
        return parts.joined(separator: " and ") + " " + on + "."
    }
}

/// The card: a row per machine with something open or running.
struct GlassActiveSnippet: View {
    let snapshot: GlassWidgetSnapshot?

    private var machines: [GlassWidgetSnapshot.ActiveMachine] {
        (snapshot?.active ?? []).filter { $0.open + $0.running > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if machines.isEmpty {
                Label("Nothing is open or running.", systemImage: "bolt.slash")
                    .foregroundStyle(.secondary)
            }
            ForEach(machines.prefix(6)) { machine in
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(machine.kinds, id: \.self) { Image(systemName: $0.symbolName) }
                    }
                    .foregroundStyle(.tint)
                    .frame(minWidth: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(machine.name).font(.headline).lineLimit(1)
                        Text(Self.counts(machine)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let id = machine.machineID {
                        Button(intent: GlassShowMachineIntent(machine: id)) {
                            Label("Show", systemImage: "arrow.up.forward.app")
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .padding()
    }

    static func counts(_ machine: GlassWidgetSnapshot.ActiveMachine) -> String {
        var parts: [String] = []
        if machine.open > 0 { parts.append("\(machine.open) open") }
        if machine.running > 0 { parts.append("\(machine.running) running") }
        return parts.joined(separator: " · ")
    }
}
