//
//  GlassLibraryPages.swift
//  Glass Power Tools — GlassShell
//
//  Two services side by side on an iPhone Duo (D93, 2026-10-31, the owner: "we should allow two of
//  any of our services in fold like a book mode. A terminal the left, a database on the right (or
//  whatever)"). Held like a book, or open flat on its side, the window shows two pages, one each side
//  of the fold, and each page is the phone as it is: a library, and whatever it opens, with its own
//  back button. A page is about 455 points wide, near the folded outer display's 466, where every
//  screen was checked (2026-10-18).
//
//  Each page is the whole stack the window draws — every capability's bootstrap around a library —
//  so no capability needs to know about pages. The capabilities' runtimes are shared; what one is
//  asked to open goes to the page in use (`glassPageIsFocused`), which is the page last touched.
//  Upright, folded, or stood like a laptop, the page in use fills the window and the other waits,
//  its sessions still open. A phone that never shows two pages never makes the second.
//

import SwiftUI
import GlassConnectionUI

extension EnvironmentValues {
    /// Whether this page is the one in use: what a capability is asked to open goes to it (D93).
    /// True everywhere but an iPhone Duo's other page.
    @Entry public var glassPageIsFocused: Bool = true
    /// Which page this is: 0, or 1 for an iPhone Duo's second (D93).
    @Entry public var glassPageIndex: Int = 0
}

/// Which page is in use, and whether there are two (D93): a finger landing on a page chooses it,
/// and so can Open on the Other Page. One window holds the pages, so one of these.
@MainActor @Observable
public final class GlassPageFocus {
    public static let shared = GlassPageFocus()
    /// The page in use: 0 or 1.
    public var focused = 0
    /// Two pages are on screen now, side by side (not one across both).
    public internal(set) var showsTwoPages = false
    /// There is room for two pages: held like a book, or open flat on its side.
    public internal(set) var hasRoomForTwo = false
    /// The page across both halves (Use Both Pages), the other waiting under it; nil for two pages.
    /// A tool alone uses the whole spread for its own two things: list and detail, code and its
    /// preview, tables and results, or a remote screen.
    public private(set) var spread: Int?
    /// The pages have traded sides (Swap Pages): the first page is drawn on the right.
    public private(set) var swapped = false

    /// Puts the other page in use, so what is opened next goes there.
    public func focusOtherPage() {
        focused = 1 - focused
    }

    /// The side page `page` is drawn on: 0 the left, 1 the right. Its own inverse: the page drawn
    /// on side `s` is `side(of: s)`.
    public func side(of page: Int) -> Int { swapped ? 1 - page : page }

    /// `page` across both halves, in use.
    public func useBothPages(_ page: Int) {
        spread = page
        focused = page
    }

    /// Two pages again, each where it was.
    public func useTwoPages() {
        spread = nil
    }

    /// The pages trade sides, each keeping what it shows.
    public func swapPages() {
        swapped.toggle()
    }

    /// Opens what `open` asks for on the page beside `page` (`openOnPage`). A session already
    /// shown on `page` moves.
    public func openBeside(_ page: Int, _ open: () -> Void) {
        openOnPage(1 - page, open)
    }

    /// Opens what `open` asks for on `page`. It puts away what it shows, so its library is there,
    /// and every tool's handling under it, and is put in use, so it is the page that carries the
    /// request out.
    public func openOnPage(_ page: Int, _ open: () -> Void) {
        putAwayRequests[page, default: 0] += 1
        focused = page
        open()
    }

    /// Asked of a page by `openBeside`: put away what it shows, back to its library.
    public private(set) var putAwayRequests: [Int: Int] = [:]

    /// The other page, drawn: the right half from the left page, the left half from the right.
    public func otherPageSymbol(from page: Int) -> String {
        side(of: page) == 0 ? "rectangle.righthalf.inset.filled" : "rectangle.lefthalf.inset.filled"
    }

    /// The page each session is shown on, by a key its tool chooses: a session is drawn on one
    /// page only, its view being one view. Asked for on the other page, it moves there: that
    /// page shows it, and this one, seeing it shown elsewhere, goes back to its library.
    public private(set) var pageShowing: [String: Int] = [:]

    /// `page` now shows the session `key`.
    public func show(_ key: String, on page: Int) {
        if pageShowing[key] != page { pageShowing[key] = page }
    }

    /// `page` no longer shows `key`; a page it has moved to keeps it.
    public func release(_ key: String, on page: Int) {
        if pageShowing[key] == page { pageShowing[key] = nil }
    }

    /// `page` shows `key`, which has since been shown on the other page: it has moved.
    public func hasMoved(_ key: String, from page: Int) -> Bool {
        pageShowing[key].map { $0 != page } ?? false
    }
}

/// Show on the Other Page (D93), drawn only while two pages are on screen: `show` brings a session
/// up on the page beside `page`, this view's own page unless another is named. One control for
/// every place that offers it.
public struct GlassShowOnOtherPageButton: View {
    private let page: Int?
    private let show: () -> Void
    @Environment(\.glassPageIndex) private var ownPage

