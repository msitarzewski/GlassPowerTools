//
//  TerminalStressHarness.swift
//  Glass Power Tools
//
//  W10 (2026-10-08): the headset's SwiftUI layout crash came while a terminal showed tmux running
//  Claude Code. This feeds that kind of output — synchronized frames, cursor-addressed redraws on
//  the alternate screen, a spinner, animated titles, tmux's status line — into the real terminal
//  window, with resizes, tab switches and reconnects, and no connection behind it.
//
//  Never in a shipped build: compiled only in DEBUG, or in a Release build given
//  `-DGLASS_STRESS_HARNESS` on the command line, and run only with `--stress-terminal` alongside
//  `--ui-testing <uuid>`, which keeps the run's storage apart and away from iCloud.
//

#if DEBUG || GLASS_STRESS_HARNESS
import Foundation
import SwiftUI
import GlassTerminalEmulator
#if canImport(UIKit)
import UIKit
#endif

/// A synthetic Claude-Code-in-tmux byte stream. Deterministic for a seed.
struct TerminalStressStream {
    private var state: UInt64
    private var tick = 0
    private var transcript: [String] = []
    private var spinnerIndex = 0
    private var inAlternateScreen = false
    /// Off: no OSC 0/2 titles. Off: no synchronized-output brackets.
    var titles = true
    var synchronized = true

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func random(_ range: ClosedRange<Int>) -> Int {
        // xorshift64*: enough for picking sizes and branches.
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return range.lowerBound + Int(value % UInt64(range.count))
    }

    private static let esc = "\u{1B}["
    private static let spinner = ["·", "✢", "✳", "✶", "✻", "✽"]
    private static let words = ["the", "terminal", "layout", "frame", "session", "window", "tmux", "render",
                                "invalidate", "stack", "children", "state", "observable", "resize", "chunk"]

    /// tmux attaching: the alternate screen, cleared, then a full first frame.
    mutating func attach(rows: Int, columns: Int) -> String {
        inAlternateScreen = true
        return "\u{1B}[?1049h\u{1B}[?25l\u{1B}[H\u{1B}[2J" + fullRedraw(rows: rows, columns: columns)
    }

    /// The next burst of output, as one write from the host would carry it.
    mutating func next(rows: Int, columns: Int) -> String {
        tick += 1
        let rows = max(rows, 8), columns = max(columns, 20)
        var out = ""
        if !inAlternateScreen { out += attach(rows: rows, columns: columns) }
        switch random(0...99) {
        case 0..<3:
            // A full redraw: Claude Code clearing and repainting, or tmux after a resize.
            out += "\u{1B}[?2026h\u{1B}[H\u{1B}[2J" + fullRedraw(rows: rows, columns: columns) + "\u{1B}[?2026l"
        case 3..<4:
            // tmux detaching and attaching again.
            out += "\u{1B}[?1049l\u{1B}[?25h\r\n[detached (from session stress)]\r\n$ "
            inAlternateScreen = false
        case 4..<30:
            // New transcript lines: tmux scrolls the pane's region and writes at its foot.
            let count = random(1...4)
            out += "\u{1B}[?2026h\u{1B}[1;\(rows - 6)r\u{1B}[\(rows - 6);1H"
            for _ in 0..<count {
                let line = transcriptLine(columns: columns)
                transcript.append(line)
                out += "\r\n" + line + "\u{1B}[K"
            }
            out += "\u{1B}[r" + inputArea(rows: rows, columns: columns) + "\u{1B}[?2026l"
        default:
            // The spinner and its counters, redrawn in place with the input box under them.
            out += "\u{1B}[?2026h" + inputArea(rows: rows, columns: columns) + "\u{1B}[?2026l"
        }
        if titles, tick % 3 == 0 {
            // Claude Code animates its title; tmux passes it on with set-titles.
            out += "\u{1B}]0;\(Self.spinner[spinnerIndex]) Claude Code\u{07}"
        }
        if titles, tick % 25 == 0 {
            out += "\u{1B}]2;stress:claude — \(tick)\u{1B}\\"
        }
        if tick % 12 == 0 { out += statusLine(rows: rows, columns: columns) }
        guard !synchronized else { return out }
        return out.replacingOccurrences(of: "\u{1B}[?2026h", with: "").replacingOccurrences(of: "\u{1B}[?2026l", with: "")
    }

