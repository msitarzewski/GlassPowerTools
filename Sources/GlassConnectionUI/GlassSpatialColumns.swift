//
//  GlassSpatialColumns.swift
//  Glass Power Tools — GlassConnectionUI
//
//  **Our own sidebar and content columns on the headset** (W33). The owner, on the Vision Pro
//  (2026-10-10): "The whole point of Glass Power Tools is Glass. Opacity is essential transparency
//  is essential", and asked whether Connections, the database, the editor and Files should be
//  completely clear at Glass 0 by replacing Apple's sidebar layout: "Yes, all four".
//
//  **Why not the system's split view.** On visionOS 27 a `NavigationSplitView` or `NavigationStack`
//  in a plain window always draws its own system glass behind every column — UIKit's columns
//  report `preferredContainerBackgroundStyle = .automatic` — and no public modifier removes it
//  (D60, W28's trace). Without a navigation container the window is completely clear apart from
//  what it draws, so these windows draw their glass themselves (`GlassSpatialWindowGlass`, at the
//  window's Glass) and lay their columns out here.
//
//  **What this gives back, and what it cannot.** A sidebar of fixed width that a toggle hides and
//  shows with an animation; a header at the top of every column, in visionOS's navigation-title
//  style, at the height of the system's bar so every column's title is level; a Back control and a
//  push transition for a column that goes deeper; a search field where `.searchable` has no bar to
//  live in; and headings, labels and a keyboard order for VoiceOver and a keyboard. It cannot give
//  the system split view's animated collapse, column resizing or its rotor landmarks — the
//  trade-offs the owner accepted.
//
//  **Where the controls go.** What lived at `.navigation`, `.topBarLeading`, `.primaryAction` and
//  `.secondaryAction` has no bar to appear in: such items silently vanish. The column headers are
//  their home. A window's own controls (the sidebar toggle, the way back to Connections, the ⚡)
//  reach whichever header its content column draws through the environment
//  (`glassSpatialColumnChrome`), so the content that owns the column draws the header and the
//  window still decides what leads and ends it. Bottom toolbar ornaments
//  (`ToolbarItemGroup(placement: .bottomOrnament)`) still work without a container and stay where
//  they are.
//
//  Mac, iPad and iPhone keep their navigation containers: nothing here is used off the headset
//  except the measurements, which are plain numbers so they can be tested on a Mac.
//

import SwiftUI

/// The measurements of our own columns on the headset.
public enum GlassSpatialColumns {
    /// The sidebar's narrowest, ideal and widest, as the system split view's sidebar had them in
    /// these windows (`GlassConnectionLibrary`, 320–460, ideal 360).
    public static let sidebarMinimumWidth: CGFloat = 320
    public static let sidebarIdealWidth: CGFloat = 360
    public static let sidebarMaximumWidth: CGFloat = 460

    /// The sidebar's width in a window `windowWidth` wide: the ideal, and narrower toward the
    /// minimum only when the window is too narrow for the content to keep most of it (three
    /// eighths of the window: 360 in Connections' first 960 points). It never grows past the
    /// ideal, because nothing here resizes a column.
    public static func sidebarWidth(windowWidth: CGFloat) -> CGFloat {
        guard windowWidth.isFinite, windowWidth > 0 else { return sidebarIdealWidth }
        return min(sidebarIdealWidth, max(sidebarMinimumWidth, (windowWidth * 0.375).rounded()))
    }

    /// The header's height: the system's navigation bar in these windows, measured over the
    /// Connections and database windows in the visionOS 27 simulator (W33), with the title centred
    /// in it. Every column's header is this tall, so their titles stand level.
    public static let headerHeight: CGFloat = 92

    /// Where a content column's title starts from the column's leading edge when nothing leads it
    /// — where visionOS sets a detail column's navigation title
    /// (`GlassWindowShape.spatialColumnTitleInset`, 6d132e9).
    public static var titleInset: CGFloat { GlassWindowShape.spatialColumnTitleInset }

    /// Where a sidebar's title starts: a few points further in than a content column's, as the
    /// system's sidebar sets "All Connections" (28.5 points from the window's edge against 24.8
    /// for "Your Library" from the column's, measured in the visionOS 27 simulator, W33).
    public static let sidebarTitleInset: CGFloat = 28

    /// The room between controls in a header, and between the last control and the title.
    public static let headerSpacing: CGFloat = 12

    /// Where a header's first control starts from the column's edge, and where its last ends.
    public static let headerControlInset: CGFloat = 18