    public init(from page: Int? = nil, show: @escaping () -> Void) {
        self.page = page
        self.show = show
    }

    public var body: some View {
        let pages = GlassPageFocus.shared
        if pages.showsTwoPages {
            let from = page ?? ownPage
            Button("Show on the Other Page", systemImage: pages.otherPageSymbol(from: from)) {
                pages.openBeside(from, show)
            }
        }
    }
}

extension View {
    /// Keeps `GlassPageFocus` told which page shows the session `key` (nil: none), and calls
    /// `putAway` to put this page back to its library (D93): `true` when the session has been shown
    /// on the other page instead, `false` when something is being opened here from the other page.
    /// Off an iPhone Duo there is one page, and neither happens.
    public func glassShownOnPage(_ key: String?, putAway: @escaping (_ moved: Bool) -> Void) -> some View {
        modifier(GlassShownOnPage(key: key, putAway: putAway))
    }
}

private struct GlassShownOnPage: ViewModifier {
    let key: String?
    let putAway: (Bool) -> Void
    @Environment(\.glassPageIndex) private var page
    /// The session this page has told `GlassPageFocus` it shows. Until it has, the record still
    /// names the page it came from, and the page it is going to would read that as moved away.
    @State private var claimed: String?
    private var focus: GlassPageFocus { .shared }

    func body(content: Content) -> some View {
        content
            .onChange(of: key, initial: true) { old, new in
                if let old, old != new { focus.release(old, on: page) }
                if let new { focus.show(new, on: page) }
                claimed = new
            }
            .onChange(of: key.map { $0 == claimed && focus.hasMoved($0, from: page) } ?? false) { _, hasMoved in
                if hasMoved { putAway(true) }
            }
            .onChange(of: focus.putAwayRequests[page] ?? 0) { _, _ in
                if key != nil { putAway(false) }
            }
            .onDisappear { if let key { focus.release(key, on: page) } }
    }
}

#if os(iOS)
import UIKit

public struct GlassLibraryPages<Page: View>: View {
    private let page: (Int) -> Page
    /// The page in use: the one last touched (`GlassPageFocus`).
    private var focus: GlassPageFocus { .shared }
    private var focused: Int { focus.focused }
    /// The second page, made the first time there is room for it, and kept after.
    @State private var secondPageMade = false
    /// The fold, read from the window as every Duo layout reads it (`GlassDeviceFold`).
    @State private var deviceFold: GlassDeviceFold?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(@ViewBuilder page: @escaping (Int) -> Page) {
        self.page = page
    }

    /// Two pages fit: an iPhone Duo (`GlassWindowPresentation.presentsInPages`) whose window is wide
    /// and on its side, as its inner display is held like a book or open flat (867 × 635 points
    /// inside the system's column, measured on the simulator 2026-10-31). An iPad has windows
    /// instead; a Pro Max on its side reports a regular width too, but at 440 points it is too
    /// short to share.
    static func showsTwoPages(size: CGSize, regularWidth: Bool) -> Bool {
        GlassWindowPresentation.presentsInPages && regularWidth
            && size.width > size.height && size.width >= 760 && size.height >= 560
    }

    #if DEBUG
    private static var marksPagesForUITests: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    #endif

