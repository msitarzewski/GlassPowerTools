//
//  SwiftTermScale.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  D75 (the owner, 2026-10-16): "we need both a resize capability and a scale capability. For
//  example I may want a 120 x 40 terminal, but with a much smaller window." Resize, as it always
//  was: the window's size sets the rows and columns. Scale: the terminal keeps the rows and columns
//  it had when Scale was chosen ("If I've resized to 200 x 100, and choose to scale, keep that") and
//  its text grows and shrinks with the window.
//
//  **The drawing is scaled; the font never changes.** SwiftTerm's font setter re-grids the terminal
//  from its frame and soft-resets it every time (`resetFont` → `resize(cols:rows:)` →
//  `terminal.softReset()`, SwiftTerm 1.20.0 `AppleTerminalView.swift`), and its cells come in whole
//  points of height, so a font fitted to a window would re-grid the terminal on every frame of a
//  drag and still leave a band up to a point per row. Instead the terminal keeps its frame at its
//  grid's size at its own font — SwiftTerm's sums give the kept grid from it — and the view holding
//  it is scaled to fit the space, centred. Pointer, touch and drawing go through the scale as they
//  would any view's.
//

import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
import SwiftTerm
#endif

/// The rows and columns a terminal keeps under Scale, and what they come to at its own font.
public struct SwiftTermScaledGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    /// What the terminal draws, before it is scaled: the grid at its own font, in points. Its shape
    /// is the shape a window holding it keeps.
    public let size: CGSize

    public init(columns: Int, rows: Int, size: CGSize) {
        self.columns = columns
        self.rows = rows
        self.size = size
    }

    /// Width over height, as a window's shape is given.
    public var aspect: Double { Double(size.width / max(1, size.height)) }

    func keeps(columns: Int, rows: Int) -> Bool { self.columns == columns && self.rows == rows }
}

/// Where a scaled terminal goes, kept to rules a test can read.
enum SwiftTermScaleLayout {
    /// The terminal's frame for a grid: its cells, what SwiftTerm keeps beside them (the Mac's
    /// scroller), and half a point more, so SwiftTerm's `Int(width / cell)` can't lose a column to
    /// rounding when a cell's width is not a whole number of points.
    static func contentSize(cell: CGSize, columns: Int, rows: Int, reservedWidth: CGFloat = 0) -> CGSize {
        CGSize(width: cell.width * CGFloat(columns) + reservedWidth + 0.5,
               height: cell.height * CGFloat(rows) + 0.5)
    }

    /// Under Scale, ⌘+, ⌘− and ⌘0 size the window rather than the font, which can't change without
    /// re-gridding the terminal: the terminal's part of the window becomes `content` at the scale
    /// asked for — `factor` times the scale it has now, or its font's own size (1) for nil — and the
    /// window around it keeps the rest. Nil for a scale too far from now to be meant (> 20 times).
    static func zoomedWindow(window: CGSize, space: CGSize, content: CGSize, factor: CGFloat?) -> CGSize? {
        guard let now = fit(content, in: space)?.scale else { return nil }
        let scale = factor.map { now * $0 } ?? 1
        guard scale.isFinite, scale > 0, scale / now < 20, now / scale < 20 else { return nil }
        let chrome = CGSize(width: max(0, window.width - space.width), height: max(0, window.height - space.height))
        return CGSize(width: (content.width * scale + chrome.width).rounded(),
                      height: (content.height * scale + chrome.height).rounded())
    }

    /// The scale that fits all of `content` in `space` keeping its shape, and where its top-left
    /// corner goes there: centred, so the space over is shared equally either side.
    static func fit(_ content: CGSize, in space: CGSize) -> (scale: CGFloat, origin: CGPoint)? {
        guard content.width > 0, content.height > 0, space.width > 0, space.height > 0,
              content.width.isFinite, content.height.isFinite, space.width.isFinite, space.height.isFinite
        else { return nil }
        let scale = min(space.width / content.width, space.height / content.height)
        return (scale, CGPoint(x: (space.width - content.width * scale) / 2,
                               y: (space.height - content.height * scale) / 2))
    }
}

#if os(macOS)
/// A Mac terminal's place in its pane (D75). Under Resize the terminal fills it, as it always did.
/// Under Scale this view's bounds are scaled — AppKit draws, hit-tests and converts events through
/// them — so the terminal keeps its grid's frame at its own font while it is drawn to fit the pane.
/// Never the terminal's own bounds: SwiftTerm takes its grid from its frame. AppKit gives the
/// terminal's layer the scale it is shown at (`contentsScale` 2 × 0.504 = 1.008 measured, macOS
/// 27.2), so its text is drawn for the pixels it covers, not drawn large and shrunk as a picture.
@MainActor
final class MacTerminalScaleView: NSView {
    let terminalView: TerminalView
    /// Scale was asked for; the grid is taken once the terminal has been laid out in a window.
    private var wantsScaling = false
    private(set) var kept: SwiftTermScaledGrid?
    /// Told when the kept grid, or its size at the terminal's font, changes; nil when Scale ends.
    var onScaledGridChange: ((SwiftTermScaledGrid?) -> Void)?

