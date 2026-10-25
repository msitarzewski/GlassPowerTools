//
//  TmuxUnusedAreaView.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  The space beyond a tmux pane's size, dotted as tmux dots it, while another client of the session
//  has the window (the owner, 2026-10-22: "dotted"). A session open on the Mac and the headset has
//  one size, the size of the device that switched to it last; on the other the terminal shows the
//  pane at that size (`TmuxControlAction.showGrid`) and this marks what lies past it, as tmux did
//  for each device before its terminals became control-mode clients (D83). Draws only; touches,
//  clicks and the pointer go through to the terminal.
//

import CoreGraphics

/// Where the dots go: a dot centred in every cell of `bounds` that lies outside `used`.
enum TmuxUnusedArea {
    static func dotCentres(in bounds: CGSize, used: CGSize, cell: CGSize) -> [CGPoint] {
        guard cell.width > 0, cell.height > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        var centres: [CGPoint] = []
        var y: CGFloat = 0
        while y + cell.height / 2 < bounds.height {
            var x: CGFloat = 0
            while x + cell.width / 2 < bounds.width {
                let centre = CGPoint(x: x + cell.width / 2, y: y + cell.height / 2)
                if centre.x > used.width || centre.y > used.height { centres.append(centre) }
                x += cell.width
            }
            y += cell.height
        }
        return centres
    }

    /// A dot's diameter for a cell: small, as tmux's middle dot is.
    static func dotSize(for cell: CGSize) -> CGFloat { max(1.5, min(cell.width, cell.height) * 0.14) }
}

#if canImport(UIKit)
import UIKit

final class TmuxUnusedAreaView: UIView {
    /// The pane's part, from the top left; nothing is dotted while it is nil.
    var used: CGSize? { didSet { isHidden = used == nil; setNeedsDisplay() } }
    var cell: CGSize = .zero { didSet { if cell != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let used else { return }
        UIColor.secondaryLabel.withAlphaComponent(0.45).setFill()
        let size = TmuxUnusedArea.dotSize(for: cell)
        for centre in TmuxUnusedArea.dotCentres(in: bounds.size, used: used, cell: cell) {
            UIBezierPath(ovalIn: CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)).fill()
        }
    }
}
#elseif canImport(AppKit)
import AppKit

final class TmuxUnusedAreaView: NSView {
    /// The pane's part, from the top left; nothing is dotted while it is nil.
    var used: CGSize? { didSet { isHidden = used == nil; needsDisplay = true } }
    var cell: CGSize = .zero { didSet { if cell != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let used else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        let size = TmuxUnusedArea.dotSize(for: cell)
        for centre in TmuxUnusedArea.dotCentres(in: bounds.size, used: used, cell: cell) {
            NSBezierPath(ovalIn: NSRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)).fill()
        }
    }
}
#endif
