//
//  SchemaDiagramVolume.swift
//  Glass Power Tools — GlassDatabase
//
//  The schema diagram on Vision Pro (D43): a volume you can walk around. The cards are the same
//  SwiftUI view the Mac draws, attached to RealityKit entities at the positions of a
//  three-dimensional layout, and they always turn to face you. Foreign keys are lines between them.
//  Select a card to light up what it is joined to; drag any card to turn the whole diagram.
//

#if os(visionOS)
import SwiftUI
import RealityKit

struct SchemaDiagramVolume: View {
    let request: SchemaDiagramRequest
    let openTable: (String) -> Void

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @PhysicalMetric(from: .meters) private var pointsPerMeter = 1
    @State private var document: SchemaDiagramDocument
    @State private var scene = VolumeScene()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var turnStart: (yaw: Float, pitch: Float)?

    init(request: SchemaDiagramRequest, openTable: @escaping (String) -> Void) {
        self.request = request
        self.openTable = openTable
        _document = State(initialValue: SchemaDiagramDocument(database: request.database,
                                                              focusTable: request.focusTable))
    }

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content, _ in
                content.add(scene.root)
            } update: { _, attachments in
                scene.update(document: document, attachments: attachments,
                             volume: SIMD3(Float(proxy.size.width), Float(proxy.size.height),
                                           Float(proxy.size.depth)) / Float(pointsPerMeter),
                             pointsPerMeter: Float(pointsPerMeter),
                             orientation: simd_quatf(angle: yaw, axis: [0, 1, 0])
                                * simd_quatf(angle: pitch, axis: [1, 0, 0]))
            } attachments: {
                if let diagram = document.diagram {
                    let lit = document.litTables
                    ForEach(diagram.tables) { table in
                        Attachment(id: table.name) {
                            SchemaTableCard(table: table, columns: document.columns(of: table),
                                            isSelected: document.selection == table.name,
                                            isDimmed: lit.map { !$0.contains(table.name) } ?? false)
                                .onTapGesture(count: 2) { openTable(table.name) }
                                .onTapGesture {
                                    document.selection = document.selection == table.name ? nil : table.name
                                }
                                .gesture(turnGesture)
                                .hoverEffect()
                        }
                    }
                }
            }
        }
        .overlay { statusOverlay }
        // Apple's toolbar ornament, as every window's bottom bar is (W31): the system sizes and
        // spaces the controls and draws the capsule.
        .toolbar { ToolbarItemGroup(placement: .bottomOrnament) { controls } }
        .task { await reload() }
    }

    /// Dragging a card turns the diagram: sideways about the vertical, up and down about the
    /// horizontal, limited so it never turns upside down.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let start = turnStart ?? (yaw, pitch)
                turnStart = start
                yaw = start.yaw + Float(value.translation.width) * 0.008
                pitch = min(0.9, max(-0.9, start.pitch + Float(value.translation.height) * 0.008))
            }
            .onEnded { _ in turnStart = nil }
    }

    @ViewBuilder private var statusOverlay: some View {
        switch document.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                if case .loading(let done, let total) = document.phase, total > 0 {
                    ProgressView(value: Double(done), total: Double(total)).frame(width: 280)
                    Text("Reading tables… \(done) of \(total)")
                } else {
                    ProgressView()
                    Text("Reading the schema…")
                }
            }
            .padding(24)
            .glassBackgroundEffect()
        case .failed(let message):
            VStack(spacing: 12) {
                Label("No Diagram", systemImage: "exclamationmark.triangle").font(.title3)
                Text(message).multilineTextAlignment(.center).frame(maxWidth: 420)
                Button("Try Again") { Task { await reload() } }
            }
            .padding(24)
            .glassBackgroundEffect()
        case .loaded:
            if document.diagram?.tables.isEmpty == true {
                Text("\(request.database) has no tables to draw.")
                    .padding(24)
                    .glassBackgroundEffect()
            }
        }
    }

    /// Separate items, not a stack: each is one of the toolbar's own, and it draws a label as its
    /// icon.
    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(request.database).font(.headline)
            Text(document.selection ?? document.summary)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 180, alignment: .leading)
        Divider().frame(height: 32)
        Button { yaw -= .pi / 6 } label: { Label("Turn Left", systemImage: "rotate.left") }
        Button { yaw += .pi / 6 } label: { Label("Turn Right", systemImage: "rotate.right") }
        Button { yaw = 0; pitch = 0 } label: {
            Label("Face Front", systemImage: "arrow.counterclockwise")
        }
        Toggle(isOn: $document.keysOnly) { Label("Keys Only", systemImage: "key") }
            .toggleStyle(.button)
        Button {
            if let selection = document.selection { openTable(selection) }
        } label: { Label("Open Table", systemImage: "tablecells") }
            .disabled(document.selection == nil)
        Button { Task { await reload() } } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }

    private func reload() async {
        await document.load(connection: sessionManager.session(for: request.sessionID)?.connection)
    }
}