    private mutating func transcriptLine(columns: Int) -> String {
        let width = random(10...max(10, columns - 2))
        var text = random(0...4) == 0 ? "⏺ " : "  "
        while text.count < width { text += Self.words[random(0...Self.words.count - 1)] + " " }
        let colour = "\(Self.esc)38;2;\(random(120...255));\(random(120...255));\(random(120...255))m"
        return colour + String(text.prefix(width)) + "\(Self.esc)0m"
    }

    private mutating func inputArea(rows: Int, columns: Int) -> String {
        spinnerIndex = (spinnerIndex + 1) % Self.spinner.count
        let e = Self.esc
        let bar = String(repeating: "─", count: max(0, columns - 2))
        var out = "\(e)\(rows - 5);1H\(e)2K\(e)38;2;215;119;87m\(Self.spinner[spinnerIndex])\(e)0m "
        out += "Thinking… (\(tick / 10)s · ↓ \(random(1...9)).\(random(0...9))k tokens · esc to interrupt)"
        out += "\(e)\(rows - 4);1H\(e)2K╭\(bar)╮"
        out += "\(e)\(rows - 3);1H\(e)2K│ > \(String(repeating: " ", count: max(0, columns - 5)))│"
        out += "\(e)\(rows - 2);1H\(e)2K╰\(bar)╯"
        out += "\(e)\(rows - 1);1H\(e)2K\(e)2m  ? for shortcuts\(e)0m"
        out += "\(e)\(rows - 3);5H"
        return out
    }

    private mutating func statusLine(rows: Int, columns: Int) -> String {
        let e = Self.esc
        let left = "[stress] 0:claude*"
        let right = "\"host\" \(tick / 60 % 24):\(String(format: "%02d", tick % 60))"
        let gap = max(1, columns - left.count - right.count)
        return "\(e)s\(e)\(rows);1H\(e)30;42m\(left)\(String(repeating: " ", count: gap))\(right)\(e)0m\(e)u"
    }

    private mutating func fullRedraw(rows: Int, columns: Int) -> String {
        var out = ""
        let body = max(1, rows - 6)
        let lines = transcript.suffix(body)
        for (index, line) in lines.enumerated() {
            out += "\(Self.esc)\(index + 1);1H\(line)\(Self.esc)K"
        }
        return out + inputArea(rows: rows, columns: columns) + statusLine(rows: rows, columns: columns)
    }
}

/// Drives `TerminalStressStream` into real terminal windows on visionOS and iPad.
@MainActor
final class TerminalStressHarness {
    struct Configuration {
        var sessions = 2
        var seconds = 0
        var seed: UInt64 = 1
        /// Parts left out, to find which one matters: resize, font, tabs, state, find, title, sync,
        /// windows (more terminal windows opening and closing while the first one streams), output.
        var disabled: Set<String> = []

        func enabled(_ part: String) -> Bool { !disabled.contains(part) }

        static var fromLaunchArguments: Configuration? {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--stress-terminal"),
                  let flag = arguments.firstIndex(of: "--ui-testing"), arguments.indices.contains(flag + 1),
                  UUID(uuidString: arguments[flag + 1]) != nil else { return nil }
            func value(_ name: String) -> String? {
                guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
            var configuration = Configuration()
            if let sessions = value("--stress-sessions").flatMap(Int.init) { configuration.sessions = max(1, min(4, sessions)) }
            if let seconds = value("--stress-seconds").flatMap(Int.init) { configuration.seconds = max(0, seconds) }
            if let seed = value("--stress-seed").flatMap(UInt64.init) { configuration.seed = seed }
            if let off = value("--stress-off") {
                configuration.disabled = Set(off.split(separator: ",").map(String.init))
            }
            return configuration
        }
    }

