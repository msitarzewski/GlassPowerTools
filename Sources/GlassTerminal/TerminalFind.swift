//
//  TerminalFind.swift
//  Glass Power Tools — GlassTerminal
//
//  Find in a terminal (2026-10-08): one bar, two sources. A plain shell is searched in SwiftTerm's
//  own buffer. A terminal kept in tmux is searched by tmux, in tmux's history: tmux draws on the
//  alternate screen, where SwiftTerm has only the rows on screen and tmux's status line, so before
//  this, find in tmux "returned nothing".
//
//  A step is one request in flight, and the latest request wins — the shape of the tmux scroll in
//  `TerminalSession.scrollTmux`, because a tmux step is a round trip and keys repeat faster.
//

import Foundation
import Observation
import GlassTerminalEmulator
#if canImport(AppKit)
import AppKit
#endif

/// Which way a step goes. Return, ⌘G and the up arrow go toward older output, the way a terminal
/// is read back: the first search finds the newest match.
nonisolated enum TerminalFindDirection: Equatable, Sendable {
    case older
    case newer
}

/// What a menu command asks of the focused pane's find bar: ⌘F, ⌘G or ⇧⌘G.
nonisolated enum TerminalFindCommand: Equatable, Sendable {
    case show
    case next
    case previous
}

/// A find command for one pane, told apart from the one before by its nonce.
nonisolated struct TerminalFindRequest: Equatable, Sendable {
    var nonce: UInt64
    var command: TerminalFindCommand

    static let none = TerminalFindRequest(nonce: 0, command: .show)
}

/// What a step found.
enum TerminalFindOutcome: Equatable, Sendable {
    /// `index` counts from the newest match, 1 being the newest; nil when the source cannot say.
    case found(count: Int, index: Int?)
    case notFound
    /// A plain sentence that says what to do.
    case failed(String)

    /// What the bar shows for it.
    var label: String {
        switch self {
        case .found(let count, let index?) where index > 0 && index <= count: "\(index) of \(count)"
        case .found(let count, _): count == 1 ? "1 match" : "\(count) matches"
        case .notFound: "No match"
        case .failed: ""
        }
    }

    var failure: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Where a step searches.
@MainActor
protocol TerminalFindSource: AnyObject {
    /// A limit the bar states while this source is in use; nil when there is none.
    var notice: String? { get }
    func step(_ term: String, _ direction: TerminalFindDirection) async -> TerminalFindOutcome
    /// The term changed: the next step starts again from the newest output.
    func restart()
    /// The bar closed: drop the highlight and give the terminal back to typing.
    func end()
}

// MARK: SwiftTerm's buffer

/// A plain shell, and any full-screen program not in app-managed tmux.
final class SwiftTermFindSource: TerminalFindSource {
    static let alternateScreenNotice = "Only what's on screen can be searched while this program runs. "
        + "Use its own search, such as / in less or vim."
    static let notReady = "The terminal isn't ready yet. Try again in a moment."

    let model: SwiftTermHostModel

    init(model: SwiftTermHostModel) {
        self.model = model
    }

    /// A full-screen program draws on the alternate screen, which has no scrollback to search.
    var notice: String? {
        model.isLikelyRunningInteractiveProgram ? Self.alternateScreenNotice : nil
    }

    func step(_ term: String, _ direction: TerminalFindDirection) async -> TerminalFindOutcome {
        guard let result = model.find(term, towardOlder: direction == .older) else {
            return .failed(Self.notReady)
        }
        guard result.found else { return .notFound }
        return .found(count: result.total, index: result.index > 0 ? result.index : nil)
    }

