//
//  SchemaDiagramView.swift
//  Glass Power Tools — GlassDatabase
//
//  The schema diagram (D43): one database's tables as cards, and its foreign keys as connectors
//  between them, read live from the connection. This file holds what every platform shares — the
//  request, the document that loads and lays out, the card — and the 2D canvas the Mac, iPad and
//  iPhone show. The headset's volume is `SchemaDiagramVolume.swift`.
//

import SwiftUI
import GlassDBKit
import GlassShell

/// What a diagram window was opened for.
struct SchemaDiagramRequest: Identifiable, Hashable, Sendable {
    var id = UUID()
    var sessionID: UUID
    var database: String
    /// A table to select on opening ("Show in Diagram" on a table).
    var focusTable: String?
}

// MARK: - Document

/// Loading, the layout and the selection, shared by the canvas and the volume.
@MainActor @Observable
final class SchemaDiagramDocument {
    enum Phase: Equatable {
        case idle
        case loading(done: Int, total: Int)
        case loaded
        case failed(String)
    }

    let database: String
    private(set) var phase: Phase = .idle
    private(set) var diagram: SchemaDiagram?
    /// Card centres, in points, for the current `keysOnly` sizes.
    var positions: [String: CGPoint] = [:]
    /// Card centres for the volume, in points, centred on the origin.
    private(set) var volumePositions: [String: SIMD3<Double>] = [:]
    /// Bumped whenever a new layout lands, so the volume knows to rebuild its connectors.
    private(set) var layoutVersion = 0
    var selection: String?
    var keysOnly = false {
        didSet { if keysOnly != oldValue { relayout() } }
    }

    init(database: String, focusTable: String?) {
        self.database = database
        self.selection = focusTable
    }

    func load(connection: (any DatabaseConnection)?) async {
        guard let connection else {
            phase = .failed("This connection has closed. Open the database again, then show its diagram.")
            return
        }
        phase = .loading(done: 0, total: 0)
        do {
            let loaded = try await SchemaDiagramLoader.load(connection: connection, database: database) { done, total in
                await MainActor.run { self.phase = .loading(done: done, total: total) }
            }
            diagram = loaded
            if let selection, loaded.table(named: selection) == nil { self.selection = nil }
            relayout()
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("The schema could not be read. \(error.localizedDescription)")
        }
    }

    func columns(of table: SchemaDiagram.Table) -> [SchemaDiagram.Column] {
        keysOnly ? table.keyColumns : table.columns
    }

    func cardSize(of table: SchemaDiagram.Table) -> CGSize {
        SchemaDiagramMetrics.cardSize(rows: columns(of: table).count)
    }

    /// Lays the cards out again, for the plane and the volume, from the current card sizes.
    func relayout() {
        guard let diagram else { return }
        let nodes = diagram.tables.map { table in
            let size = cardSize(of: table)
            return SchemaDiagramLayout.Node(id: table.name,
                                            size: SIMD3(size.width, size.height, size.width * 0.35))
        }
        let edges = diagram.relationships.map { ($0.fromTable, $0.toTable) }
        let plane = SchemaDiagramLayout.layout(nodes: nodes, edges: edges, space: .plane,
                                               gap: SchemaDiagramMetrics.gap)
        let margin = SchemaDiagramMetrics.margin
        positions = plane.mapValues { CGPoint(x: $0.x + margin, y: $0.y + margin) }
        #if os(visionOS)
        volumePositions = SchemaDiagramLayout.layout(nodes: nodes, edges: edges, space: .volume,
                                                     gap: SchemaDiagramMetrics.gap)
        #endif
        layoutVersion += 1
    }

    /// The whole canvas, margins included.
    var canvasSize: CGSize {
        guard let diagram else { return .zero }
        var maxX: CGFloat = 0, maxY: CGFloat = 0
        for table in diagram.tables {
            guard let center = positions[table.name] else { continue }
            let size = cardSize(of: table)
            maxX = max(maxX, center.x + size.width / 2)
            maxY = max(maxY, center.y + size.height / 2)
        }
        return CGSize(width: maxX + SchemaDiagramMetrics.margin, height: maxY + SchemaDiagramMetrics.margin)
    }

