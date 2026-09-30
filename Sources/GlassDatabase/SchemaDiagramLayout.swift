//
//  SchemaDiagramLayout.swift
//  Glass Power Tools — GlassDatabase
//
//  Where each table's card goes. A force-directed layout (Fruchterman–Reingold): every card pushes
//  every other away, every foreign key pulls its two tables together, and the push and pull cool
//  over a fixed number of rounds. Then cards that still overlap are separated, and tables with no
//  keys at all are set out in rows beside the rest, where a force layout would only scatter them.
//
//  **Deterministic.** The starting positions come from the tables' sorted names, never from a
//  random number, so the same schema opens the same way every time and a test can pin it.
//  The same code lays out the Mac's plane and the headset's volume; 2D is 3D with depth held at 0.
//

import Foundation

enum SchemaDiagramLayout {
    struct Node: Sendable, Hashable {
        var id: String
        /// Width, height and depth of the card, in the caller's units.
        var size: SIMD3<Double>
    }

    enum Space: Sendable { case plane, volume }

    /// Card centres, keyed by node id. On the plane the top-left of the whole layout is (0, 0),
    /// y grows downward, and z is 0. In the volume the layout is centred on the origin.
    static func layout(nodes: [Node], edges: [(String, String)], space: Space,
                       gap: Double, iterations: Int = 350) -> [String: SIMD3<Double>] {
        guard !nodes.isEmpty else { return [:] }
        let ordered = nodes.sorted { $0.id < $1.id }
        let index = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        var links: [(Int, Int)] = []
        var degree = [Int](repeating: 0, count: ordered.count)
        for (from, to) in edges {
            guard let a = index[from], let b = index[to], a != b else { continue }
            links.append((a, b)); degree[a] += 1; degree[b] += 1
        }
        let connected = ordered.indices.filter { degree[$0] > 0 }
        let isolated = ordered.indices.filter { degree[$0] == 0 }

        var position = [SIMD3<Double>](repeating: .zero, count: ordered.count)
        let depthAxis: Double = space == .volume ? 1 : 0

        // The ideal distance between two related cards: the typical card, plus the gap.
        let typical = connected.isEmpty ? SIMD3<Double>(1, 1, 1)
            : connected.reduce(SIMD3<Double>.zero) { $0 + ordered[$1].size } / Double(connected.count)
        // Not the larger side: that spread twelve tables over 2,300 points (2026-09-30).
        let k = (typical.x + typical.y) / 2 * 0.9 + gap

        // Start on a golden-angle spiral (plane) or a Fibonacci sphere (volume), in name order.
        let n = Double(max(connected.count, 1))
        let radius = k * sqrt(n) * 0.6
        for (i, node) in connected.enumerated() {
            let t = (Double(i) + 0.5) / n
            let angle = Double(i) * 2.399963229728653
            if space == .volume {
                let y = 1 - 2 * t, r = sqrt(max(0, 1 - y * y))
                position[node] = radius * SIMD3(cos(angle) * r, y, sin(angle) * r)
            } else {
                position[node] = radius * sqrt(t) * SIMD3(cos(angle), sin(angle), 0)
            }
        }

        var temperature = radius * 0.5
        let cooling = temperature / Double(max(iterations, 1))
        for _ in 0..<iterations {
            var shift = [SIMD3<Double>](repeating: .zero, count: ordered.count)
            for a in connected.indices {
                let i = connected[a]
                for b in connected.indices where b > a {
                    let j = connected[b]
                    var delta = position[i] - position[j]
                    delta.z *= depthAxis
                    var distance = (delta * delta).sum().squareRoot()
                    if distance < 0.01 {
                        // Two cards on one spot: separate them along a fixed axis, not a random one.
                        delta = SIMD3(1, 0.5, 0.25 * depthAxis); distance = 0.01
                    }
                    let force = (k * k) / distance
                    let push = delta / distance * force
                    shift[i] += push; shift[j] -= push
                }
            }
            for (i, j) in links {
                var delta = position[i] - position[j]
                delta.z *= depthAxis
                let distance = max((delta * delta).sum().squareRoot(), 0.01)
                let pull = delta / distance * (distance * distance / k)
                shift[i] -= pull; shift[j] += pull
            }
            for i in connected {
                // A little gravity keeps separate groups of tables from drifting apart forever.
                shift[i] -= position[i] * 0.05
                let length = max((shift[i] * shift[i]).sum().squareRoot(), 0.0001)
                position[i] += shift[i] / length * min(length, temperature)
                position[i].z *= depthAxis
            }
            temperature = max(temperature - cooling, k * 0.01)
        }

        if space == .plane {
            separate(&position, nodes: ordered, members: connected, gap: gap, space: space)
        } else {
            spread(&position, nodes: ordered, members: connected, gap: gap)
            faceTheViewer(&position, members: connected)
        }

        // Tables with no keys: rows below the graph on the plane, a wall behind it in the volume.
        if !isolated.isEmpty {
            let placed = bounds(position, nodes: ordered, members: connected)
            let width = connected.isEmpty ? Double(isolated.count).squareRoot() * (typical.x + gap) * 1.6
                : max(placed.max.x - placed.min.x, (ordered[isolated[0]].size.x + gap) * 3)
            let top = connected.isEmpty ? 0 : placed.max.y + gap * 2
            let back = connected.isEmpty ? 0 : placed.min.z - gap * 2
            let left = connected.isEmpty ? 0 : placed.min.x
            var x = left, y = top, rowHeight = 0.0
            for i in isolated {
                let size = ordered[i].size
                if x > left, x + size.x > left + width { x = left; y += rowHeight + gap; rowHeight = 0 }
                position[i] = SIMD3(x + size.x / 2, y + size.y / 2, space == .volume ? back : 0)
                x += size.x + gap; rowHeight = max(rowHeight, size.y)
            }
        }

        // Anchor: top-left at the origin on the plane, centred in the volume.
        let all = bounds(position, nodes: ordered, members: Array(ordered.indices))
        let offset = space == .plane ? SIMD3(all.min.x, all.min.y, 0) : (all.min + all.max) / 2
        return Dictionary(uniqueKeysWithValues: ordered.indices.map { (ordered[$0].id, position[$0] - offset) })
    }

