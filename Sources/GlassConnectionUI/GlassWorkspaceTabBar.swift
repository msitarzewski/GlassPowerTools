//
//  GlassWorkspaceTabBar.swift
//  Glass Power Tools — GlassConnectionUI
//
//  The tab strip, once, for every workspace that has one.
//
//  glassdb wrote it for SQL documents and table views (`DatabaseWorkspaceView.workspaceTabBar`) and
//  it is the shape the user asked the editor to use: *"The Open list in the left panel should
//  actually be tabs… use exactly the same UI as the tabs in the Database SQL editor."* Copying it
//  would have produced two strips that agree today and drift by the next change to either, so it
//  lives here and both call it.
//
//  What stays with the caller is everything that is not the strip: which tabs exist, what they are
//  called, what selecting one does. This owns capsules, spacing, the close button and the scroll.
//

import SwiftUI

/// One tab. `id` is whatever the workspace already uses to identify a surface.
public struct GlassWorkspaceTabItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let symbolName: String
    /// A permanent tab — an overview, a connection — has no close button and refuses ⌘W.
    public let isClosable: Bool
    /// Opened provisionally by a single click, and replaced by the next one. Drawn in italics,
    /// which is what every editor with this pattern does and what makes the difference legible
    /// without a second glyph in the strip.
    public let isProvisional: Bool
    /// What the tooltip and the accessibility hint say; the title when nil. The accessibility label
    /// is the title, the words on the tab: Voice Control acts on what it shows ("Tap orders"), and
    /// the editor's help is the file's folder, which made every tab from one folder sound the same
    /// to VoiceOver (2026-10-18, `AccessibilityAuditUITests`).
    public let help: String?
    /// The tab's accessibility identifier, for a test to find a kind of tab whatever its title.
    public let accessibilityIdentifier: String?

    public init(id: ID, title: String, symbolName: String, isClosable: Bool = true,
                isProvisional: Bool = false, help: String? = nil, accessibilityIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.isClosable = isClosable
        self.isProvisional = isProvisional
        self.help = help
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var helpText: String { help ?? title }
}

public struct GlassWorkspaceTabBar<ID: Hashable>: View {
    private let tabs: [GlassWorkspaceTabItem<ID>]
    private let selection: ID?
    private let accessibilityLabel: String
    private let onSelect: (ID) -> Void
    private let onClose: (ID) -> Void

    public init(tabs: [GlassWorkspaceTabItem<ID>], selection: ID?,
                accessibilityLabel: String = "Open workspaces",
                onSelect: @escaping (ID) -> Void,
                onClose: @escaping (ID) -> Void) {
        self.tabs = tabs
        self.selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.onSelect = onSelect
        self.onClose = onClose
    }

    public var body: some View {
        // **Tabs stay inside the safe area.** A scroll view whose edge lies on the safe area's edge
        // reaches past it, taking the inset beyond as room to scroll into. Nothing sat there until
        // the iPhone Duo: iOS puts the time, Wi-Fi and the toolbar's buttons in a column at the
        // right of its displays, and the selected tab sat under the clock, where scrolling to it
        // left it (2026-10-18). One point short of the edge the scroll view inherits no inset (the
        // editor's preview had the same cause, `GlassEditorPreviewPane`); the material behind still
        // spans the strip.
        HStack(spacing: 0) {
            // The selected tab in view, when the strip appears and whenever it changes: a workspace
            // opened on its last tab began with that tab off the end. After a turn, once the tabs
            // are laid out; asked at once, there is nothing yet to scroll to.
            ScrollViewReader { proxy in
                scroller
                    .task(id: selection) {
                        await Task.yield()
                        guard let selection else { return }
                        withAnimation(.snappy) { proxy.scrollTo(selection) }
                    }
            }
        }
        .padding(.horizontal, 1)
        // **A strip is as tall as its tabs.**
        //
        // A `ScrollView` accepts whatever height it is offered — it has no opinion of its own —
        // so in a column where everything else was flexible it took half the window and centred
        // the tabs in the middle of the empty space (reported 2026-09-17, with two tabs open and
        // the sidebar closed). `fixedSize` vertically is what asks it for its content's height
        // instead.
        .fixedSize(horizontal: false, vertical: true)
        // Inside the content safe area: the strip belongs to the canvas below the title bar and
        // must not extend upward over the window's own frost.
        .background(.regularMaterial, ignoresSafeAreaEdges: [])
        // **One line at any text size.** At the largest, tabs read "Ov…ew" (2026-10-19). A strip
        // of tabs is a bar, and like Apple's it stops growing past xxxLarge; a long press on a tab
        // shows its name whole in the Large Content Viewer.
        .glassBar()
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    let isSelected = tab.id == selection
                    HStack(spacing: 2) {
                        // **The whole capsule selects, not just the words.** The button used to wrap
                        // the label only, so the padding around it — most of a short tab — was dead
                        // space that swallowed the click. The label fills the button, the button
                        // takes its shape from the capsule, and the close control sits beside it
                        // with a hit target of its own.
                        Button {
                            onSelect(tab.id)
                        } label: {
                            Label(tab.title, systemImage: tab.symbolName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 200)
                                .font(tab.isProvisional ? .caption.italic() : .caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassWorkspaceTabControlTarget()
                        .accessibilityLabel(tab.isProvisional ? "\(tab.title), previewing" : tab.title)
                        .accessibilityHint(tab.helpText == tab.title ? "" : tab.helpText)
                        .accessibilityIdentifier(tab.accessibilityIdentifier ?? "")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        // Its name, not its icon alone: the icons say only what kind of tab it is.
                        .accessibilityShowsLargeContentViewer {
                            Label(tab.title, systemImage: tab.symbolName)
                        }

                        if tab.isClosable {
                            Button {
                                onClose(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .glassWorkspaceTabControlTarget()
                            .accessibilityLabel("Close \(tab.title)")
                            .accessibilityShowsLargeContentViewer {
                                Label("Close \(tab.title)", systemImage: "xmark")
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .id(tab.id)
                    .padding(.horizontal, 4)
                    // **The selected tab has to look selected.** `.regularMaterial` over a light
                    // window is very nearly the window, so on a Mac in Light mode there was no
                    // visible selection at all (reported 2026-09-17) — the material was doing its
                    // job, which is to disappear. A tint of the foreground colour reads on either
                    // appearance and against any theme the canvas is painted in.
                    .background(
                        isSelected ? AnyShapeStyle(Color.primary.opacity(0.12))
                                   : AnyShapeStyle(Color.clear),
                        in: Capsule()
                    )
                    .overlay {
                        if isSelected {
                            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .help(tab.helpText)
                    .contextMenu {
                        if tab.isClosable {
                            Button("Close Tab", systemImage: "xmark") { onClose(tab.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(accessibilityLabel)
    }
}

public extension View {
    /// A hit target a finger can land on, and a pointer does not have to aim at.
    @ViewBuilder
    func glassWorkspaceTabControlTarget() -> some View {
        #if os(macOS)
        frame(minWidth: 28, minHeight: 28)
        #else
        frame(minWidth: 44, minHeight: 44)
        #endif
    }
}
