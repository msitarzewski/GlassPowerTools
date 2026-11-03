//
//  GlassTabOverview.swift
//  Glass Power Tools — GlassShell
//
//  A window's overview of its tabs off the Mac (D99; the owner, 2026-11-03, on his iPhone and headset: "both seem
//  to be missing coverflow and the new expose"). The Mac's overview (D96) draws a window's tabs as its Show All
//  Windows does; off the Mac this draws them as All Windows draws its cards there (`GlassAllWindowsCard`: the
//  picture taken again each second, the coding agent's mark, the name over it), on the same plate and in the same
//  layout (`GlassAllWindowsLayout`), with a ring on the one selected for the arrow keys. As a carousel the same
//  tiles stand in `GlassCarouselRow`.
//
//  The capability says what each tab is (`GlassOverviewItem`); the window owns choosing, closing and moving them.
//

import SwiftUI

/// One tab of a window, as its overview draws it.
public struct GlassOverviewItem: Identifiable {
    public let id: UUID
    public let title: String
    /// Where it is: its repository and branch, its machine, its state when not connected.
    public let detail: String?
    public let detailTruncation: Text.TruncationMode
    /// For UI tests.
    public let identifier: String
    /// Its picture now, or the last it drew; nil before it has drawn one.
    public let picture: @MainActor () -> Image?
    /// The coding agent at work in it, as a template image.
    public let mark: @MainActor () -> Image?
    /// Shown where it has no picture.
    public let symbolName: String

    public init(id: UUID, title: String, detail: String?, detailTruncation: Text.TruncationMode = .tail,
                identifier: String, symbolName: String = "terminal",
                picture: @escaping @MainActor () -> Image?, mark: @escaping @MainActor () -> Image?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.detailTruncation = detailTruncation
        self.identifier = identifier
        self.symbolName = symbolName
        self.picture = picture
        self.mark = mark
    }

    /// As the carousel names it.
    public var carouselItem: GlassCarouselItem<UUID> {
        GlassCarouselItem(id: id, title: title, detail: detail, detailTruncation: detailTruncation,
                          identifier: identifier)
    }

    /// The items whose name or detail contains `filter`, ignoring case; all of them for an empty one. As Show All
    /// Windows' type-to-find narrows on the Mac (`MacTerminalExposeModel.filtered`).
    public static func filtered(_ items: [GlassOverviewItem], by filter: String) -> [GlassOverviewItem] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query) || item.detail?.localizedCaseInsensitiveContains(query) == true
        }
    }
}

/// A tab, as All Windows' card is drawn off the Mac — its picture with no plate behind it but its window's own
/// page (`backdrop`, an iPhone's or iPad's terminal theme), the agent's mark, its name over the bottom — and a ring
/// while it is selected. `captioned` false leaves the name to the carousel, which shows the front's under the row.
public struct GlassOverviewTile: View {
    let item: GlassOverviewItem
    let selected: Bool
    var backdrop: Color?
    var captioned = true
    /// Whether its picture is taken again each second: false for a reflection, which shows the tile's.
    var live = true
    @AppStorage(GlassShowAllWindows.blursPreviewsKey) private var blursPreviews = false
    @Environment(\.scenePhase) private var scenePhase

    public init(item: GlassOverviewItem, selected: Bool, backdrop: Color? = nil, captioned: Bool = true,
                live: Bool = true) {
        self.item = item
        self.selected = selected
        self.backdrop = backdrop
        self.captioned = captioned
        self.live = live
    }