    /// Pushes apart any two cards whose boxes (plus the gap) overlap, along the axis where they
    /// overlap least, until none do or the rounds run out.
    private static func separate(_ position: inout [SIMD3<Double>], nodes: [Node], members: [Int],
                                 gap: Double, space: Space) {
        for _ in 0..<400 {
            var moved = false
            for a in members.indices {
                for b in members.indices where b > a {
                    let i = members[a], j = members[b]
                    let reach = (nodes[i].size + nodes[j].size) / 2 + gap
                    let delta = position[j] - position[i]
                    let overlap = reach - SIMD3(abs(delta.x), abs(delta.y), abs(delta.z))
                    let depthOverlaps = space == .plane || overlap.z > 0
                    guard overlap.x > 0, overlap.y > 0, depthOverlaps else { continue }
                    var axis = overlap.x < overlap.y ? 0 : 1
                    if space == .volume, overlap.z < overlap[axis] { axis = 2 }
                    let direction: Double = delta[axis] >= 0 ? 1 : -1
                    position[i][axis] -= direction * overlap[axis] / 2
                    position[j][axis] += direction * overlap[axis] / 2
                    moved = true
                }
            }
            if !moved { return }
        }
    }

    /// The volume's version of `separate`: its cards turn to face the viewer, so what matters is
    /// how far apart their centres are, not whether two boxes intersect. Separating boxes pushed
    /// every pair apart along its thinnest side, and a schema came out as a tall column one card
    /// wide (2026-09-30).
    private static func spread(_ position: inout [SIMD3<Double>], nodes: [Node], members: [Int], gap: Double) {
        for _ in 0..<400 {
            var moved = false
            for a in members.indices {
                for b in members.indices where b > a {
                    let i = members[a], j = members[b]
                    let need = (max(nodes[i].size.x, nodes[i].size.y) + max(nodes[j].size.x, nodes[j].size.y)) / 2 * 0.8 + gap
                    var delta = position[j] - position[i]
                    var distance = (delta * delta).sum().squareRoot()
                    guard distance < need else { continue }
                    if distance < 0.001 { delta = SIMD3(1, 0, 0); distance = 1 }
                    let push = delta / distance * (need - distance) / 2
                    position[i] -= push; position[j] += push
                    moved = true
                }
            }
            if !moved { return }
        }
    }