    /// The tables lit while `selection` is set: it and every table a key joins it to.
    var litTables: Set<String>? {
        guard let selection, let diagram else { return nil }
        return diagram.neighbors(of: selection).union([selection])
    }

    func isLit(_ relationship: SchemaDiagram.Relationship) -> Bool? {
        guard let selection else { return nil }
        return relationship.fromTable == selection || relationship.toTable == selection
    }

    var summary: String {
        guard let diagram else { return "" }
        var parts = ["\(diagram.tables.count) table\(diagram.tables.count == 1 ? "" : "s")",
                     "\(diagram.relationships.count) relationship\(diagram.relationships.count == 1 ? "" : "s")"]
        if diagram.omittedTableCount > 0 {
            parts.append("first \(SchemaDiagramLoader.tableLimit) of \(diagram.tables.count + diagram.omittedTableCount) shown")
        }
        if diagram.unresolvedRelationshipCount > 0 {
            parts.append("\(diagram.unresolvedRelationshipCount) to tables not shown")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Card

enum SchemaDiagramMetrics {
    static let cardWidth: CGFloat = 240
    static let headerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 22
    static let footer: CGFloat = 6
    static let gap: Double = 56
    static let margin: CGFloat = 48

    static func cardSize(rows: Int) -> CGSize {
        CGSize(width: cardWidth, height: headerHeight + CGFloat(max(rows, 0)) * rowHeight + footer)
    }

    /// The y of a row's middle, from the card's top edge.
    static func rowMidY(_ index: Int) -> CGFloat { headerHeight + CGFloat(index) * rowHeight + rowHeight / 2 }
}

/// One table: its name, then a row per column with its key marks and type.
struct SchemaTableCard: View {
    let table: SchemaDiagram.Table
    let columns: [SchemaDiagram.Column]
    var isSelected = false
    var isDimmed = false
    var isMatch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "tablecells")
                    .foregroundStyle(.secondary)
                Text(table.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: SchemaDiagramMetrics.headerHeight)
            .background(.quaternary.opacity(0.6))
            ForEach(columns, id: \.name) { column in
                HStack(spacing: 6) {
                    keyMark(column)
                        .frame(width: 16)
                    Text(column.name)
                        .font(.callout.monospaced())
                        .fontWeight(column.isPrimaryKey ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(column.type.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .frame(height: SchemaDiagramMetrics.rowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(width: SchemaDiagramMetrics.cardWidth,
               height: SchemaDiagramMetrics.cardSize(rows: columns.count).height, alignment: .top)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected || isMatch ? Color.accentColor : Color.secondary.opacity(0.35),
                              lineWidth: isSelected ? 2.5 : (isMatch ? 2 : 1))
        }
        .clipShape(.rect(cornerRadius: 10))
        .opacity(isDimmed ? 0.35 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(table.name), \(columns.count) column\(columns.count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private func keyMark(_ column: SchemaDiagram.Column) -> some View {
        if column.isPrimaryKey {
            Image(systemName: "key.fill").foregroundStyle(.yellow).font(.caption)
                .accessibilityLabel("Primary key")
        } else if column.isForeignKey {
            Image(systemName: "arrow.turn.up.right").foregroundStyle(Color.accentColor).font(.caption)
                .accessibilityLabel("Foreign key")
        } else {
            Color.clear
        }
    }
}

// MARK: - Canvas (Mac, iPad, iPhone)

struct SchemaDiagramView: View {
    let request: SchemaDiagramRequest
    let openTable: (String) -> Void

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var document: SchemaDiagramDocument
    @State private var zoom: CGFloat = 1
    /// Where the canvas is scrolled, so a zoom can keep the point under the pointer still.
    @State private var scrollPosition = ScrollPosition()
    @State private var contentOffset: CGPoint = .zero
    /// The scroll view's limits: how far the canvas can scroll, including the band under the
    /// toolbar. At rest a Mac window's canvas sits at about y = -52, and clamping to zero made
    /// every pan from the top jump up before it moved (2026-09-30).
    @State private var scrollBounds = CGRect.zero
    /// Bumped by Zoom to Fit, so the canvas scrolls back to its top-left corner.
    @State private var fitRequest = 0
    /// Where the canvas was scrolled when a pan began; non-nil while one is under way.
    @State private var panStart: CGPoint?
    /// ⌥-Space is held: every drag pans, even one that starts on a card.
    @State private var panKeyHeld = false
    /// A zoom in progress, shown by scaling the finished picture about `liveAnchor` and applied
    /// for real once input pauses: re-laying the canvas out and scrolling on every scroll-wheel
    /// step made ⌘-scroll stutter (owner, 2026-09-30: "a little debounce could be useful").
    @State private var liveScale: CGFloat = 1
    @State private var liveAnchor: CGPoint = .zero
    @State private var zoomCommit: Task<Void, Never>?
    @State private var dragStart: [String: CGPoint] = [:]
    @State private var searchText = ""
    /// The visible area, for Zoom to Fit.
    @State private var viewport: CGSize = .zero
    @State private var hasFitted = false

    init(request: SchemaDiagramRequest, openTable: @escaping (String) -> Void) {
        self.request = request
        self.openTable = openTable
        _document = State(initialValue: SchemaDiagramDocument(database: request.database,
                                                              focusTable: request.focusTable))
    }

    var body: some View {
        content
            .navigationTitle(request.database)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            // The database window's glass, not a plate of its own: the same see-through canvas
            // and blur the workspace draws from Settings, over a window made non-opaque the same
            // way (owner, 2026-09-30: "our transparency rules need to follow here, too").
            .modifier(DatabaseWorkspaceBackground(material: .ultraThinMaterial,
                                                  fillOpacity: settingsManager.windowOpacity,
                                                  blurAmount: settingsManager.blurBackground))
            #if os(macOS)
            .background { MacDatabaseWorkspaceWindowReader(opensSidebarInitially: false) }
            #endif
            .searchable(text: $searchText, prompt: "Find a table")
            .onSubmit(of: .search) { selectFirstMatch() }
            .task { await reload() }
    }

    @ViewBuilder private var content: some View {
        switch document.phase {
        case .idle, .loading:
            loadingView
        case .failed(let message):
            ContentUnavailableView {
                Label("No Diagram", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await reload() } }
            }
        case .loaded:
            if let diagram = document.diagram, !diagram.tables.isEmpty {
                canvas(diagram)
                    .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            } else {
                ContentUnavailableView("No Tables", systemImage: "tablecells",
                                       description: Text("\(request.database) has no tables to draw."))
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            if case .loading(let done, let total) = document.phase, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .frame(maxWidth: 280)
                Text("Reading tables… \(done) of \(total)")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Reading the schema…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text(document.summary)
            Spacer()
            if let selection = document.selection {
                Text(selection).fontWeight(.medium)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }

    private func canvas(_ diagram: SchemaDiagram) -> some View {
        let size = document.canvasSize
        let lit = document.litTables
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return ScrollViewReader { reader in ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // The empty canvas: a click clears the selection. On the Mac, pressing and
                // dragging here pans (there is no finger to scroll with), with the grab hand.
                Color.clear
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .gesture(panGesture(clearsSelectionOnClick: true))
                    #else
                    .onTapGesture { document.selection = nil }
                    #endif
                Canvas { context, _ in
                    drawConnectors(diagram, in: &context)
                }
                .allowsHitTesting(false)
                ForEach(diagram.tables) { table in
                    let center = document.positions[table.name] ?? .zero
                    SchemaTableCard(table: table, columns: document.columns(of: table),
                                    isSelected: document.selection == table.name,
                                    isDimmed: lit.map { !$0.contains(table.name) } ?? false,
                                    isMatch: !query.isEmpty && table.name.localizedCaseInsensitiveContains(query))
                        .position(center)
                        .gesture(dragGesture(for: table.name))
                        .onTapGesture(count: 2) { openTable(table.name) }
                        .onTapGesture { document.selection = table.name }
                        .contextMenu {
                            Button("Open Table", systemImage: "tablecells") { openTable(table.name) }
                            Button("Select Related Tables", systemImage: "point.3.connected.trianglepath.dotted") {
                                document.selection = table.name
                            }
                        }
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
            // One invisible marker per card, at its centre in the zoomed canvas, for scrolling to
            // a table: a positioned card's own frame is the whole canvas, so it cannot be a target.
            .overlay(alignment: .topLeading) {
                // The id belongs to the 1-point view, placed by `position` after it: a padded
                // marker's frame ran from the canvas corner to the card, and "centre it" centred
                // halfway there (2026-09-30).
                ForEach(diagram.tables) { table in
                    let center = document.positions[table.name] ?? .zero
                    Color.clear.frame(width: 1, height: 1)
                        .id(table.name)
                        .position(x: center.x * zoom, y: center.y * zoom)
                }
            }
        }
        .scaleEffect(liveScale, anchor: UnitPoint(x: viewport.width > 0 ? liveAnchor.x / viewport.width : 0.5,
                                                  y: viewport.height > 0 ? liveAnchor.y / viewport.height : 0.5))
        .clipped()
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, offset in contentOffset = offset }
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            let insets = geometry.contentInsets
            let low = CGPoint(x: -insets.leading, y: -insets.top)
            let high = CGPoint(x: max(low.x, geometry.contentSize.width - geometry.containerSize.width + insets.trailing),
                               y: max(low.y, geometry.contentSize.height - geometry.containerSize.height + insets.bottom))
            return CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
        } action: { _, bounds in scrollBounds = bounds }
        #if os(macOS)
        // The grab hand for every drag on the diagram — a pan or a card — and the open hand while
        // ⌥-Space is held. Set once here, so crossing a card mid-drag does not drop it.
        .pointerStyle(panStart != nil || !dragStart.isEmpty ? .grabActive : (panKeyHeld ? .grabIdle : nil))
        #endif
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        #if os(macOS)
        // ⌘-scroll zooms, about the pointer, as it does in Preview and Maps.
        .background {
            MacCommandScrollZoom(onZoom: { delta, precise, point in
                let step = precise ? 1.01 : 1.1
                previewZoom(by: CGFloat(pow(step, Double(delta))), at: point)
                scheduleZoomCommit()
            }, onPanKey: { held in panKeyHeld = held })
        }
        // While ⌥-Space is held, a layer over everything takes the drag, so it pans even when
        // it starts on a card, and shows the open hand until the drag closes it.
        .overlay {
            if panKeyHeld {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture(clearsSelectionOnClick: false))
                    .pointerStyle(panStart != nil ? .grabActive : .grabIdle)
            }
        }
        #endif
        .onChange(of: fitRequest) { _, _ in
            withAnimation { scrollPosition.scrollTo(point: .zero) }
        }
        // Open fitted to the window, on the selected table when there is one: at 100% a
        // twelve-table shop showed two cards and not the one asked for (2026-09-30).
        .task(id: "\(document.layoutVersion)-\(viewport.width > 0)") {
            guard !hasFitted, viewport.width > 0 else { return }
            hasFitted = true
            zoom = fittedZoom(readable: true)
            if let selection = document.selection {
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation { reader.scrollTo(selection, anchor: .center) }
            }
        }
        .onChange(of: document.selection) { _, selection in
            guard let selection else { return }
            withAnimation { reader.scrollTo(selection, anchor: .center) }
        }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoomCommit?.cancel()
                    if liveScale == 1 { liveAnchor = value.startLocation }
                    liveScale = clampedLiveScale(value.magnification)
                }
                .onEnded { _ in commitZoom() }
        )
    }

    private func dragGesture(for name: String) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart[name] ?? document.positions[name] ?? .zero
                dragStart[name] = start
                document.positions[name] = CGPoint(x: max(0, start.x + value.translation.width),
                                                   y: max(0, start.y + value.translation.height))
            }
            .onEnded { _ in dragStart[name] = nil }
    }

    // MARK: Connectors

    private func drawConnectors(_ diagram: SchemaDiagram, in context: inout GraphicsContext) {
        for relationship in diagram.relationships {
            guard let from = diagram.table(named: relationship.fromTable),
                  let to = diagram.table(named: relationship.toTable),
                  let fromCenter = document.positions[from.name],
                  let toCenter = document.positions[to.name] else { continue }
            let fromSize = document.cardSize(of: from), toSize = document.cardSize(of: to)
            let fromY = anchorY(table: from, columns: relationship.fromColumns, center: fromCenter, size: fromSize)
            let toY = anchorY(table: to, columns: relationship.toColumns, center: toCenter, size: toSize)
            let lit = document.isLit(relationship)
            let color: Color = lit == true ? .accentColor : .secondary
            let opacity: Double = lit == false ? 0.15 : (lit == true ? 1 : 0.6)
            let width: CGFloat = lit == true ? 2.5 : 1.5

            var path = Path()
            let start: CGPoint, end: CGPoint, startOut: CGFloat, endOut: CGFloat
            if relationship.isSelfReference {
                let x = fromCenter.x + fromSize.width / 2
                start = CGPoint(x: x, y: fromY); end = CGPoint(x: x, y: toY)
                startOut = 1; endOut = 1
                let bulge = CGFloat(40)
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: x + bulge, y: fromY),
                              control2: CGPoint(x: x + bulge, y: toY == fromY ? toY + 20 : toY))
            } else {
                // Side by side: leave from the side facing the other card, enter on the side
                // facing back. Stacked (the cards overlap left to right): leave and enter on the
                // same side, as a bracket, rather than an S through both cards.
                let stacked = abs(toCenter.x - fromCenter.x) < (fromSize.width + toSize.width) / 2
                if stacked {
                    startOut = toCenter.x >= fromCenter.x ? 1 : -1; endOut = startOut
                } else {
                    startOut = toCenter.x >= fromCenter.x ? 1 : -1; endOut = -startOut
                }
                start = CGPoint(x: fromCenter.x + startOut * fromSize.width / 2, y: fromY)
                end = CGPoint(x: toCenter.x + endOut * toSize.width / 2, y: toY)
                let reach = stacked ? max(40, abs(end.x - start.x) + 40) : max(40, abs(end.x - start.x) / 2)
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: start.x + startOut * reach, y: start.y),
                              control2: CGPoint(x: end.x + endOut * reach, y: end.y))
            }
            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: width)