    /// The edge a screen pushed onto a column comes in from: the trailing edge going deeper or
    /// across, the leading edge going back — the way a navigation stack moves.
    public static func pushEdge(fromDepth old: Int, toDepth new: Int) -> Edge {
        new < old ? .leading : .trailing
    }
}

/// A Back control for a column that has gone deeper: what it goes back to, and how.
public struct GlassSpatialBack {
    /// The screen it returns to, as its own title says it: "Collections", a folder's name.
    public let title: String
    public let action: @MainActor () -> Void

    public init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.action = action
    }
}

/// A column's search, where `.searchable` has no navigation bar to put its field in.
public struct GlassSpatialSearch {
    public let text: Binding<String>
    public let prompt: String
    public let accessibilityIdentifier: String?
    public let onSubmit: (@MainActor () -> Void)?

    public init(text: Binding<String>, prompt: String, accessibilityIdentifier: String? = nil,
                onSubmit: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.prompt = prompt
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSubmit = onSubmit
    }
}

/// One place a column's title menu offers: Files' folders above the one open.
public struct GlassSpatialMenuItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let action: @MainActor () -> Void

    public init(id: String, title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

public extension View {
    /// **This view as one of our columns, on the headset**: a header with `title` (and the window's
    /// own controls, `glassSpatialColumnChrome`), a search field when `search` is given, and the
    /// view beneath. Off the headset it is the view itself: there a navigation container draws the
    /// title, the search field and the toolbar from the view's own modifiers.
    ///
    /// - Parameters:
    ///   - subtitle: a second line under the title, for a column that stands alone (Files' path).
    ///   - back: the way back, for a column that has gone deeper.
    ///   - titleMenu: places the title's menu offers (Files: the folders above this one); with
    ///     none, the title is plain text.
    ///   - trailing: the column's own controls, at the header's trailing edge.
    @ViewBuilder
    func glassSpatialColumn<Trailing: View>(
        _ title: String,
        subtitle: String? = nil,
        back: GlassSpatialBack? = nil,
        search: GlassSpatialSearch? = nil,
        titleMenu: [GlassSpatialMenuItem] = [],
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        #if os(visionOS)
        GlassSpatialColumn(title, subtitle: subtitle, back: back, search: search,
                           titleMenu: titleMenu, trailing: trailing) { self }
        #else
        self
        #endif
    }
}

#if os(visionOS)
// MARK: - The headset

extension EnvironmentValues {
    /// The sidebar the content column's header shows and hides, set by `GlassSpatialSplitView` on
    /// its content column only.
    @Entry var glassSpatialSidebarVisibility: Binding<NavigationSplitViewVisibility>? = nil
    /// The window's own controls for the header its content column draws.
    @Entry var glassSpatialColumnChrome: GlassSpatialColumnChrome? = nil
    /// Inside a `GlassSpatialSplitView`'s sidebar, whose title sits a little further in.
    @Entry var glassSpatialIsSidebar = false
    /// Inside one of our columns rather than a navigation container's: a list there draws no
    /// grouped platter of its own (`glassSpatialList()`).
    @Entry public var glassSpatialInColumn = false
}

/// A window's own controls, for the header of the column they belong to: what leads it (the way
/// back to Connections) and what ends it (the ⚡). Set with `glassSpatialColumnChrome(leading:trailing:)`.
public struct GlassSpatialColumnChrome {
    /// Nil when the window puts nothing before the title.
    fileprivate let leading: (() -> AnyView)?
    fileprivate let trailing: () -> AnyView
}

public extension View {
    /// The window's own controls for the header of the column this view is: `leading` before the
    /// title, after the sidebar toggle; `trailing` last, after the column's own.
    func glassSpatialColumnChrome<Leading: View, Trailing: View>(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        environment(\.glassSpatialColumnChrome,
                    GlassSpatialColumnChrome(leading: { AnyView(leading()) }, trailing: { AnyView(trailing()) }))
    }

    /// The window's own controls for the end of this column's header, with nothing before its title.
    func glassSpatialColumnChrome<Trailing: View>(@ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        environment(\.glassSpatialColumnChrome,
                    GlassSpatialColumnChrome(leading: nil, trailing: { AnyView(trailing()) }))
    }

    /// One screen of a column that pushes and pops, as a navigation stack does: a new `key` slides
    /// in from the trailing edge going deeper (a larger `depth`) and from the leading edge going
    /// back, and the screen it replaces fades where it stands. Animated by the change itself.
    func glassSpatialPush<Key: Hashable>(_ key: Key, depth: Int) -> some View {
        modifier(GlassSpatialPushModifier(key: key, depth: depth))
    }
}

/// **The sidebar and content columns** of a window that draws its own glass. The sidebar has a
/// fixed width (`GlassSpatialColumns.sidebarWidth`) and slides out and back when `visibility` is
/// `.detailOnly` and back; the content column takes the rest and carries the toggle in its header.
public struct GlassSpatialSplitView<Sidebar: View, Content: View>: View {
    @Binding private var visibility: NavigationSplitViewVisibility
    private let showsToggle: Bool
    private let sidebar: Sidebar
    private let content: Content

    /// - Parameter showsToggle: false where the sidebar could only ever be empty — an editor with
    ///   no project — so no control offers it.
    public init(visibility: Binding<NavigationSplitViewVisibility>, showsToggle: Bool = true,
                @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder content: () -> Content) {
        _visibility = visibility
        self.showsToggle = showsToggle
        self.sidebar = sidebar()
        self.content = content()
    }

    private var showsSidebar: Bool { visibility != .detailOnly }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if showsSidebar {
                    sidebar
                        .environment(\.glassSpatialSidebarVisibility, nil)
                        .environment(\.glassSpatialColumnChrome, nil)
                        .environment(\.glassSpatialIsSidebar, true)
                        .frame(width: GlassSpatialColumns.sidebarWidth(windowWidth: proxy.size.width))
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        // One group for VoiceOver, where the system's split view gave a landmark.
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Sidebar")
                }
                content
                    .environment(\.glassSpatialSidebarVisibility, showsToggle ? $visibility : nil)
                    .environment(\.glassSpatialIsSidebar, false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Content")
            }
        }
        #if DEBUG
        // Screenshots only: `--demo-sidebar-hidden` in a `--ui-testing` run hides every window's
        // sidebar, for a capture of the toggle's other state. After a moment, because the database
        // and the editor set their own first visibility as they appear.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-testing"), arguments.contains("--demo-sidebar-hidden") else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { visibility = .detailOnly }
        }
        #endif
    }
}