    init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        terminalView.autoresizingMask = []
        addSubview(terminalView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setScaling(_ enabled: Bool) {
        guard enabled != wantsScaling else { return }
        wantsScaling = enabled
        if !enabled { kept = nil }
        layoutTerminal()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutTerminal()
    }

    override func layout() {
        super.layout()
        layoutTerminal()
    }

    /// After the terminal's font changes: its cells did, so what the grid comes to did.
    func cellsChanged() { layoutTerminal() }

    /// ⌘+, ⌘− and ⌘0 under Scale (`SwiftTermScaleLayout.zoomedWindow`): the window resized, its
    /// top-left kept, within its screen. False when not scaling or in full screen.
    func zoomWindow(by factor: CGFloat?) -> Bool {
        guard let kept, kept.size != .zero, let window, let content = window.contentView,
              !window.styleMask.contains(.fullScreen),
              let target = SwiftTermScaleLayout.zoomedWindow(window: content.frame.size, space: frame.size,
                                                             content: kept.size, factor: factor) else { return false }
        var size = NSSize(width: max(target.width, window.contentMinSize.width),
                          height: max(target.height, window.contentMinSize.height))
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let chrome = window.frameRect(forContentRect: .zero).size
            size.width = min(size.width, visible.width - chrome.width)
            size.height = min(size.height, visible.height - chrome.height)
        }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: true)
        return true
    }

    private func layoutTerminal() {
        if wantsScaling, kept == nil, window != nil, frame.width > 0, frame.height > 0 {
            // Laid out as Resize lays it out first, so the grid taken is the window's own.
            fill()
            let terminal = terminalView.getTerminal()
            if terminal.cols > 0, terminal.rows > 0 {
                kept = SwiftTermScaledGrid(columns: terminal.cols, rows: terminal.rows, size: .zero)
            }
        }
        guard let grid = kept, let cell = cellSize, frame.width > 0, frame.height > 0 else {
            fill()
            return
        }
        let content = SwiftTermScaleLayout.contentSize(cell: cell, columns: grid.columns, rows: grid.rows,
                                                       reservedWidth: reservedScrollerWidth)
        guard let fit = SwiftTermScaleLayout.fit(content, in: frame.size) else { return fill() }
        let shown = NSSize(width: frame.width / fit.scale, height: frame.height / fit.scale)
        setBoundsSize(shown)
        setBoundsOrigin(NSPoint(x: -(shown.width - content.width) / 2, y: -(shown.height - content.height) / 2))
        if terminalView.frame != NSRect(origin: .zero, size: content) {
            terminalView.frame = NSRect(origin: .zero, size: content)
        }
        let reported = SwiftTermScaledGrid(columns: grid.columns, rows: grid.rows, size: content)
        if reported != kept {
            kept = reported
            onScaledGridChange?(reported)
        }
    }

    /// Resize: the terminal fills the pane, unscaled.
    private func fill() {
        let wasScaled = bounds.size != frame.size || bounds.origin != .zero
        if bounds.size != frame.size { setBoundsSize(frame.size) }
        if bounds.origin != .zero { setBoundsOrigin(.zero) }
        if terminalView.frame != bounds { terminalView.frame = bounds }
        if wasScaled, !wantsScaling { onScaledGridChange?(nil) }
    }

    /// One cell at the terminal's font: its grid's frame (`getOptimalFrameSize`, the scroller
    /// SwiftTerm keeps beside it taken off) over its grid.
    private var cellSize: CGSize? {
        let terminal = terminalView.getTerminal()
        guard terminal.cols > 0, terminal.rows > 0 else { return nil }
        let optimal = terminalView.getOptimalFrameSize().size
        let cell = CGSize(width: (optimal.width - reservedScrollerWidth) / CGFloat(terminal.cols),
                          height: optimal.height / CGFloat(terminal.rows))
        return cell.width > 0 && cell.height > 0 ? cell : nil
    }

    /// SwiftTerm's own sum (`reservedScrollerWidth`, private there): its scroller's width, unless
    /// the scroller is hidden.
    private var reservedScrollerWidth: CGFloat {
        let scroller = terminalView.subviews.first { $0 is NSScroller }
        guard let scroller, !scroller.isHidden else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: terminalView.scrollerStyle)
    }
}
#endif