/// The entities behind the volume, kept across updates so a change of selection recolours the
/// lines rather than rebuilding the scene.
@MainActor
final class VolumeScene {
    let root = Entity()
    private let lines = Entity()
    private var builtVersion = -1
    private var builtSelection: String?
    private var builtVolume: SIMD3<Float> = .zero
    private var builtKeysOnly = false

    init() {
        root.name = "schema-diagram"
        root.addChild(lines)
    }

    func update(document: SchemaDiagramDocument, attachments: RealityViewAttachments,
                volume: SIMD3<Float>, pointsPerMeter: Float, orientation: simd_quatf) {
        root.orientation = orientation
        guard let diagram = document.diagram, !document.volumePositions.isEmpty,
              volume.x > 0, pointsPerMeter > 0 else { return }

        // Fit the layout inside the volume, leaving room at the edges.
        let positions = document.volumePositions
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
        for table in diagram.tables {
            guard let p = positions[table.name] else { continue }
            let size = document.cardSize(of: table)
            let half = SIMD3(Float(size.width), Float(size.height), Float(size.width) * 0.35) / 2
            low = pointwiseMin(low, SIMD3<Float>(p) - half); high = pointwiseMax(high, SIMD3<Float>(p) + half)
        }
        let extent = (high - low) / pointsPerMeter
        let room = volume * 0.85
        let scale = min(1, min(room.x / max(extent.x, 0.001), min(room.y / max(extent.y, 0.001),
                                                                    room.z / max(extent.z, 0.001))))
        root.scale = SIMD3(repeating: scale)

        for table in diagram.tables {
            guard let card = attachments.entity(for: table.name), let p = positions[table.name] else { continue }
            if card.parent !== root {
                root.addChild(card)
                card.components.set(BillboardComponent())
            }
            card.position = SIMD3<Float>(p) / pointsPerMeter
        }

        let selectionChanged = builtSelection != document.selection
        guard builtVersion != document.layoutVersion || selectionChanged || builtVolume != volume
                || builtKeysOnly != document.keysOnly else { return }
        builtVersion = document.layoutVersion
        builtSelection = document.selection
        builtVolume = volume
        builtKeysOnly = document.keysOnly
        rebuildLines(diagram: diagram, document: document, pointsPerMeter: pointsPerMeter, scale: scale)
    }

    private func rebuildLines(diagram: SchemaDiagram, document: SchemaDiagramDocument,
                              pointsPerMeter: Float, scale: Float) {
        lines.children.removeAll()
        // A line keeps about the same thickness whatever the diagram's scale.
        let radius = 0.0012 / max(scale, 0.05)
        let mesh = MeshResource.generateCylinder(height: 1, radius: radius)
        for relationship in diagram.relationships where !relationship.isSelfReference {
            guard let a = document.volumePositions[relationship.fromTable],
                  let b = document.volumePositions[relationship.toTable] else { continue }
            let start = SIMD3<Float>(a) / pointsPerMeter, end = SIMD3<Float>(b) / pointsPerMeter
            let span = end - start
            let length = simd_length(span)
            guard length > 0.0001 else { continue }
            let lit = document.isLit(relationship)
            var material = UnlitMaterial(color: lit == true ? .systemBlue : .white)
            material.blending = .transparent(opacity: .init(floatLiteral: lit == false ? 0.12 : (lit == true ? 0.95 : 0.45)))
            let line = ModelEntity(mesh: mesh, materials: [material])
            line.position = (start + end) / 2
            line.scale = SIMD3(1, length, 1)
            let direction = span / length
            let up = SIMD3<Float>(0, 1, 0)
            // `simd_quatf(from:to:)` is undefined for opposite vectors; a half turn is the answer.
            line.orientation = simd_dot(up, direction) < -0.9999
                ? simd_quatf(angle: .pi, axis: [1, 0, 0])
                : simd_quatf(from: up, to: direction)
            lines.addChild(line)
        }
    }
}
#endif