            // Crow's foot at the referencing ("many") end, a bar at the referenced ("one") end.
            var marks = Path()
            let foot: CGFloat = 9
            marks.move(to: CGPoint(x: start.x + startOut * foot, y: start.y))
            marks.addLine(to: CGPoint(x: start.x, y: start.y - 5))
            marks.move(to: CGPoint(x: start.x + startOut * foot, y: start.y))
            marks.addLine(to: CGPoint(x: start.x, y: start.y + 5))
            marks.move(to: CGPoint(x: end.x + endOut * 6, y: end.y - 5))
            marks.addLine(to: CGPoint(x: end.x + endOut * 6, y: end.y + 5))
            context.stroke(marks, with: .color(color.opacity(opacity)), lineWidth: width)
        }
    }

    /// The y of the first named column's row, or the header's middle when it is not shown.
    private func anchorY(table: SchemaDiagram.Table, columns: [String], center: CGPoint, size: CGSize) -> CGFloat {
        let top = center.y - size.height / 2
        let shown = document.columns(of: table)
        if let first = columns.first, let index = shown.firstIndex(where: { $0.name == first }) {
            return top + SchemaDiagramMetrics.rowMidY(index)
        }
        return top + SchemaDiagramMetrics.headerHeight / 2
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $document.keysOnly) {
                Label("Keys Only", systemImage: "key")
            }
            .help("Show only primary and foreign key columns")
            Button { zoom(to: zoom / 1.25, keeping: viewportCenter) } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out")
            Button { zoom(to: zoom * 1.25, keeping: viewportCenter) } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in")
            Button { zoom = fittedZoom(readable: false); fitRequest += 1 } label: {
                Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Fit the whole diagram in the window")
            Button {
                if let selection = document.selection { openTable(selection) }
            } label: {
                Label("Open Table", systemImage: "tablecells")
            }
            .disabled(document.selection == nil)
            .help("Open the selected table")
            Button { Task { await reload() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Read the schema again")
        }
    }

    #if os(macOS)
    /// Pans the canvas with the pointer: the scroll offset moves opposite to the drag. A press
    /// that never moves is a click, and on the empty canvas a click clears the selection.
    private func panGesture(clearsSelectionOnClick: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = panStart ?? contentOffset
                panStart = start
                scrollPosition.scrollTo(point: clampedOffset(CGPoint(x: start.x - value.translation.width,
                                                                     y: start.y - value.translation.height)))
            }
            .onEnded { value in
                panStart = nil
                if clearsSelectionOnClick, hypot(value.translation.width, value.translation.height) < 3 {
                    document.selection = nil
                }
            }
    }
    #endif

    private static let zoomRange: ClosedRange<CGFloat> = 0.05...3

    /// Scales the picture by `factor` about `point`, within the zoom range. The first step of a
    /// burst fixes the anchor, so the point under the pointer stays put for the whole gesture.
    private func previewZoom(by factor: CGFloat, at point: CGPoint) {
        if liveScale == 1 { liveAnchor = point }
        liveScale = clampedLiveScale(liveScale * factor)
    }

    private func clampedLiveScale(_ scale: CGFloat) -> CGFloat {
        min(Self.zoomRange.upperBound / zoom, max(Self.zoomRange.lowerBound / zoom, scale))
    }

    private func scheduleZoomCommit() {
        zoomCommit?.cancel()
        zoomCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            commitZoom()
        }
    }

    /// The real zoom and scroll, in one update with no animation, so the picture does not jump.
    private func commitZoom() {
        zoomCommit?.cancel()
        zoomCommit = nil
        guard liveScale != 1 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let target = zoom * liveScale
            liveScale = 1
            zoom(to: target, keeping: liveAnchor)
        }
    }

    private var viewportCenter: CGPoint { CGPoint(x: viewport.width / 2, y: viewport.height / 2) }

    /// Zooms to `value`, keeping the canvas point under `anchor` (a point in the visible area)
    /// where it is, so zooming goes toward what you are looking at, not the top-left corner.
    private func zoom(to value: CGFloat, keeping anchor: CGPoint) {
        let old = zoom
        let new = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value))
        guard new != old else { return }
        zoom = new
        let target = CGPoint(x: (contentOffset.x + anchor.x) * new / old - anchor.x,
                             y: (contentOffset.y + anchor.y) * new / old - anchor.y)
        // The limits after the zoom: the content is `new / old` times the size, the insets are not.
        let insetLow = scrollBounds.origin
        let size = document.canvasSize
        let high = CGPoint(x: max(insetLow.x, size.width * new - viewport.width - insetLow.x),
                           y: max(insetLow.y, size.height * new - viewport.height - insetLow.y))
        scrollPosition.scrollTo(point: CGPoint(x: min(high.x, max(insetLow.x, target.x)),
                                               y: min(high.y, max(insetLow.y, target.y))))
    }

    /// An offset kept within what the scroll view can actually show.
    private func clampedOffset(_ point: CGPoint) -> CGPoint {
        guard scrollBounds != .zero else { return point }
        return CGPoint(x: min(scrollBounds.maxX, max(scrollBounds.minX, point.x)),
                       y: min(scrollBounds.maxY, max(scrollBounds.minY, point.y)))
    }

    /// The zoom that shows the whole canvas, never above 100%. On opening, `readable` also keeps
    /// it large enough to read the names, and a schema too large for that opens on its
    /// selection. Zoom to Fit is not held to that: it fits, whatever size that takes (it used to
    /// stop at the same floor, and on a large schema appeared to do nothing, 2026-09-30).
    private func fittedZoom(readable: Bool) -> CGFloat {
        let size = document.canvasSize
        guard size.width > 0, size.height > 0, viewport.width > 0 else { return 1 }
        let fit = min(1, viewport.width / size.width, viewport.height / size.height)
        return max(readable ? 0.35 : Self.zoomRange.lowerBound, fit)
    }

    private func selectFirstMatch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
              let match = document.diagram?.tables.first(where: { $0.name.localizedCaseInsensitiveContains(query) })
        else { return }
        document.selection = match.name
    }

    private func reload() async {
        await document.load(connection: sessionManager.session(for: request.sessionID)?.connection)
    }
}

