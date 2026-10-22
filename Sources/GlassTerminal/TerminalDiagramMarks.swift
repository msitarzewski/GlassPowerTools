//
//  TerminalDiagramMarks.swift
//  Glass Power Tools — GlassTerminal
//
//  A mark beside each Mermaid diagram a terminal shows as text, which opens it drawn, over the
//  terminal (the owner, 2026-10-21: "an inline diagram icon would be amazing"). The diagrams are
//  found by `TerminalDiagramFinder` in what the terminal shows, looked at again as output settles,
//  as it scrolls and as it resizes; each mark stands just after its diagram's first line. The text
//  stays the program's own, so one that redraws loses nothing, and a mark goes when its text does.
//
//  Drawn by the editor's Mermaid, as its Markdown preview draws a diagram
//  (`GlassTerminalRuntime.diagramView`); a diagram Mermaid can't read says why there.
//

import SwiftUI
import GlassTerminalEmulator

/// The marks, laid over a terminal's own view, in its cells.
struct TerminalDiagramMarks: View {
    @ObservedObject var model: SwiftTermHostModel
    /// The diagram drawn; nil marks nothing.
    let draw: (@MainActor (String) -> AnyView)?

    var body: some View {
        let diagrams = model.diagrams
        let cell = diagrams.cellSize
        ZStack(alignment: .topLeading) {
            if let draw, cell.width > 0, cell.height > 0 {
                ForEach(diagrams.found) { diagram in
                    TerminalDiagramMark(diagram: diagram, cell: cell, draw: draw)
                        .offset(x: CGFloat(diagram.markColumn) * cell.width,
                                y: CGFloat(diagram.rows.lowerBound) * cell.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.refreshDiagrams() }
        // Once output has come to rest: a diagram being printed is marked when it is whole.
        .onChange(of: model.outputActivity.isActive) { _, active in
            if !active { model.refreshDiagrams() }
        }
        .onChange(of: model.scrollPosition) { _, _ in model.refreshDiagrams() }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in model.refreshDiagrams() }
    }
}

/// One diagram's mark: a pinch or a click shows it drawn.
private struct TerminalDiagramMark: View {
    let diagram: TerminalDiagram
    let cell: CGSize
    let draw: @MainActor (String) -> AnyView

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "flowchart")
                .font(.system(size: max(9, cell.height * 0.62), weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: cell.height * 1.7, height: cell.height)
                .background(.regularMaterial, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect()
        #endif
        .accessibilityLabel("Show Diagram")
        .accessibilityIdentifier("terminal-diagram-mark")
        // Last: before the accessibility modifiers it gave Vision Pro a second element of the same
        // name (as the Keys menu's did, 2026-10-21).
        .help("Show Diagram")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            #if os(iOS)
            // An iPhone shows it as a sheet, as wide as the screen, with Done to close it.
            NavigationStack {
                draw(diagram.source)
                    .navigationTitle("Diagram")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
            .frame(minWidth: 320, idealWidth: 640, minHeight: 300, idealHeight: 460)
            .presentationCompactAdaptation(.sheet)
            #else
            draw(diagram.source)
                .frame(width: 640, height: 460)
            #endif
        }
    }
}
