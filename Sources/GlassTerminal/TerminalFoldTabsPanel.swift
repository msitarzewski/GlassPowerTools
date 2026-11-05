//
//  TerminalFoldTabsPanel.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal window's tabs below an iPhone Duo's fold (D93, 2026-10-31): stood like a laptop with
//  the keyboard put away, the deck's panel shows the window's tabs as live pictures, the others
//  first. Tap one to bring it to the top half. With two tabs the other fills the panel, so a log
//  followed in one (Watch Log File) stays in sight while the other is worked in; with more they
//  sit in two columns, as Apple asks grids on the Duo to (even columns).
//

#if os(iOS)
import SwiftUI
import GlassShell
import GlassTerminalEmulator

/// The tabs of the window a terminal is in, handed down by the window (`VisionTerminalWorkgroupView`).
struct TerminalFoldTabs {
    let sessions: [TerminalSession]
    let selected: UUID?
    let select: @MainActor (UUID) -> Void
    let newTab: @MainActor () -> Void
}

private struct TerminalFoldTabsKey: EnvironmentKey {
    static let defaultValue: TerminalFoldTabs? = nil
}

extension EnvironmentValues {
    var terminalFoldTabs: TerminalFoldTabs? {
        get { self[TerminalFoldTabsKey.self] }
        set { self[TerminalFoldTabsKey.self] = newValue }
    }
}

struct TerminalFoldTabsPanel: View {
    let tabs: TerminalFoldTabs

    /// The others first, then the one in the top half.
    private var ordered: [TerminalSession] {
        tabs.sessions.filter { $0.id != tabs.selected } + tabs.sessions.filter { $0.id == tabs.selected }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: tabs.sessions.count <= 2 ? 1 : 2)
    }

    var body: some View {
        // Drawn again each second: a picture is asked for and arrives just after (`previewImage`).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ordered) { session in
                        card(session)
                    }
                    newTab
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("terminal-fold-tabs")
    }

    private func card(_ session: TerminalSession) -> some View {
        let front = session.id == tabs.selected
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let rang = session.terminalHostModel.bellNotice.isUnseen
        return Button {
            tabs.select(session.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let picture = session.terminalHostModel.previewImage(maxPixelWidth: 900) {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(TerminalWorkgroupOpening.label(session, on: .tabBar))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(front ? "In the top half" : session.server.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 10, style: .continuous))
                .padding(8)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(front ? Color.accentColor : .white.opacity(0.12), lineWidth: front ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        // Its bell rang out of sight: an orange glow beneath, as beneath a tab (`GlassBell`, 2026-11-03).
        .glassBellGlow(rang, cornerRadius: 16, spread: 12, outside: true)
        .accessibilityLabel(TerminalWorkgroupOpening.label(session, on: .tabBar))
        .accessibilityValue([rang ? GlassBell.accessibilityWord : nil, front ? "In the top half" : session.server.name]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(front ? .isSelected : [])
        .accessibilityIdentifier("terminal-fold-tab-\(session.id.uuidString)")
    }

    private var newTab: some View {
        Button {
            tabs.newTab()
        } label: {
            Label("New Terminal Tab", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal-fold-new-tab")
    }
}
#endif