    public var body: some View {
        ZStack {
            if let backdrop { backdrop }
            TimelineView(.animation(minimumInterval: 1, paused: !live || scenePhase != .active)) { _ in
                if let picture = item.picture() {
                    // The tile's width filled, its newest part kept: a phone's terminal is tall, and fitted
                    // whole it was a sliver (All Windows' cards, 2026-10-14).
                    Color.clear.overlay(alignment: .bottom) {
                        picture
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: blursPreviews ? GlassShowAllWindows.previewBlurRadius : 0)
                    }
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { GlassAllWindowsMark(image: item.mark()) }
        .overlay(alignment: .bottom) {
            if captioned {
                GlassAllWindowsCaption(title: item.title, detail: item.detail)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.16), lineWidth: selected ? 3 : 1)
        }
        .contentShape(.rect(cornerRadius: 10))
    }
}

/// A group's glass, its edge, and its name: All Windows' machine and a window's overview draw the same plate.
struct GlassAllWindowsGroupPlate: View {
    let title: String
    let symbolName: String
    let frames: GlassAllWindowsLayout.Group
    var targeted = false

    var body: some View {
        let origin = frames.frame.origin
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.14), lineWidth: targeted ? 3 : 1)
                }
            Label(title, systemImage: symbolName)
                .font(.headline)
                .lineLimit(1)
                .frame(width: frames.titleFrame.width, height: frames.titleFrame.height, alignment: .leading)
                .offset(x: frames.titleFrame.minX - origin.x, y: frames.titleFrame.minY - origin.y)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A window's tabs as a grid: one group, titled with the window's name, its tiles laid out as Show All Windows
/// lays out its own. It scrolls only when even the smallest tiles cannot fit, keeping the selection in sight.
public struct GlassOverviewGrid<Tile: View>: View {
    let title: String
    let symbolName: String
    let items: [GlassOverviewItem]
    let selection: UUID?
    let size: CGSize
    let tile: (GlassOverviewItem, CGSize) -> Tile

    public init(title: String, symbolName: String = "macwindow", items: [GlassOverviewItem], selection: UUID?,
                size: CGSize, @ViewBuilder tile: @escaping (GlassOverviewItem, CGSize) -> Tile) {
        self.title = title
        self.symbolName = symbolName
        self.items = items
        self.selection = selection
        self.size = size
        self.tile = tile
    }

    /// Where each tile stands, in reading order, for the arrow keys (`GlassAllWindowsNavigation`).
    public static func frames(count: Int, in size: CGSize) -> [CGRect] {
        GlassAllWindowsLayout(tileCounts: [count], in: size).groups.first?.tileFrames ?? []
    }

    public var body: some View {
        let layout = GlassAllWindowsLayout(tileCounts: [items.count], in: size)
        if layout.scrolls {
            ScrollViewReader { scroll in
                ScrollView {
                    canvas(layout)
                        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                }
                .onChange(of: selection) { _, id in
                    if let id { withAnimation(.easeInOut(duration: 0.18)) { scroll.scrollTo(id, anchor: .center) } }
                }
            }
        } else {
            canvas(layout)
        }
    }

    private func canvas(_ layout: GlassAllWindowsLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if let frames = layout.groups.first {
                let origin = frames.frame.origin
                ZStack(alignment: .topLeading) {
                    GlassAllWindowsGroupPlate(title: title, symbolName: symbolName, frames: frames)
                    ForEach(Array(zip(items, frames.tileFrames)), id: \.0.id) { item, frame in
                        tile(item, layout.tileSize)
                            .frame(width: layout.tileSize.width, height: layout.tileSize.height)
                            .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                            .id(item.id)
                    }
                }
                .frame(width: frames.frame.width, height: frames.frame.height)
                .position(x: frames.frame.midX, y: frames.frame.midY)
            }
        }
    }
}

/// What typing has narrowed the tabs to: a field rather than the Mac's type-anywhere, as a phone's keyboard
/// comes up for a field, and the headset's for one it is looking at.
public struct GlassOverviewFindField: View {
    @Binding var text: String
    let matches: Int

    public init(text: Binding<String>, matches: Int) {
        _text = text
        self.matches = matches
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find a terminal by name or folder", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.search)
                .accessibilityIdentifier("terminal-overview-find")
            if !text.isEmpty {
                Text(matches == 1 ? "1 terminal" : "\(matches) terminals")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: Capsule())
    }
}
