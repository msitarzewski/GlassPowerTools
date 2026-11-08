//
//  TerminalTypeAhead.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Type-ahead (D102, 2026-11-06): the suggestion a terminal shows after its cursor, the keys that take it, and the
//  grey text itself. What to suggest is the terminal capability's to decide (`GlassTerminal/TypeAhead`); this draws
//  it and hands back what to type when it is taken. `tasks/2026-11/2026-11-06_type-ahead.md`.
//

import Foundation
import SwiftTerm
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A command offered for the line being typed.
public struct TerminalTypeAheadSuggestion: Equatable, Sendable {
    /// The whole command.
    public let command: String
    /// What follows the text typed so far.
    public let suffix: String

    public init(command: String, suffix: String) {
        self.command = command
        self.suffix = suffix
    }
}

/// The keys that take a suggestion, as the terminal sends them.
public enum TerminalTypeAheadKeys {
    /// What to type in place of `outgoing` when it takes the suggestion whose rest is `suffix`: all of it for →
    /// and ⌃E (fish's keys), one word for ⌥→. Nil for any other key, which goes to the shell as it is.
    public static func replacement(for outgoing: [UInt8], suffix: String) -> String? {
        guard !suffix.isEmpty else { return nil }
        switch outgoing {
        case Self.right, Self.applicationRight, [0x05]:
            return suffix
        case Self.optionRight, Self.metaF, Self.escapeRight, Self.commandRight:
            return nextWord(of: suffix)
        default:
            return nil
        }
    }

    /// The suffix's next word, with the space or slash after it: what ⌥→ takes.
    public static func nextWord(of suffix: String) -> String {
        var word = ""
        var sawWord = false
        for character in suffix {
            let separator = character == " " || character == "/"
            if separator, sawWord {
                word.append(character)
                break
            }
            if !separator { sawWord = true }
            word.append(character)
        }
        return word
    }

    static let right: [UInt8] = [0x1B, 0x5B, 0x43]                         // ESC [ C
    static let applicationRight: [UInt8] = [0x1B, 0x4F, 0x43]              // ESC O C
    static let optionRight: [UInt8] = [0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x43] // ESC [ 1 ; 3 C
    static let commandRight: [UInt8] = [0x1B, 0x5B, 0x31, 0x3B, 0x39, 0x43] // ESC [ 1 ; 9 C
    static let metaF: [UInt8] = [0x1B, 0x66]                               // ESC f
    static let escapeRight: [UInt8] = [0x1B, 0x1B, 0x5B, 0x43]             // ESC ESC [ C
}

#if canImport(UIKit)
typealias TypeAheadPlatformView = UIView
typealias TypeAheadPlatformFont = UIFont
typealias TypeAheadPlatformColor = UIColor
#else
typealias TypeAheadPlatformView = NSView
typealias TypeAheadPlatformFont = NSFont
typealias TypeAheadPlatformColor = NSColor
#endif

/// The grey text after the cursor: one character to a cell, in the terminal's font, as fish draws its own.
@MainActor
final class TerminalTypeAheadGhostView: TypeAheadPlatformView {
    var text = "" { didSet { if text != oldValue { markForRedraw() } } }
    var font: TypeAheadPlatformFont?
    var color: TypeAheadPlatformColor = .gray
    var cellWidth: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if canImport(UIKit)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if !canImport(UIKit)
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    private func markForRedraw() {
        #if canImport(UIKit)
        setNeedsDisplay()
        #else
        needsDisplay = true
        #endif
    }

    override func draw(_ rect: CGRect) {
        guard let font else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        // Centred in the cell's height, as SwiftTerm places its glyphs.
        let lineHeight = font.ascender - font.descender
        let top = max(0, (bounds.height - lineHeight) / 2)
        for (index, character) in text.enumerated() {
            NSAttributedString(string: String(character), attributes: attributes)
                .draw(at: CGPoint(x: CGFloat(index) * cellWidth, y: top))
        }
    }
}

@MainActor
extension TerminalView {
    /// Shows `text` in grey from the cursor's cell, as much as fits before the row's end; nil or empty hides it.
    func showTypeAheadGhost(_ text: String?, columnsLeft: Int) {
        let ghost = subviews.lazy.compactMap { $0 as? TerminalTypeAheadGhostView }.first
        guard let text, !text.isEmpty, columnsLeft > 0, let cell = cursorCellFrame else {
            ghost?.removeFromSuperview()
            return
        }
        let shown = String(text.prefix(columnsLeft))
        let view = ghost ?? {
            let view = TerminalTypeAheadGhostView(frame: .zero)
            addSubview(view)
            return view
        }()
        view.font = font
        view.color = nativeForegroundColor.withAlphaComponent(0.42)
        view.cellWidth = cell.width
        view.text = shown
        view.frame = CGRect(x: cell.minX, y: cell.minY, width: cell.width * CGFloat(shown.count), height: cell.height)
    }
}