    public var body: some View {
        GeometryReader { geometry in
            let two = Self.showsTwoPages(size: geometry.size, regularWidth: horizontalSizeClass == .regular)
            let originX = geometry.frame(in: .global).minX
            let split = split(in: geometry.size, originX: originX)
            let sideBySide = two && focus.spread == nil
            ZStack(alignment: .topLeading) {
                // One way for one page or two, so the first is the same view when the second
                // appears, and whatever it shows stays (a session opened folded, then unfolded).
                pages(in: geometry.size, split: split, two: two)
            }
            .background {
                // The middle of the fold, in the window: a touch left of it is on the page drawn
                // on the left.
                GlassPageTouches(divide: sideBySide ? originX + (split.0 + split.1) / 2 : nil) { side in
                    let touched = focus.side(of: side)
                    if focus.focused != touched { focus.focused = touched }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onChange(of: two, initial: true) { _, two in
                if two { secondPageMade = true }
                focus.hasRoomForTwo = two
            }
            .onChange(of: sideBySide, initial: true) { _, sideBySide in
                focus.showsTwoPages = sideBySide
            }
        }
        .glassDeviceFold($deviceFold)
    }

    /// Either side of the fold held like a book; open flat, either side of a hairline. In the
    /// view's own coordinates.
    private func split(in size: CGSize, originX: CGFloat) -> (CGFloat, CGFloat) {
        bookFold.map { ($0.minX - originX, $0.maxX - originX) } ?? (size.width / 2 - 0.5, size.width / 2 + 0.5)
    }

    /// The fold down the middle, held like a book, in the window's coordinates.
    private var bookFold: (minX: CGFloat, maxX: CGFloat)? {
        deviceFold.flatMap { $0.isAcross ? nil : ($0.globalFrame.minX, $0.globalFrame.maxX) }
    }

    /// The page drawn on `side` (0 the left, 1 the right), either side of the fold.
    private func pageFrame(side: Int, in size: CGSize, split: (CGFloat, CGFloat)) -> CGRect {
        side == 0 ? CGRect(x: 0, y: 0, width: split.0, height: size.height)
                  : CGRect(x: split.1, y: 0, width: size.width - split.1, height: size.height)
    }

    @ViewBuilder
    private func pages(in size: CGSize, split: (CGFloat, CGFloat), two: Bool) -> some View {
        let spread = two ? focus.spread : nil
        let sideBySide = two && spread == nil
        // The page on screen alone: across both halves, or the one in use where there is room for one.
        let alone = spread ?? focused
        ForEach(0..<(two || secondPageMade ? 2 : 1), id: \.self) { index in
            let shown = sideBySide || index == alone
            let frame = sideBySide ? pageFrame(side: focus.side(of: index), in: size, split: split) : CGRect(origin: .zero, size: size)
            page(index)
                .environment(\.glassPageIsFocused, focused == index)
                .environment(\.glassPageIndex, index)
                // A page is a phone's width: it lays itself out as one (the window says regular).
                // Across both halves it is the window's.
                .environment(\.horizontalSizeClass, sideBySide ? .compact : horizontalSizeClass)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                // The page waiting while there is room for one keeps its size and its sessions.
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
                .zIndex(index == alone ? 1 : 0)
        }
        if two {
            // Each page's handle, in the band above its bar, as an iPad window has: Use Both Pages,
            // Swap Pages, and back to two. Across both halves, over the first half, off the fold.
            ForEach(0..<2, id: \.self) { index in
                if spread == nil || spread == index {
                    let under = sideBySide ? pageFrame(side: focus.side(of: index), in: size, split: split)
                                           : pageFrame(side: 0, in: size, split: split)
                    GlassPageHandle(page: index)
                        .position(x: under.midX, y: GlassPageHandle.height / 2)
                        .zIndex(2)
                }
            }
        }
        #if DEBUG
        // UI tests only (`DuoPagesUITests`): where each page is, placed where it is rather than
        // moved there, which is how the tree reports it.
        if two && Self.marksPagesForUITests {
            ForEach(0..<2, id: \.self) { index in
                if spread == nil || spread == index {
                    let frame = sideBySide ? pageFrame(side: focus.side(of: index), in: size, split: split)
                                           : CGRect(origin: .zero, size: size)
                    Color.clear
                        .frame(width: frame.width, height: frame.height)
                        .accessibilityElement()
                        .accessibilityLabel("Page \(index + 1)")
                        .accessibilityIdentifier("glass-page-\(index)")
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        #endif
        if sideBySide {
            Rectangle()
                .fill(.separator)
                .frame(width: max(1, split.1 - split.0), height: size.height)
                .offset(x: split.0)
                .opacity(bookFold == nil ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// A page's handle (D93): three dots above its bar, as an iPad window has, with what can be done
/// with the pages.
private struct GlassPageHandle: View {
    static let height: CGFloat = 26
    let page: Int
    private var focus: GlassPageFocus { .shared }

    var body: some View {
        Menu {
            if focus.spread == nil {
                Button("Use Both Pages", systemImage: "rectangle") { focus.useBothPages(page) }
                Button("Swap Pages", systemImage: "arrow.left.arrow.right") { focus.swapPages() }
            } else {
                Button("Use Two Pages", systemImage: "rectangle.split.2x1") { focus.useTwoPages() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 60, height: Self.height)
                .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        // Grey, as an iPad window's three dots are, not the accent a menu's label takes.
        .tint(Color.secondary)
        .accessibilityLabel("Pages")
        .accessibilityIdentifier("glass-page-handle-\(page)")
    }
}

/// Which page a finger lands on, before anything on it acts: a recognizer on the window that
/// watches every touch and never claims one, so a terminal's or a desktop's own touches count too.
/// Decided by the fold, never by the pages' frames: a page is placed by an offset, and a frame read
/// outside it is where the page was before it moved, every touch on the second page missing it.
private struct GlassPageTouches: UIViewRepresentable {
    /// Where the first page ends and the second begins, in the window; nil while there is one.
    let divide: CGFloat?
    let onTouch: (Int) -> Void

    func makeUIView(context: Context) -> WatcherView { WatcherView() }

    func updateUIView(_ view: WatcherView, context: Context) {
        view.recognizer.divide = divide
        view.recognizer.onTouch = onTouch
    }

    final class WatcherView: UIView {
        let recognizer = Recognizer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }

    final class Recognizer: UIGestureRecognizer {
        var divide: CGFloat?
        var onTouch: ((Int) -> Void)?

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        convenience init() { self.init(target: nil, action: nil) }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            // A touch on the pages, not on a sheet or a menu drawn over both, which are not views
            // in the window's own view.
            if let divide, let touch = touches.first, let window = view as? UIWindow,
               let pages = window.rootViewController?.view, touch.view?.isDescendant(of: pages) == true {
                onTouch?(touch.location(in: window).x < divide ? 0 : 1)
            }
            // Never recognised: every touch goes on to what is under it.
            state = .failed
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
#endif
