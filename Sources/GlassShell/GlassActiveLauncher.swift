//
//  GlassActiveLauncher.swift
//  Glass Power Tools — GlassShell
//
//  What Active offers when nothing is open: the library's machines under the service they have,
//  Terminal, Database and Desktop, each one a tap from connecting. The owner, 2026-10-12, at the
//  unfolded iPhone Duo's empty Active detail: "Why not show options from the defined machines?
//  Terminal > [machines with terminals] Database > [Machines with databases] etc?" The Mac, an
//  iPad and the headset showed the same thing there: "Nothing Is Open", and nothing to do about it.
//
//  Where a detail column is on screen it is the detail's page; on a phone, folded, it is the rest
//  of the Active list under "Nothing Is Open". A row connects that one service, as the Connect
//  menu's item for it does (`GlassShellModel.connect(hostID:endpointID:)`).
//

import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// The machines to offer, by service. Pure, so what is offered is tested without a screen.
struct GlassActiveLauncher: Equatable {
    struct Entry: Identifiable, Equatable {
        var hostID: HostID
        var endpointID: EndpointID
        var machine: String
        /// The service's own name, where it says more than the machine's name under its heading:
        /// "MySQL on alpha", "Local Shell", or which of a machine's two terminals this is.
        var detail: String?
        var id: EndpointID { endpointID }
    }

    struct Section: Identifiable, Equatable {
        var kind: HostServiceKind
        var entries: [Entry]
        var id: HostServiceKind { kind }
        var title: String { GlassServicePresentation.displayName(for: kind) }
    }

    var sections: [Section]

    var isEmpty: Bool { sections.isEmpty }

    /// `hosts` in the library's order; `kinds` in the order to offer them. A kind with no
    /// machine has no section.
    init(hosts: [GlassShellHost], kinds: [HostServiceKind]) {
        sections = kinds.compactMap { kind in
            let entries = hosts.flatMap { host in
                host.services.filter { $0.kind == kind }.map { service in
                    Entry(hostID: host.id, endpointID: service.endpointID, machine: host.displayName,
                          detail: Self.detail(for: service, on: host))
                }
            }
            return entries.isEmpty ? nil : Section(kind: kind, entries: entries)
        }
    }

    /// Nil when the service's name only restates its heading and machine: the name the setup
    /// gives a service it is not told one for ("Terminal on alpha"), or the machine's own name.
    static func detail(for service: HostServiceLink, on host: GlassShellHost) -> String? {
        let name = service.displayName
        let kind = GlassServicePresentation.displayName(for: service.kind)
        let restated = [host.displayName, kind, "\(kind) on \(host.displayName)"]
        if name.isEmpty || restated.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return nil }
        return name
    }
}

extension GlassShellModel {
    /// The machines Active offers when nothing is open, in the setup's tab order (Terminal,
    /// Database, Desktop). A kind this build has no capability for is not offered: choosing it
    /// would only say so.
    func activeLauncher() -> GlassActiveLauncher {
        let registered = Set(registry.registeredKinds)
        return GlassActiveLauncher(hosts: hosts, kinds: GlassShellSetupModel.tabOrder.filter(registered.contains))
    }
}

/// One machine under a service's heading.
private struct GlassActiveLauncherRow: View {
    let entry: GlassActiveLauncher.Entry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.machine)
                if let detail = entry.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.footnote)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

private struct GlassActiveLauncherButton: View {
    let model: GlassShellModel
    let section: GlassActiveLauncher.Section
    let entry: GlassActiveLauncher.Entry

    var body: some View {
        Button {
            model.connect(hostID: entry.hostID, endpointID: entry.endpointID)
        } label: {
            GlassActiveLauncherRow(entry: entry)
        }
        .accessibilityHint("Connects to this machine's \(section.title.lowercased())")
        .accessibilityIdentifier("active-launch-\(section.kind.rawValue)")
    }
}

private struct GlassActiveLauncherHeading: View {
    let section: GlassActiveLauncher.Section

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            GlassServiceIcon(GlassServicePresentation.symbol(for: section.kind))
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// The detail column's page when nothing is open: set like the library's overview, which is the
/// page beside it when no machine is chosen.
struct GlassActiveLauncherPage: View {
    static let title = "Nothing Is Open"

    let model: GlassShellModel
    let launcher: GlassActiveLauncher

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    #if !os(visionOS)
                    Text(Self.title).font(.largeTitle.bold())
                    #endif
                    Text("Choose a machine to connect to it. It appears under Active while the session is live.")
                        .foregroundStyle(.secondary)
                }
                ForEach(launcher.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        GlassActiveLauncherHeading(section: section).font(.headline)
                        VStack(spacing: 0) {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 14) }
                                GlassActiveLauncherButton(model: model, section: section, entry: entry)
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                        // The overview's tiles, so the two pages beside the library read as one.
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                    }
                }
            }
            .glassDetailPageInsets()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("active-launcher")
        .glassSpatialColumn(Self.title)
    }
}

/// The same, as sections of the Active list, where there is no detail column to hold the page.
struct GlassActiveLauncherSections: View {
    let model: GlassShellModel
    let launcher: GlassActiveLauncher

    var body: some View {
        ForEach(launcher.sections) { section in
            Section {
                ForEach(section.entries) { entry in
                    GlassActiveLauncherButton(model: model, section: section, entry: entry)
                        .foregroundStyle(.primary)
                        .selectionDisabled()
                }
            } header: {
                GlassActiveLauncherHeading(section: section)
            }
        }
    }
}
