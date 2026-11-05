//
//  TerminalRefreshCounts.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  What a Vision Pro draws, and how soon a typed key's answer comes, counted each second (the
//  owner, 2026-10-29: "I can see the screen flicker. It's very obvious that something is refreshing
//  the screen a LOT"): shown over each terminal window when Settings ▸ Terminal ▸ Show Refresh Counts
//  is on, and written to the diagnostics file every five seconds that anything was counted.
//

#if os(visionOS)
import Foundation
import Observation

@MainActor
@Observable
public final class TerminalRefreshCounts {
    public static let shared = TerminalRefreshCounts()

    public enum Source: String, CaseIterable, Sendable {
        case windows = "Windows drawn"
        case panes = "Terminal panes drawn"
        case bars = "Bars drawn"
        case output = "Output arrived"
        case pictures = "Pictures taken"
        case metalFrames = "Metal frames"
        case wholeRepaints = "Whole repaints, no lines named"
        case wholeScrolledBack = "Whole repaints, not at the foot"
        case wholeAllRows = "Whole repaints, every line"
        case rowRepaints = "Changed-line repaints"
        /// Of those, ones where the screen starts lower than the view's top (`TerminalRepaintBand`).
        case screenLower = "Changed-line repaints, screen lower"
        case unchangedRows = "Repaints skipped, nothing changed"
        /// What the system then drew: the whole terminal, or only the band asked for.
        case drawnWhole = "Terminals drawn whole"
        case drawnInPart = "Terminals drawn in part"
        case waits = "Main thread waits"

        /// The diagnostics file's word for it.
        var key: String {
            switch self {
            case .windows: "windows"
            case .panes: "panes"
            case .bars: "bars"
            case .output: "output"
            case .pictures: "pictures"
            case .metalFrames: "metal frames"
            case .wholeRepaints: "whole repaints (no lines)"
            case .wholeScrolledBack: "whole repaints (not at foot)"
            case .wholeAllRows: "whole repaints (every line)"
            case .rowRepaints: "line repaints"
            case .screenLower: "line repaints (screen lower)"
            case .unchangedRows: "skipped (unchanged)"
            case .drawnWhole: "drawn whole"
            case .drawnInPart: "drawn in part"
            case .waits: "waits"
            }
        }
    }

    /// Typed keys in the last five seconds, from each key sent to the next output from its terminal:
    /// the network there and back, the far side, and this side's reading. Output that would have come
    /// anyway (a spinner) answers early, so it is at most the true time.
    public struct Echo: Equatable, Sendable {
        public let keys: Int
        public let average: Int
        public let longest: Int
    }

    /// The last whole second's counts.
    public private(set) var second: [Source: Int] = [:]
    /// Output in the last second, bytes.
    public private(set) var outputBytes = 0
    public private(set) var echo: Echo?

    @ObservationIgnored private var counting: [Source: Int] = [:]
    @ObservationIgnored private var countingBytes = 0
    @ObservationIgnored private var fiveSeconds: [Source: Int] = [:]
    @ObservationIgnored private var fiveSecondsBytes = 0
    @ObservationIgnored private var echoes: [Duration] = []
    @ObservationIgnored private var keySent: [ObjectIdentifier: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var ticks = 0

    public func note(_ source: Source) {
        counting[source, default: 0] += 1
        start()
    }

    func noteOutput(from terminal: ObjectIdentifier, bytes: Int) {
        counting[.output, default: 0] += 1
        countingBytes += bytes
        if let sent = keySent.removeValue(forKey: terminal) { echoes.append(.now - sent) }
        start()
    }

    func noteKeySent(to terminal: ObjectIdentifier) {
        if keySent[terminal] == nil { keySent[terminal] = .now }
        start()
    }

    private func start() {
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        if second != counting { second = counting }
        if outputBytes != countingBytes { outputBytes = countingBytes }
        for (source, count) in counting { fiveSeconds[source, default: 0] += count }
        fiveSecondsBytes += countingBytes
        counting = [:]
        countingBytes = 0
        // A key with no output for five seconds has had its answer, or gets none.
        let now = ContinuousClock.now
        keySent = keySent.filter { now - $0.value < .seconds(5) }
        ticks += 1
        guard ticks % 5 == 0 else { return }
        let waits = echoes.map { Int($0 / .milliseconds(1)) }
        let next = waits.isEmpty ? nil : Echo(keys: waits.count, average: waits.reduce(0, +) / waits.count,
                                              longest: waits.max() ?? 0)
        if echo != next { echo = next }
        if !fiveSeconds.isEmpty || next != nil {
            var words = Source.allCases.compactMap { source in fiveSeconds[source].map { "\(source.key) \($0)" } }
            if fiveSecondsBytes > 0 { words.append("output \(fiveSecondsBytes / 1024) KB") }
            if let next { words.append("keys \(next.keys), next output after \(next.average) ms, longest \(next.longest) ms") }
            TerminalSelectionDiagnostics.record?("refresh in 5s: " + words.joined(separator: ", "))
        }
        fiveSeconds = [:]
        fiveSecondsBytes = 0
        echoes = []
    }
}
#endif