/// **One column**: its header — the window's controls, the way back, the title, the column's
/// own controls — a search field when it has one, and its content beneath. Draw it with
/// `glassSpatialColumn(_:…)` so the same call means nothing off the headset.
public struct GlassSpatialColumn<Trailing: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let back: GlassSpatialBack?
    private let search: GlassSpatialSearch?
    private let titleMenu: [GlassSpatialMenuItem]
    private let trailing: Trailing
    private let content: Content

    public init(_ title: String, subtitle: String? = nil, back: GlassSpatialBack? = nil,
                search: GlassSpatialSearch? = nil, titleMenu: [GlassSpatialMenuItem] = [],
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.search = search
        self.titleMenu = titleMenu
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSpatialColumnHeader(title, subtitle: subtitle, back: back, titleMenu: titleMenu,
                                     trailing: { trailing })
            if let search {
                GlassSpatialSearchField(search)
                    .padding(.horizontal, GlassSpatialColumns.headerControlInset)
                    .padding(.bottom, 10)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.glassSpatialInColumn, true)
        }
    }
}

/// **A column's header**, as visionOS draws a navigation bar: the sidebar toggle and the window's
/// leading controls, the way back, the title in the bar's large-title style, then the column's
/// own controls and the window's trailing ones, in circular buttons. Every header is
/// `GlassSpatialColumns.headerHeight` tall with the title centred, so two columns' titles stand
/// level whatever their controls.
public struct GlassSpatialColumnHeader<Trailing: View>: View {
    @Environment(\.glassSpatialSidebarVisibility) private var sidebar
    @Environment(\.glassSpatialColumnChrome) private var chrome
    @Environment(\.glassSpatialIsSidebar) private var isSidebar