// MARK: - Presenting

/// Opens the diagram the way the platform does: a window where there are windows, a sheet on a
/// phone. `openTable` is how a card's Open Table reaches a workspace.
struct SchemaDiagramPresenter: ViewModifier {
    @Binding var request: SchemaDiagramRequest?
    /// On a phone, where the diagram is a sheet: open the table in the workspace behind it.
    let openTable: (SchemaDiagramRequest, String) -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(DatabaseSessionManager.self) private var sessionManager
    @State private var sheetRequest: SchemaDiagramRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, wanted in
                guard let wanted else { return }
                request = nil
                if GlassWindowPresentation.canOpenWindows {
                    openWindow(id: "database-diagram", value: sessionManager.registerDiagram(wanted))
                } else {
                    sheetRequest = wanted
                }
            }
            .sheet(item: $sheetRequest) { wanted in
                NavigationStack {
                    SchemaDiagramView(request: wanted) { table in
                        sheetRequest = nil
                        openTable(wanted, table)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { sheetRequest = nil }
                        }
                    }
                }
            }
    }
}

extension View {
    func schemaDiagramPresenter(_ request: Binding<SchemaDiagramRequest?>,
                                openTable: @escaping (SchemaDiagramRequest, String) -> Void) -> some View {
        modifier(SchemaDiagramPresenter(request: request, openTable: openTable))
    }
}