    func restart() { model.clearSearch() }
    func end() { model.clearSearch() }
}

// MARK: tmux's search

/// One request to tmux's search: a step, or leaving copy mode.
nonisolated enum TerminalTmuxFindRequest: Equatable, Sendable {
    case search(String, TerminalFindDirection)
    case end
}

/// What `display -p` printed after a step.
nonisolated struct TerminalTmuxFindReply: Equatable, Sendable {
    var present: Bool
    var count: Int
    /// The cursor's line in copy mode's view of the history: its row less how far the view is
    /// scrolled. tmux holds that view still while output arrives, so the same line keeps its value.
    var line: Int
    var column: Int
}

/// The parts the Mac's argv builder and the SSH `sh` builder share.
nonisolated enum TerminalTmuxFind {
    /// After the step: whether the search found anything, how many matches, and where the cursor
    /// landed. Spaces, not tabs, between fields.
    static let replyFormat = "#{search_present} #{search_count} #{scroll_position} #{copy_cursor_y} #{copy_cursor_x}"

    static func searchCommand(_ direction: TerminalFindDirection) -> String {
        direction == .older ? "search-backward-text" : "search-forward-text"
    }

    /// The term as tmux's command parser needs it. An argument that **ends** in `;` ends the
    /// command there, so a trailing `;` is written `\;`. A `;` anywhere else is already literal,
    /// and escaping it would search for the backslash too (tmux 3.7c, tried both ways).
    static func argument(_ term: String) -> String {
        term.hasSuffix(";") ? String(term.dropLast()) + "\\;" : term
    }

    /// `1 3 36 8 0`; when nothing is found the count is empty: `0  36 8 0`. Nil for anything else.
    static func parse(_ output: String) -> TerminalTmuxFindReply? {
        let line = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let fields = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5, fields[0] == "0" || fields[0] == "1",
              let scroll = Int(fields[2]), let row = Int(fields[3]), let column = Int(fields[4]),
              scroll >= 0, row >= 0, column >= 0 else { return nil }
        let count: Int
        if fields[1].isEmpty {
            count = 0
        } else if let value = Int(fields[1]), value >= 0 {
            count = value
        } else {
            return nil
        }
        return TerminalTmuxFindReply(present: fields[0] == "1", count: count, line: row - scroll, column: column)
    }
}

/// Where a terminal kept in tmux is searched: its session, and how a request reaches it.
struct TerminalTmuxFindTarget {
    typealias Runner = @MainActor (TerminalTmuxFindRequest) async -> String?

    let session: String
    /// Said when tmux does not answer, with what to do about it.
    let failure: String
    /// Runs one request; nil when tmux failed or did not answer.
    let run: Runner
}

/// tmux's own search: tmux scrolls to the hit and highlights it itself, and its redraws keep the
/// highlight. Copy mode is left on a miss and when the bar closes, so typing reaches the shell.
final class TmuxFindSource: TerminalFindSource {
    let session: String
    private let failure: String
    private let run: TerminalTmuxFindTarget.Runner
    /// This find has entered copy mode and not left it yet.
    private(set) var inCopyMode = false
    private var last: (direction: TerminalFindDirection, reply: TerminalTmuxFindReply)?
    private var restartPending = false

    init(_ target: TerminalTmuxFindTarget) {
        session = target.session
        failure = target.failure
        run = target.run
    }

    var notice: String? { nil }

    func step(_ term: String, _ direction: TerminalFindDirection) async -> TerminalFindOutcome {
        if restartPending, inCopyMode {
            // A new term starts at the live screen, so it too finds the newest match first.
            _ = await run(.end)
            inCopyMode = false
            last = nil
        }
        restartPending = false
        guard var reply = await search(term, direction) else { return await fail() }
        // In emacs mode-keys (tmux's default), turning round lands on the match already shown —
        // the cursor only moves to its other end — so the step is sent once more.
        if reply.present, reply.count > 1, let last, last.direction != direction,
           Self.sameMatch(last.reply, reply, width: term.count) {
            guard let again = await search(term, direction) else { return await fail() }
            reply = again
        }
        guard reply.present, reply.count > 0 else {
            last = nil
            if inCopyMode {
                _ = await run(.end)
                inCopyMode = false
            }
            return .notFound
        }
        last = (direction, reply)
        return .found(count: reply.count, index: nil)
    }

    /// No readable answer — no connection, or a tmux without these searches, which stops the
    /// chain after `copy-mode`. Copy mode is left at once, never kept waiting for a close.
    private func fail() async -> TerminalFindOutcome {
        last = nil
        _ = await run(.end)
        inCopyMode = false
        return .failed(failure)
    }