    private let title: String
    private let subtitle: String?
    private let back: GlassSpatialBack?
    private let titleMenu: [GlassSpatialMenuItem]
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, back: GlassSpatialBack? = nil,
                titleMenu: [GlassSpatialMenuItem] = [],
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.titleMenu = titleMenu
        self.trailing = trailing()
    }

    /// Whether anything stands before the title: then the controls start at the control inset and
    /// the title follows them; otherwise the title starts where visionOS sets one.
    private var hasLeadingControls: Bool { sidebar != nil || chrome?.leading != nil || back != nil }

    public var body: some View {
        HStack(spacing: GlassSpatialColumns.headerSpacing) {
            // The sidebar toggle first, then the window's way back, as the database's split view
            // ordered its bar, then this column's own way back.
            if let sidebar {
                GlassSidebarToggle(columnVisibility: sidebar)
                    .keyboardShortcut("s", modifiers: [.control, .command])
            }
            chrome?.leading?()
            if let back {
                Button(action: back.action) {
                    Label(back.title, systemImage: "chevron.backward")
                }
                .help("Back to \(back.title)")
                .accessibilityLabel("Back")
                .accessibilityValue(back.title)
                .accessibilityIdentifier("glass-column-back")
                .keyboardShortcut("[", modifiers: .command)
            }
            // A column with nothing to name (an empty detail) still has a header, for the
            // window's controls; it has no heading.
            if !title.isEmpty {
                titleView
                    .padding(.leading, hasLeadingControls ? 4 : 0)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            trailing
            chrome?.trailing()
        }
        // Icons only, in the system's own button shape: a capsule round an icon is the circle
        // the navigation bar draws, and a button with words (Select, Done) keeps its capsule.
        .labelStyle(.iconOnly)
        .padding(.leading, hasLeadingControls ? GlassSpatialColumns.headerControlInset
                 : isSidebar ? GlassSpatialColumns.sidebarTitleInset : GlassSpatialColumns.titleInset)
        .padding(.trailing, GlassSpatialColumns.headerControlInset)
        .frame(height: GlassSpatialColumns.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var titleView: some View {
        if titleMenu.isEmpty {
            titleText
                .accessibilityAddTraits(.isHeader)
        } else {
            // The places above this one, as the system's title menu offered them (W16).
            Menu {
                ForEach(titleMenu) { item in
                    Button(item.title, systemImage: item.systemImage) { item.action() }
                        .labelStyle(.titleAndIcon)
                }
            } label: {
                HStack(spacing: 6) {
                    titleText
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Shows the folders above this one")
            .accessibilityIdentifier("glass-column-title-menu")
        }
    }

    /// The title in the navigation bar's large-title style — measured against the system's
    /// "All Connections", 1.22 times `.title` (W33) — with its subtitle beneath when it has one.
    /// Only a column that stands alone has a subtitle (Files' path), so no title beside it has to
    /// stay level with it.
    private var titleText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { $0.isEmpty ? title : "\(title), in \($0)" } ?? title)
    }
}

/// A search field for a column, where `.searchable` has nowhere to draw one, shaped as the
/// system's sidebar search field is on the headset: a capsule in the system's field fill, the
/// magnifying glass and the prompt inside it in the secondary style, and a clear button once
/// there is something to clear. The rounded-border text field style draws a much darker field
/// on visionOS with a prompt that can barely be read (W33, compared in the simulator).
public struct GlassSpatialSearchField: View {
    private let search: GlassSpatialSearch
    @FocusState private var focused: Bool

    public init(_ search: GlassSpatialSearch) {
        self.search = search
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(search.prompt, text: search.text, prompt: Text(search.prompt).foregroundStyle(.secondary))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { search.onSubmit?() }
                .onKeyPress(.escape) {
                    guard !search.text.wrappedValue.isEmpty else { return .ignored }
                    search.text.wrappedValue = ""
                    return .handled
                }
                .accessibilityIdentifier(search.accessibilityIdentifier ?? "glass-column-search")
            if !search.text.wrappedValue.isEmpty {
                Button("Clear text", systemImage: "xmark.circle.fill") {
                    search.text.wrappedValue = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.quaternary, in: .capsule)
        // A tap anywhere in the capsule reaches the field, as the system's does.
        .contentShape(.capsule)
        .onTapGesture { focused = true }
        .hoverEffect(.highlight)
    }
}

private struct GlassSpatialPushModifier<Key: Hashable>: ViewModifier {
    let key: Key
    let depth: Int
    /// The depth on screen before this change, so the edge a new screen comes in from is known
    /// while it is inserted.
    @State private var shownDepth: Int?

    func body(content: Content) -> some View {
        let edge = GlassSpatialColumns.pushEdge(fromDepth: shownDepth ?? depth, toDepth: depth)
        ZStack {
            content
                .id(key)
                .transition(.asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                                        removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.3), value: key)
        .onChange(of: depth, initial: true) { _, new in shownDepth = new }
    }
}
#endif