#if os(macOS)
import AppKit

/// ⌘-scroll over the canvas, as a zoom: a local event monitor that takes scroll events with ⌘ held
/// while the pointer is over this view in its own window, and lets every other scroll through.
/// SwiftUI has no modifier-aware scroll-wheel gesture on the Mac.
private struct MacCommandScrollZoom: NSViewRepresentable {
    /// Scroll delta (positive = zoom in), whether it came from a trackpad, and the pointer in the
    /// view's own top-left coordinates.
    let onZoom: (_ delta: CGFloat, _ precise: Bool, _ point: CGPoint) -> Void
    /// ⌥-Space pressed (true) or let go (false), in this window, while no text field is typing.
    let onPanKey: (Bool) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onZoom = onZoom
        view.onPanKey = onPanKey
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onZoom = onZoom
        view.onPanKey = onPanKey
    }

    final class MonitorView: NSView {
        var onZoom: ((CGFloat, Bool, CGPoint) -> Void)?
        var onPanKey: ((Bool) -> Void)?
        private var monitor: Any?
        private var keyMonitor: Any?
        private var panKeyHeld = false

        private func setPanKey(_ held: Bool) {
            guard held != panKeyHeld else { return }
            panKeyHeld = held
            onPanKey?(held)
        }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
            setPanKey(false)
            guard window != nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                switch event.type {
                case .keyDown where event.keyCode == 49 && event.modifierFlags.contains(.option):
                    // Typing in Find a table keeps its ⌥-Space.
                    if window.firstResponder is NSText { return event }
                    self.setPanKey(true)
                    return nil
                case .keyUp where event.keyCode == 49 && self.panKeyHeld:
                    self.setPanKey(false)
                    return nil
                case .flagsChanged where self.panKeyHeld && !event.modifierFlags.contains(.option):
                    self.setPanKey(false)
                    return event
                default:
                    return event
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.modifierFlags.contains(.command),
                      let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let delta = event.scrollingDeltaY
                guard delta != 0 else { return nil }
                self.onZoom?(delta, event.hasPreciseScrollingDeltas, point)
                return nil
            }
        }

        // No deinit: leaving the window (which a view always does before it goes) removes the
        // monitor in `viewDidMoveToWindow`.
    }
}
#endif