    private func search(_ term: String, _ direction: TerminalFindDirection) async -> TerminalTmuxFindReply? {
        let output = await run(.search(term, direction))
        // The step entered copy mode whatever came back, so a close still leaves it.
        inCopyMode = true
        return output.flatMap(TerminalTmuxFind.parse)
    }

    /// The same line, and the cursor no further than the term's width from where it was: the
    /// other end of one match. Characters, not cells, so a wide term errs toward one more press.
    static func sameMatch(_ before: TerminalTmuxFindReply, _ after: TerminalTmuxFindReply, width: Int) -> Bool {
        before.line == after.line && abs(before.column - after.column) <= max(width, 1)
    }

    func restart() {
        last = nil
        restartPending = true
    }

    func end() {
        last = nil
        restartPending = false
        guard inCopyMode else { return }
        inCopyMode = false
        let run = run
        Task { _ = await run(.end) }
    }
}

// MARK: Choosing the source

nonisolated enum TerminalFindSourceChoice: Equatable, Sendable {
    case swiftTerm
    case tmux(session: String)

    /// tmux's search for a terminal the app keeps in tmux while tmux can be reached; otherwise
    /// SwiftTerm's buffer, which is always there.
    static func choose(tmuxSession: String?, tmuxReachable: Bool) -> Self {
        guard let tmuxSession, !tmuxSession.isEmpty, tmuxReachable else { return .swiftTerm }
        return .tmux(session: tmuxSession)
    }
}

extension TerminalSession {
    /// An SSH terminal kept in tmux, while connected: its finds go to tmux on the host, over this
    /// connection. Nil otherwise, and the terminal's own buffer is searched — as it is in tmux too
    /// once the terminal is tmux's control-mode client and keeps the history (`TmuxControlClient`, D83).
    var tmuxFindTarget: TerminalTmuxFindTarget? {
        guard !terminalHostModel.keepsHistoryUnderTmux else { return nil }
        guard case .tmux(let name) = TerminalFindSourceChoice.choose(
            tmuxSession: survivesClose ? tmuxSessionName : nil, tmuxReachable: state == .connected) else { return nil }
        return TerminalTmuxFindTarget(
            session: name,
            failure: "The server didn't answer the search. Check the connection, then search again."
        ) { [weak self] request in
            guard let self else { return nil }
            return try? await runTmuxCommand(TerminalTmux.findCommand(name: name, request: request))
        }
    }
}

#if os(macOS)
extension MacLocalTmux {
    /// A local pane in this Mac's tmux: its finds run tmux here, in order with its scrolling.
    static func findTarget(session: String?, tmux: String? = MacLocalTmux.executablePath()) -> TerminalTmuxFindTarget? {
        guard case .tmux(let name) = TerminalFindSourceChoice.choose(tmuxSession: session, tmuxReachable: tmux != nil),
              let tmux else { return nil }
        return TerminalTmuxFindTarget(
            session: name,
            failure: "tmux on this Mac didn't answer the search. Search again."
        ) { request in
            let arguments = MacLocalTmux.findArguments(session: name, request: request)
            return await withCheckedContinuation { continuation in
                MacLocalTmux.scrollQueue.async {
                    continuation.resume(returning: MacLocalTmux.run(tmux, arguments))
                }
            }
        }
    }
}
#endif

// MARK: The bar's state

/// One pane's find bar: its term, whether it is open, and what the last step found.
@MainActor
@Observable
final class TerminalFindController {
    /// What the field holds. A change starts the search again from the newest output, but does
    /// not search: that waits for Return or an arrow.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            termChanged()
        }
    }
    private(set) var isPresented = false
    private(set) var outcome: TerminalFindOutcome?
    private(set) var notice: String?
    private(set) var isSearching = false
    /// Raised each time the field should take the keyboard.
    private(set) var focusRequest: UInt64 = 0

    @ObservationIgnored private var model: SwiftTermHostModel?
    @ObservationIgnored private var tmuxTarget: (@MainActor () -> TerminalTmuxFindTarget?)?
    @ObservationIgnored private var source: (any TerminalFindSource)?
    @ObservationIgnored private var pending: (term: String, direction: TerminalFindDirection)?
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private let sharedTerm: @MainActor () -> String?
    @ObservationIgnored private let publishTerm: @MainActor (String) -> Void

    /// - Parameters:
    ///   - sharedTerm: the term a closed bar opens with when it has none: the Mac's find pasteboard.
    ///   - publishTerm: told each term searched for, so other windows and apps can find it again.
    init(sharedTerm: @escaping @MainActor () -> String? = TerminalFindController.systemFindTerm,
         publishTerm: @escaping @MainActor (String) -> Void = TerminalFindController.publishSystemFindTerm) {
        self.sharedTerm = sharedTerm
        self.publishTerm = publishTerm
    }

    /// Where steps search: this terminal's buffer, or tmux when `tmux` names a target, asked at
    /// every step because a terminal can enter tmux after the bar opened.
    func configure(model: SwiftTermHostModel, tmux: @escaping @MainActor () -> TerminalTmuxFindTarget?) {
        self.model = model
        self.tmuxTarget = tmux
    }

    /// ⌘F: open the bar and put the keyboard in its field.
    func present() {
        if query.isEmpty, let shared = sharedTerm(), !shared.isEmpty { query = shared }
        isPresented = true
        focusRequest &+= 1
        notice = currentSource()?.notice
    }

    /// ⌘G and ⇧⌘G: step with the bar's term, opening it with the last term — or the find
    /// pasteboard's — when it is closed. With no term at all, it is ⌘F.
    func findAgain(_ direction: TerminalFindDirection) {
        if query.isEmpty, let shared = sharedTerm(), !shared.isEmpty { query = shared }
        guard !query.isEmpty else {
            present()
            return
        }
        if !isPresented {
            isPresented = true
            focusRequest &+= 1
        }
        step(direction)
    }

    func perform(_ command: TerminalFindCommand) {
        switch command {
        case .show: present()
        case .next: findAgain(.older)
        case .previous: findAgain(.newer)
        }
    }

    /// Return and the arrows. A step already on its way finishes first; only the latest request
    /// made meanwhile follows it.
    func step(_ direction: TerminalFindDirection) {
        let term = query
        guard !term.isEmpty else { return }
        publishTerm(term)
        pending = (term, direction)
        pump()
    }

    /// Escape and the close button. The term stays for ⌘G.
    func close() {
        generation &+= 1
        pending = nil
        isPresented = false
        outcome = nil
        notice = nil
        source?.end()
    }

    /// Waits for the step in flight and any that follow it — for tests.
    func waitUntilIdle() async {
        while let runner { await runner.value }
    }

    private func termChanged() {
        outcome = nil
        if runner != nil { generation &+= 1 }
        source?.restart()
    }

    private func pump() {
        guard runner == nil, pending != nil else { return }
        runner = Task { [weak self] in
            guard let self else { return }
            while let request = pending {
                pending = nil
                let generation = self.generation
                guard let source = currentSource() else {
                    outcome = .failed(SwiftTermFindSource.notReady)
                    break
                }
                isSearching = true
                let result = await source.step(request.term, request.direction)
                if generation == self.generation {
                    outcome = result
                    notice = source.notice
                } else {
                    // Closed or changed while the step travelled: it may have entered copy mode
                    // after the close left it, so leave again.
                    source.end()
                }
            }
            isSearching = false
            runner = nil
        }
    }

    /// The source for the terminal as it is now, kept while it stays the same so tmux's place in
    /// the search carries from step to step.
    private func currentSource() -> (any TerminalFindSource)? {
        if let target = tmuxTarget?() {
            if let tmux = source as? TmuxFindSource, tmux.session == target.session { return tmux }
            source?.end()
            source = TmuxFindSource(target)
        } else if let model {
            if let buffer = source as? SwiftTermFindSource, buffer.model === model { return buffer }
            source?.end()
            source = SwiftTermFindSource(model: model)
        } else {
            return nil
        }
        return source
    }

    // MARK: The system's find pasteboard

    static func systemFindTerm() -> String? {
        #if os(macOS)
        NSPasteboard(name: .find).string(forType: .string)
        #else
        nil
        #endif
    }

    static func publishSystemFindTerm(_ term: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard(name: .find)
        guard pasteboard.string(forType: .string) != term else { return }
        pasteboard.clearContents()
        pasteboard.setString(term, forType: .string)
        #endif
    }
}
