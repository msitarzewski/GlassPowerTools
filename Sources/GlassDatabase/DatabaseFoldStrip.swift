//
//  DatabaseFoldStrip.swift
//  Glass Power Tools — GlassDatabase
//
//  A query's strip below an iPhone Duo's fold (D93, 2026-10-31): stood like a laptop, the query and
//  its results sit above the fold, and here, between the fold and the keyboard's keys, are Run (the
//  toolbar's own menu: the statement, the selection or all of them), Explain, and the keys SQL wants
//  that a phone's keyboard hides. With the keyboard put away, the selected row is below.
//

#if os(iOS)
import SwiftUI

/// What the query editor lends its tab's strip: Run and Explain, as its toolbar has them.
struct DatabaseFoldActions {
    let availability: SQLRunAvailability
    let run: (SQLExecutionMode) -> Void
    let canExplain: Bool
    let explain: () -> Void
}

extension EnvironmentValues {
    @Entry var databaseFoldActions: DatabaseFoldActions? = nil
}

struct DatabaseFoldStrip: View {
    let controller: SQLEditorController
    let actions: DatabaseFoldActions?

    /// The characters, as they are typed.
    private static let characters = ["*", ",", "(", ")", "'", "=", "<", ">", ";", "%", ".", "_"]

    var body: some View {
        HStack(spacing: 8) {
            if let actions {
                SQLRunControl(availability: actions.availability, run: actions.run)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Button("Explain Plan", systemImage: "point.3.connected.trianglepath.dotted", action: actions.explain)
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(!actions.canExplain)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Self.characters, id: \.self) { character in
                        Button { controller.type(character) } label: {
                            Text(character).frame(minWidth: 32, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Type \(character)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .font(.body.monospaced())
        .accessibilityIdentifier("db-fold-strip")
    }
}
#endif
