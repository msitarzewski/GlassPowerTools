#if os(macOS)
import SwiftUI
import AppKit
import Testing
import GlassConnectionUI

/// Rows in the library's lists are one height, whatever their second line holds, so switching the
/// column between Connections, Workgroups, Keys and Projects moves nothing (2026-10-07: "between
/// views, row heights should not fluctuate — items should remain in consistent position"). Measured
/// on a real list in a transparent window: row heights are AppKit's to give.
@MainActor
@Suite("Library row consistency", .serialized)
struct GlassLibraryRowConsistencyTests {
    private func rowHeights(_ rows: [AnyView]) async -> [CGFloat] {
        let list = List(selection: .constant(Optional(0))) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in row.tag(index) }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = NSHostingView(rootView: list)
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<15 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        func tables(_ view: NSView) -> [NSTableView] { (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables) }
        guard let table = tables(window.contentView!).first else { return [] }
        return (0..<table.numberOfRows).map { table.rect(ofRow: $0).height }
    }

    @Test("service icons, a tab count with a colour, a line of text, and nothing: one height")
    func oneHeight() async {
        let heights = await rowHeights([
            AnyView(GlassLibraryConnectionRow(name: "alpha") {
                HStack(spacing: 4) {
                    GlassServiceIcon(.system("terminal"))
                    GlassServiceIcon(.circleStack)
                }
                .foregroundStyle(.secondary)
            } accessory: { Button("Connect") {} }),
            AnyView(GlassLibraryConnectionRow(name: "Workgroup", subtitle: "5 tabs", color: .blue)),
            AnyView(GlassLibraryConnectionRow(name: "Key") {
                Text("ED25519").font(GlassSpatialMetrics.rowSubtitleFont)
            } accessory: { EmptyView() }),
            AnyView(GlassLibraryConnectionRow(name: "This Mac") { EmptyView() } accessory: { Button("Connect") {} }),
        ])
        #expect(heights.count == 4, "\(heights)")
        #expect(Set(heights).count == 1, "every kind of row is one height: \(heights)")
    }
}
#endif
