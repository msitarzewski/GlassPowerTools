//
//  MutationAuditView.swift
//  Glass Power Tools — GlassDatabase
//
//  Reading the mutation audit, which until now was written and never read.
//
//  The Stage 3 plan recorded this as "one list view", then corrected itself to "there is no store
//  to view — mutations go to OSLog". **Both were out of date by the time the work started.** The
//  port already ships a real store: `MutationAuditStore` in `Models.swift`, a 1,000-record ring in
//  `UserDefaults`, appended to by every write path — row update, pasted range, insert, truncate,
//  drop, schema change, confirmed editor statement, and now deletion. What was missing was the
//  reader. `OSLogStore` was never the right answer regardless: it is restricted on iOS, and a log
//  line is not a structured mutation.
//
//  The reader lives here rather than beside the writer because `Models.swift` is another worker's
//  file this stage; nothing about it needs to be private.
//
//  **No row values are displayed here, because none are stored.** See `RowIdentityPredicate`.
//

import SwiftUI

// MARK: - Reading the store

extension MutationAuditStore {

    /// Newest first. A record that will not decode is dropped rather than failing the whole read:
    /// an audit that disappears because one entry is malformed is worse than a short audit.
    static func records(defaults: UserDefaults = .standard) -> [MutationAuditRecord] {
        guard let data = defaults.data(forKey: UserDefaultsKeys.mutationAudit),
              let decoded = try? JSONDecoder().decode([MutationAuditRecord].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    static func records(forConnection connectionID: UUID,
                        defaults: UserDefaults = .standard) -> [MutationAuditRecord] {
        records(defaults: defaults).filter { $0.connectionID == connectionID }
    }

    /// Clears the whole ring. Deliberately all-or-nothing: an audit a user can edit selectively
    /// is not an audit.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: UserDefaultsKeys.mutationAudit)
    }
}

extension MutationOutcome {
    var displayName: String {
        switch self {
        case .committed: "Committed"
        case .rolledBack: "Rolled back"
        case .serverStateUnknown: "Server state unknown"
        case .notStarted: "Not started"
        }
    }

    var systemImage: String {
        switch self {
        case .committed: "checkmark.circle"
        case .rolledBack: "arrow.uturn.backward.circle"
        case .serverStateUnknown: "questionmark.circle"
        case .notStarted: "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .committed: .green
        case .rolledBack: .secondary
        case .serverStateUnknown: .orange
        case .notStarted: .secondary
        }
    }

    /// What the outcome actually means for the database, in the user's terms. `serverStateUnknown`
    /// is the one that matters: the commit was sent and the answer never came back, so the row may
    /// or may not have changed and only the server can say.
    var explanation: String {
        switch self {
        case .committed: "The server accepted the change."
        case .rolledBack: "The change failed and the transaction was rolled back."
        case .serverStateUnknown:
            "The commit was sent and no confirmation came back. The change may or may not have been applied; check the table."
        case .notStarted: "The statement was refused before any transaction began."
        }
    }
}

// MARK: - The viewer

struct MutationAuditView: View {
    /// The connection whose mutations open first. `nil` shows everything.
    var connectionID: UUID?
    var connectionName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showsAllConnections = false
    @State private var records: [MutationAuditRecord] = []
    @State private var confirmingClear = false

    private var visibleRecords: [MutationAuditRecord] {
        guard let connectionID, !showsAllConnections else { return records }
        return records.filter { $0.connectionID == connectionID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleRecords.isEmpty {
                    ContentUnavailableView(
                        "No Mutations Recorded",
                        systemImage: "list.bullet.rectangle.portrait",
                        description: Text("Every row, schema and confirmed statement change this app makes is recorded here. Row values are never recorded — only which columns identified the row.")
                    )
                } else {
                    List(visibleRecords) { record in
                        MutationAuditRow(record: record)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Mutation Log")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if connectionID != nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Toggle("All Connections", isOn: $showsAllConnections)
                            .help(connectionName.map { "Showing \($0) only; turn on to include every connection" }
                                  ?? "Include mutations from every connection")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Clear Log…", systemImage: "trash", role: .destructive) {
                        confirmingClear = true
                    }
                    .disabled(records.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .confirmationDialog("Clear the mutation log?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear Log", role: .destructive) {
                    MutationAuditStore.clear()
                    records = []
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every recorded mutation is removed, for every connection. This changes nothing in any database.")
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task { records = MutationAuditStore.records() }
    }
}

private struct MutationAuditRow: View {
    let record: MutationAuditRecord

    private var objectPath: String {
        [record.database, record.object].compactMap { $0 }.joined(separator: ".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(record.normalizedOperation.uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                Text(objectPath.isEmpty ? "—" : objectPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Label(record.outcome.displayName, systemImage: record.outcome.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(record.outcome.tint)
            }
            HStack(spacing: 10) {
                Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                Text(record.source)
                if let affected = record.affectedRows {
                    Text("\(affected) row\(affected == 1 ? "" : "s")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let predicate = record.predicate, !predicate.isEmpty {
                // The shape, with its placeholders. There are no values here to show, by design.
                Text(predicate)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityLabel("Row identified by \(predicate)")
            }
            if record.outcome == .serverStateUnknown {
                Text(record.outcome.explanation)
                    .font(.caption)
                    .foregroundStyle(record.outcome.tint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.normalizedOperation) on \(objectPath), \(record.outcome.displayName)")
    }
}
