//
//  TerminalOverviewStyle.swift
//  Glass Power Tools — GlassTerminal
//
//  How a terminal window's overview lays out its tabs: Show All Windows' grid, or the carousel (D97 on the Mac,
//  D99 everywhere). This device's choice, kept for every window. On the Mac the overview's own switch sets it; on
//  iPhone, iPad and Vision Pro the window's Terminal View menu does, as Grid or Carousel beside Tabs.
//

import SwiftUI

enum TerminalOverviewStyle: String, CaseIterable {
    case grid, carousel

    /// The Mac's key since D97, so a Mac keeps its choice.
    static let key = "com.glasspowertools.terminal.overviewStyle"

    var title: String {
        switch self {
        case .grid: "Grid"
        case .carousel: "Carousel"
        }
    }

    var symbolName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .carousel: "rectangle.stack"
        }
    }
}

/// What a terminal window off the Mac shows, as its Terminal View menu lists it: the window's tabs, or its overview
/// as a grid or a carousel. The overview is `LayoutPreset.OpeningView.grid` — a Workgroup opens in tabs or the
/// overview, as before — and which of the two it is drawn as is the device's `TerminalOverviewStyle`.
enum TerminalViewChoice: CaseIterable, Hashable {
    case tabs, grid, carousel

    init(_ presentation: LayoutPreset.OpeningView, style: TerminalOverviewStyle) {
        switch presentation {
        case .tabs: self = .tabs
        case .grid: self = style == .carousel ? .carousel : .grid
        }
    }

    var presentation: LayoutPreset.OpeningView { self == .tabs ? .tabs : .grid }

    /// The overview's style it asks for; nil for Tabs, which leaves the device's choice as it is.
    var style: TerminalOverviewStyle? {
        switch self {
        case .tabs: nil
        case .grid: .grid
        case .carousel: .carousel
        }
    }

    var title: String {
        switch self {
        case .tabs: "Tabs"
        case .grid: TerminalOverviewStyle.grid.title
        case .carousel: TerminalOverviewStyle.carousel.title
        }
    }

    /// A window with its tab strip, a grid of cards, a row of them.
    var symbolName: String {
        switch self {
        case .tabs: "rectangle.topthird.inset.filled"
        case .grid: TerminalOverviewStyle.grid.symbolName
        case .carousel: TerminalOverviewStyle.carousel.symbolName
        }
    }

    /// Where a pinch on Vision Pro's Terminal View goes when the window has no orb to become: the next, around.
    var next: Self {
        switch self {
        case .tabs: .grid
        case .grid: .carousel
        case .carousel: .tabs
        }
    }
}
