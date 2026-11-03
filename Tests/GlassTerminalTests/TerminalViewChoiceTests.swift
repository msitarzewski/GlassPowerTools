import Testing
@testable import GlassTerminal

/// A terminal window's Terminal View off the Mac (D99): Tabs, Grid or Carousel, where Grid and Carousel are the
/// window's overview drawn the device's way. A saved Workgroup still opens in tabs or the overview, as before.
@Suite("A terminal window's Terminal View")
struct TerminalViewChoiceTests {
    @Test("Tabs, Grid and Carousel, in that order, each named and drawn")
    func choices() {
        #expect(TerminalViewChoice.allCases == [.tabs, .grid, .carousel])
        #expect(TerminalViewChoice.allCases.map(\.title) == ["Tabs", "Grid", "Carousel"])
        #expect(Set(TerminalViewChoice.allCases.map(\.symbolName)).count == 3)
    }

    @Test("What the window shows is its presentation and the device's style: the overview is Grid or Carousel by it")
    func readFromPresentationAndStyle() {
        #expect(TerminalViewChoice(.tabs, style: .grid) == .tabs)
        #expect(TerminalViewChoice(.tabs, style: .carousel) == .tabs, "tabs whatever the overview's style")
        #expect(TerminalViewChoice(.grid, style: .grid) == .grid)
        #expect(TerminalViewChoice(.grid, style: .carousel) == .carousel)
    }

    @Test("Choosing sets the presentation, and the style for Grid or Carousel; Tabs leaves the style as it was")
    func written() {
        #expect(TerminalViewChoice.tabs.presentation == .tabs && TerminalViewChoice.tabs.style == nil)
        #expect(TerminalViewChoice.grid.presentation == .grid && TerminalViewChoice.grid.style == .grid)
        #expect(TerminalViewChoice.carousel.presentation == .grid && TerminalViewChoice.carousel.style == .carousel)
        // Read back as chosen, for every choice and either style kept before.
        for choice in TerminalViewChoice.allCases {
            for kept in TerminalOverviewStyle.allCases {
                #expect(TerminalViewChoice(choice.presentation, style: choice.style ?? kept) == choice)
            }
        }
    }

    @Test("A pinch on Vision Pro's Terminal View goes round all three")
    func next() {
        #expect(TerminalViewChoice.tabs.next == .grid)
        #expect(TerminalViewChoice.grid.next == .carousel)
        #expect(TerminalViewChoice.carousel.next == .tabs)
    }

    @Test("The overview's style is kept under the Mac's key, so a Mac keeps its choice")
    func keptUnderTheMacsKey() {
        #expect(TerminalOverviewStyle.key == "com.glasspowertools.terminal.overviewStyle")
        #expect(TerminalOverviewStyle(rawValue: "carousel") == .carousel)
    }
}