    /// Turns the volume's layout so its widest spread runs left to right, the next up and down,
    /// and the thinnest toward the viewer. A force layout is free to settle a tree-shaped schema
    /// flat, and it did — edge-on, a sheet 150 points wide seen from its side (2026-09-30).
    /// The axes are the principal axes of the card centres (Jacobi on their 3×3 covariance).
    private static func faceTheViewer(_ position: inout [SIMD3<Double>], members: [Int]) {
        guard members.count > 2 else { return }
        let centre = members.reduce(SIMD3<Double>.zero) { $0 + position[$1] } / Double(members.count)
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        for i in members {
            let d = position[i] - centre
            for r in 0..<3 { for k in 0..<3 { c[r][k] += d[r] * d[k] } }
        }
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<32 {
            var p = 0, q = 1
            for (a, b) in [(0, 1), (0, 2), (1, 2)] where abs(c[a][b]) > abs(c[p][q]) { p = a; q = b }
            guard abs(c[p][q]) > 1e-9 else { break }
            let theta = 0.5 * atan2(2 * c[p][q], c[q][q] - c[p][p])
            let cs = cos(theta), sn = sin(theta)
            for k in 0..<3 {
                let kp = c[k][p], kq = c[k][q]
                c[k][p] = cs * kp - sn * kq; c[k][q] = sn * kp + cs * kq
            }
            for k in 0..<3 {
                let pk = c[p][k], qk = c[q][k]
                c[p][k] = cs * pk - sn * qk; c[q][k] = sn * pk + cs * qk
            }
            for k in 0..<3 {
                let kp = v[k][p], kq = v[k][q]
                v[k][p] = cs * kp - sn * kq; v[k][q] = sn * kp + cs * kq
            }
        }
        // Columns of `v` are the axes; order them by spread, widest first.
        let order = [0, 1, 2].sorted { c[$0][$0] > c[$1][$1] }
        let axes = order.map { SIMD3(v[0][$0], v[1][$0], v[2][$0]) }
        for i in members {
            let d = position[i] - centre
            position[i] = SIMD3((d * axes[0]).sum(), (d * axes[1]).sum(), (d * axes[2]).sum())
        }
        // A flat schema still gets depth — the point of a volume — at least a third of its width.
        let zs = members.map { position[$0].z }, xs = members.map { position[$0].x }
        let depth = (zs.max() ?? 0) - (zs.min() ?? 0), width = (xs.max() ?? 0) - (xs.min() ?? 0)
        if depth > 0.001, depth < width * 0.35 {
            let stretch = width * 0.35 / depth
            for i in members { position[i].z *= stretch }
        }
    }

    static func bounds(_ position: [SIMD3<Double>], nodes: [Node], members: [Int])
        -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        guard let first = members.first else { return (.zero, .zero) }
        var low = position[first] - nodes[first].size / 2, high = position[first] + nodes[first].size / 2
        for i in members {
            low = pointwiseMin(low, position[i] - nodes[i].size / 2)
            high = pointwiseMax(high, position[i] + nodes[i].size / 2)
        }
        return (low, high)
    }
}
