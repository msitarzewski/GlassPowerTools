//
//  GlassICloudStatus.swift
//  Glass Power Tools — GlassShell
//
//  The library's iCloud state, pinned to the foot of its sidebar: a cloud that says synced,
//  syncing, unavailable or failed the way Apple's own apps draw it, and opens to the last sync's
//  time, what it moved, why it failed, and Sync Now.
//
//  Asked for on 2026-09-27 after collections made on the Mac never reached the phone. The only
//  status was one line on the Privacy page of Settings, and it said "Synced" while the phone was
//  reading its own stale copies back: a failure nobody could see from where they were looking.
//

import SwiftUI
import GlassConnectionUI

/// The footer row: the cloud, and the state in a few words. Tapping it opens the details.
public struct GlassICloudStatusFooter: View {
    private let model: GlassShellModel
    @State private var showingDetails = false

    public init(model: GlassShellModel) { self.model = model }

    public var body: some View {
        #if os(visionOS)
        // On the headset a row-wide button lights up as a platter wherever the eyes land, which
        // reads as a big button rather than a status line (2026-09-29). The words are plain text,
        // as Mail's "Updated" line is; only the cloud is a button, and only it highlights.
        HStack(spacing: 8) {
            Button {
                showingDetails = true
            } label: {
                Image(systemName: symbol)
                    .symbolEffect(.rotate, isActive: isSyncing)
                    .foregroundStyle(isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
            .help(model.catalogSyncStatusDescription)
            .accessibilityLabel("iCloud")
            .accessibilityValue(model.catalogSyncStatusDescription)
            .accessibilityIdentifier("library-icloud-status")
            .popover(isPresented: $showingDetails) {
                GlassICloudStatusDetails(model: model)
            }
            Text(shortStatus)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .padding(.horizontal, 16).padding(.vertical, 10)
        #else
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolEffect(.rotate, isActive: isSyncing)
                    .foregroundStyle(isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                Text(shortStatus)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The list scrolls under it, so it needs a surface of its own: the bar material, with the
        // hairline Apple's footers draw above it.
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help(model.catalogSyncStatusDescription)
        .accessibilityLabel("iCloud")
        .accessibilityValue(model.catalogSyncStatusDescription)
        .accessibilityIdentifier("library-icloud-status")
        // A footer, one line at any text size: at the largest it read "Not synced on t…"
        // (2026-10-19). Past xxxLarge a long press shows the line whole.
        .accessibilityShowsLargeContentViewer {
            Label(shortStatus, systemImage: symbol)
        }
        .glassBar()
        .popover(isPresented: $showingDetails) {
            GlassICloudStatusDetails(model: model)
                .presentationCompactAdaptation(.popover)
        }
        #endif
    }

    /// One line that fits a sidebar; the popover has the rest.
    private var shortStatus: String {
        switch model.catalogSyncStatus {
        case .idle: model.catalogSyncStatusDescription
        case .syncing: "Syncing with iCloud…"
        case .synced(let date): "Synced with iCloud \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable: "iCloud unavailable"
        case .failed: "iCloud sync failed"
        }
    }

    private var isSyncing: Bool {
        if case .syncing = model.catalogSyncStatus { true } else { false }
    }

    private var isProblem: Bool {
        switch model.catalogSyncStatus {
        case .failed, .unavailable: true
        default: false
        }
    }

    /// The SF Symbols Apple's apps use for the same four states.
    private var symbol: String {
        switch model.catalogSyncStatus {
        case .idle: "icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .unavailable: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }
}

/// What the popover says: state, when, what moved, and the one action.
struct GlassICloudStatusDetails: View {
    let model: GlassShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud").font(.headline)
            Text(model.catalogSyncStatusDescription)
                .foregroundStyle(isProblem ? .red : .primary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = model.catalogSyncSummary {
                Text("\(summary.inAccount) records in iCloud · \(summary.received) received · \(summary.sent) sent")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("library-icloud-summary")
            }
            Text("Your machines, services and collections sync through iCloud to every device signed in to the same Apple Account.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.load() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncing)
            .accessibilityIdentifier("library-icloud-sync-now")
        }
        .padding()
        .frame(width: 320, alignment: .leading)
    }

    private var isSyncing: Bool {
        if case .syncing = model.catalogSyncStatus { true } else { false }
    }

    private var isProblem: Bool {
        switch model.catalogSyncStatus {
        case .failed, .unavailable: true
        default: false
        }
    }
}