    private static var running: TerminalStressHarness?

    private let configuration: Configuration
    private let sessionManager: SessionManager
    private let settingsManager: SettingsManager
    private var sessions: [TerminalSession] = []
    private var streams: [UUID: TerminalStressStream] = [:]
    private var workgroupID: UUID?
    private var openWindow: OpenWindowAction?
    private var dismissWindow: DismissWindowAction?
    /// Windows opened after the first, oldest first, with their one session each.
    private var extraWindows: [(workgroupID: UUID, session: TerminalSession)] = []
    private var nextSessionNumber = 1
    private var chunks = 0
    private var bytes = 0
    private var resizes = 0
    private let started = ContinuousClock.now

    private init(configuration: Configuration, sessionManager: SessionManager, settingsManager: SettingsManager) {
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.settingsManager = settingsManager
    }

    static func start(_ configuration: Configuration, sessionManager: SessionManager,
                      settingsManager: SettingsManager, openWindow: OpenWindowAction,
                      dismissWindow: DismissWindowAction) {
        guard running == nil else { return }
        let harness = TerminalStressHarness(configuration: configuration, sessionManager: sessionManager,
                                            settingsManager: settingsManager)
        running = harness
        harness.openWindow = openWindow
        harness.dismissWindow = dismissWindow
        harness.begin(openWindow: openWindow)
    }

    private func log(_ message: String) {
        let elapsed = started.duration(to: .now).components.seconds
        print("W10 harness t=\(elapsed)s \(message)")
    }

    private func begin(openWindow: OpenWindowAction) {
        let workgroupID = sessionManager.createWorkgroup(name: "stress", colorTag: .blue)
        self.workgroupID = workgroupID
        for _ in 0..<configuration.sessions {
            sessions.append(makeSession(in: workgroupID))
        }
        #if canImport(UIKit)
        let scenesBefore = Set(UIApplication.shared.connectedScenes.map(\.session.persistentIdentifier))
        #endif
        openWindow(id: "terminal", value: workgroupID)
        log("opened workgroup with \(sessions.count) sessions; off: \(configuration.disabled.sorted())")

        Task {
            try? await Task.sleep(for: .milliseconds(700))
            for session in sessions {
                session.state = .connected
                Task { await self.stream(into: session) }
            }
            #if canImport(UIKit)
            Task { await self.disturb(scenesBefore: scenesBefore) }
            #endif
            await report()
        }
    }

    /// A tmux terminal on a made-up host, connecting, its output not yet started.
    private func makeSession(in workgroupID: UUID) -> TerminalSession {
        let number = nextSessionNumber
        nextSessionNumber += 1
        var server = ServerConfiguration(name: "stress-\(number)", host: "192.0.2.\(10 + number % 200)", username: "ann")
        server.tmux = true
        let session = TerminalSession(server: server, terminalWriteSink: { _ in }, terminalResizeSink: { _, _ in })
        session.tmuxSessionName = "stress-\(number)"
        session.tmuxCommandRunner = { _ in "" }
        sessionManager.registerSession(session)
        _ = sessionManager.appendSession(session, toWorkgroup: workgroupID)
        session.state = .connecting
        var stream = TerminalStressStream(seed: configuration.seed &+ UInt64(number))
        stream.titles = configuration.enabled("title")
        stream.synchronized = configuration.enabled("sync")
        streams[session.id] = stream
        return session
    }

    /// Connect from the library while another terminal streams: a new window, connecting, then
    /// output. With two open already, the oldest is closed instead.
    private func openOrCloseExtraWindow() async {
        if extraWindows.count >= 2 {
            let oldest = extraWindows.removeFirst()
            sessionManager.closeWorkgroup(oldest.workgroupID)
            dismissWindow?(id: "terminal", value: oldest.workgroupID)
            log("closed a window")
            return
        }
        let workgroupID = sessionManager.createWorkgroup(name: "stress", colorTag: .green)
        let session = makeSession(in: workgroupID)
        extraWindows.append((workgroupID, session))
        openWindow?(id: "terminal", value: workgroupID)
        log("opened a window")
        try? await Task.sleep(for: .milliseconds(500))
        session.state = .connected
        Task { await self.stream(into: session) }
    }

    private var finished: Bool {
        configuration.seconds > 0 && started.duration(to: .now) > .seconds(configuration.seconds)
    }

    /// Output as an SSH channel delivers it: frames cut at arbitrary bytes, a few milliseconds apart.
    private func stream(into session: TerminalSession) async {
        guard configuration.enabled("output"), var stream = streams[session.id] else { return }
        while !finished, !Task.isCancelled, session.state != .disconnected {
            let geometry = session.currentTerminalGeometry
            var data = Data(stream.next(rows: geometry.rows, columns: geometry.columns).utf8)
            while !data.isEmpty {
                let size = min(data.count, stream.random(64...4096))
                session.feedTerminalData(data.prefix(size))
                data = data.dropFirst(size)
                chunks += 1
                bytes += size
                if stream.random(0...2) == 0 { try? await Task.sleep(for: .milliseconds(stream.random(1...4))) }
            }
            try? await Task.sleep(for: .milliseconds(stream.random(4...40)))
        }
    }

    #if canImport(UIKit)
    /// What happens around output on the headset: the window resized, the font changed, tabs
    /// switched, a reconnect, a find.
    private func disturb(scenesBefore: Set<String>) async {
        var random = TerminalStressStream(seed: configuration.seed &* 31)
        try? await Task.sleep(for: .seconds(2))
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { !scenesBefore.contains($0.session.persistentIdentifier) }
        if scene == nil { log("no new window scene found; window resizes off") }
        while !finished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(random.random(150...900)))
            switch random.random(0...9) {
            case 0...2 where configuration.enabled("resize"):
                guard let scene else { continue }
                let size = CGSize(width: random.random(700...1500), height: random.random(500...1000))
                #if os(visionOS)
                scene.requestGeometryUpdate(.Vision(size: size)) { _ in }
                #endif
                resizes += 1
            case 3 where configuration.enabled("font"):
                let session = sessions[random.random(0...sessions.count - 1)]
                let defaultSize = settingsManager.currentTheme.swiftTermTheme.fontSize
                session.terminalHostModel.adjustFontSize(by: random.random(0...1) == 0 ? -1 : 1, defaultSize: defaultSize)
            case 4...5 where configuration.enabled("tabs") && sessions.count > 1:
                guard let workgroupID else { continue }
                _ = sessionManager.selectSession(sessions[random.random(0...sessions.count - 1)].id, inWorkgroup: workgroupID)
            case 6 where configuration.enabled("state"):
                let session = sessions[random.random(0...sessions.count - 1)]
                session.reconnectAttemptCount = random.random(1...5)
                session.state = .reconnecting
                try? await Task.sleep(for: .milliseconds(random.random(100...600)))
                session.state = .connected
            case 8 where configuration.enabled("windows"):
                await openOrCloseExtraWindow()
            case 7 where configuration.enabled("find"):
                let session = sessions[random.random(0...sessions.count - 1)]
                if random.random(0...1) == 0 {
                    _ = session.terminalHostModel.find("stack", towardOlder: true)
                } else {
                    session.terminalHostModel.clearSearch()
                }
            default:
                break
            }
        }
    }
    #endif

    private func report() async {
        while !finished, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            log("chunks=\(chunks) bytes=\(bytes) resizes=\(resizes)")
        }
        log("finished: chunks=\(chunks) bytes=\(bytes) resizes=\(resizes)")
    }
}
#endif
