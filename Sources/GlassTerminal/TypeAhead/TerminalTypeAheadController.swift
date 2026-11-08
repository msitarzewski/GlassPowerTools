//
//  TerminalTypeAheadController.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): one terminal's suggestions. It hears the line change and the commands run from
//  the terminal's host model (`SwiftTermHostModel`, whose prompt tracker follows the shell), keeps what ran in the
//  machine's history, and asks the sources and the engine what to offer. `tasks/2026-11/2026-11-06_type-ahead.md`.
//

import Foundation
import GlassLayers
import GlassTerminalEmulator
import os

/// Settings ▸ Terminal ▸ Suggestions.
nonisolated struct TerminalTypeAheadSettings: Equatable, Sendable {
    /// Suggestions at all.
    var enabled = true
    /// The Mac's grey text after the cursor (→ takes it). Off, the Mac offers none inline.
    var showsGreyText = true
    /// Keep the commands run on each machine.
    var keepsHistory = true
    /// Sources turned off.
    var disabledSources: Set<TerminalTypeAheadSource> = [.assistant]
    /// This Mac's zsh terminals start with the shell integration (`TerminalLocalShellIntegration`).
    var integratesThisMac = true

    static let enabledKey = "terminal.typeAhead.enabled"
    static let greyTextKey = "terminal.typeAhead.greyText"
    static let historyKey = "terminal.typeAhead.keepsHistory"
    static let disabledSourcesKey = "terminal.typeAhead.disabledSources"
    static let integratesThisMacKey = "terminal.typeAhead.integratesThisMac"

    static func load(from defaults: UserDefaults) -> TerminalTypeAheadSettings {
        var settings = TerminalTypeAheadSettings()
        if defaults.object(forKey: enabledKey) != nil { settings.enabled = defaults.bool(forKey: enabledKey) }
        if defaults.object(forKey: greyTextKey) != nil { settings.showsGreyText = defaults.bool(forKey: greyTextKey) }
        if defaults.object(forKey: historyKey) != nil { settings.keepsHistory = defaults.bool(forKey: historyKey) }
        if defaults.object(forKey: integratesThisMacKey) != nil {
            settings.integratesThisMac = defaults.bool(forKey: integratesThisMacKey)
        }
        if let names = defaults.stringArray(forKey: disabledSourcesKey) {
            settings.disabledSources = Set(names.compactMap(TerminalTypeAheadSource.init(rawValue:)))
        }
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(showsGreyText, forKey: Self.greyTextKey)
        defaults.set(keepsHistory, forKey: Self.historyKey)
        defaults.set(disabledSources.map(\.rawValue).sorted(), forKey: Self.disabledSourcesKey)
        defaults.set(integratesThisMac, forKey: Self.integratesThisMacKey)
    }

    func uses(_ source: TerminalTypeAheadSource) -> Bool { enabled && !disabledSources.contains(source) }
}

/// Words a source offers for the word being typed, given the whole line. Sources beyond history and snippets
/// (the library, the folder, common tools, the screen) answer through these.
typealias TerminalTypeAheadWordSource = @MainActor (_ line: String) -> [(word: String, score: Double)]

@MainActor
final class TerminalTypeAheadController {
    /// The machine whose history this terminal shares: a library machine's id, or `TerminalCommandHistory.thisMac`.
    let machine: String
    private weak var model: SwiftTermHostModel?
    private let history: TerminalCommandHistory
    private let folder: @MainActor () -> String?
    private let snippets: @MainActor () -> [CommandSnippet]
    private let defaults: UserDefaults
    /// Word sources by kind, added as the capability learns what the terminal can reach.
    var wordSources: [(source: TerminalTypeAheadSource, words: TerminalTypeAheadWordSource)] = []
    private(set) var settings: TerminalTypeAheadSettings
    private var settingsObserver: NSObjectProtocol?
    /// The commands run in this terminal lately, oldest first: the on-device model's context.
    private var recent: [String] = []
    private var folderSource: TerminalTypeAheadFolder?
    private lazy var assistant: TerminalTypeAheadAssistant = {
        let assistant = TerminalTypeAheadAssistant()
        assistant.onAnswer = { [weak self] in self?.lineChanged(self?.model?.typeAheadLine) }
        return assistant
    }()

    /// Joins `model`'s terminal to the type-ahead for `machine`, once; a second call replaces the first.
    @discardableResult
    static func attach(to model: SwiftTermHostModel, machine: String,
                       folder: @escaping @MainActor () -> String?,
                       snippets: @escaping @MainActor () -> [CommandSnippet],
                       history: TerminalCommandHistory = .shared,
                       defaults: UserDefaults = GlassUITestRun.settingsDefaults) -> TerminalTypeAheadController {
        if let existing = model.typeAheadOwner as? TerminalTypeAheadController, existing.machine == machine {
            return existing
        }
        let controller = TerminalTypeAheadController(model: model, machine: machine, folder: folder, snippets: snippets,
                                                     history: history, defaults: defaults)
        model.typeAheadOwner = controller
        return controller
    }

    init(model: SwiftTermHostModel, machine: String, folder: @escaping @MainActor () -> String?,
         snippets: @escaping @MainActor () -> [CommandSnippet], history: TerminalCommandHistory, defaults: UserDefaults) {
        self.model = model
        self.machine = machine
        self.folder = folder
        self.snippets = snippets
        self.history = history
        self.defaults = defaults
        self.settings = TerminalTypeAheadSettings.load(from: defaults)
        model.onTypeAheadLine = { [weak self] line in self?.lineChanged(line) }
        model.onTerminalCommandRun = { [weak self] command in self?.ran(command) }
        model.onTerminalCommandFinished = { [weak self] status in self?.finished(status) }
        applySettings()
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSettings() }
        }
    }

    isolated deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// What to offer for the line already on the screen, once the sources are added: a window opened on a terminal
    /// typed into (or a demo's transcript, read before its window's sources were) offers at once, not at the next
    /// key (2026-11-06).
    func offerForCurrentLine() {
        Self.logger.debug("event=attached line=\(self.model?.typeAheadLine != nil, privacy: .public) marks=\(self.model?.hasShellIntegration ?? false, privacy: .public)")
        lineChanged(model?.typeAheadLine)
    }

    private func reloadSettings() {
        let fresh = TerminalTypeAheadSettings.load(from: defaults)
        guard fresh != settings else { return }
        settings = fresh
        applySettings()
        lineChanged(model?.typeAheadLine)
    }

    private func applySettings() {
        #if os(macOS)
        model?.drawsTypeAheadGhost = settings.enabled && settings.showsGreyText
        #else
        model?.drawsTypeAheadGhost = false
        if model?.offersTypeAheadChips != settings.enabled { model?.offersTypeAheadChips = settings.enabled }
        #endif
    }

    /// A folder as a shell reports it: a path, or OSC 7's `file://host/path` with its percent escapes.
    nonisolated static func folderPath(_ reported: String?) -> String? {
        guard let reported, !reported.isEmpty else { return nil }
        if reported.hasPrefix("/") { return reported }
        guard let url = URL(string: reported), url.isFileURL else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? path : nil
    }

    // MARK: - Events

    func lineChanged(_ line: TerminalTypedLine?) {
        guard let model else { return }
        guard settings.enabled, let line, line.cursorAtEnd else {
            model.setTypeAhead(nil, choices: [])
            return
        }
        let candidates = candidates(for: line.text)
        let (best, choices) = TerminalTypeAheadEngine.choose(typed: line.text, candidates: candidates)
        let suggestion = best.map {
            TerminalTypeAheadSuggestion(command: $0.command, suffix: String($0.command.dropFirst(line.text.count)))
        }
        // Lengths and counts only: never what was typed.
        Self.logger.debug("""
            event=line length=\(line.text.count, privacy: .public) candidates=\(candidates.count, privacy: .public) \
            choices=\(choices.count, privacy: .public) kept=\(self.history.records(for: self.machine).count, privacy: .public)
            """)
        model.setTypeAhead(suggestion, choices: choices.map(\.command))
    }

    private static let logger = Logger(subsystem: "sh.glas", category: "type-ahead")

    private func ran(_ command: TerminalRanCommand) {
        Self.logger.debug("event=ran length=\(command.command.count, privacy: .public)")
        guard settings.enabled else { return }
        let here = folder()
        // Whatever ran may have made or removed files or branches.
        folderSource?.invalidate(here)
        guard TerminalCommandHistory.keeps(command.command) else { return }
        recent.append(command.command.trimmingCharacters(in: .whitespacesAndNewlines))
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
        if settings.keepsHistory { history.record(command.command, machine: machine, folder: here) }
    }

    private func finished(_ status: Int?) {
        guard settings.enabled, settings.keepsHistory else { return }
        history.finish(machine: machine, status: status)
    }

    // MARK: - Sources

    /// The library's machines for the commands that reach one (`TerminalTypeAheadLibrary`), once.
    func addLibrary(servers: @escaping @MainActor () -> [ServerConfiguration]) {
        guard !wordSources.contains(where: { $0.source == .library }) else { return }
        wordSources.append((.library, { line in
            let machines = servers().map {
                TerminalTypeAheadLibrary.Machine(address: $0.host, user: $0.username, port: $0.port,
                                                 lastConnected: $0.lastConnected)
            }
            return TerminalTypeAheadLibrary.words(line: line, machines: machines)
        }))
    }

    /// What the folder holds, read with `reader`, for arguments `kind` says it can fill; once. `home`: what `~` is to
    /// `reader` (this Mac's home, or "" for a server, whose SFTP paths start in it), for a typed path.
    func addFolder(reader: any TerminalFolderReader, home: String,
                   kind: @escaping @MainActor (String) -> TerminalFolderArgument?) {
        guard folderSource == nil else { return }
        let source = TerminalTypeAheadFolder(reader: reader, home: home)
        source.onLoaded = { [weak self] in self?.lineChanged(self?.model?.typeAheadLine) }
        folderSource = source
        wordSources.append((.folder, { [weak self, weak source] line in
            source?.words(line: line, folder: self?.folder(), kind: kind(line)) ?? []
        }))
    }

    /// Common tools' subcommands and options (`CommandSpecs`), once.
    func addTools() {
        guard !wordSources.contains(where: { $0.source == .tool }) else { return }
        wordSources.append((.tool, { line in
            guard let completion = CommandSpecs.completion(forLine: line) else { return [] }
            // The spec's prefix is the word as the shell reads it (quotes gone, after `=` for `--opt=`); what
            // follows it in a candidate is what to append to the word as typed.
            let typedWord = TerminalTypeAheadEngine.currentWord(of: line).word
            return completion.candidates.enumerated().compactMap { index, candidate in
                guard candidate.word.hasPrefix(completion.wordPrefix) else { return nil }
                return (typedWord + candidate.word.dropFirst(completion.wordPrefix.count), 0.7 - Double(index) * 0.001)
            }
        }))
    }

    /// Every word source a terminal on this Mac gets: in one place, so a source written is a source attached
    /// (`TypeAheadCommandsTests.everySourceAttached`).
    func addThisMacSources(servers: (@MainActor () -> [ServerConfiguration])?, home: String = NSHomeDirectory()) {
        if let servers { addLibrary(servers: servers) }
        addTools()
        addScreen()
        addFolder(reader: TerminalLocalFolderReader(), home: home, kind: Self.folderArgument(for:))
        addCommands(reader: TerminalLocalFolderReader(), home: home)
    }

    /// Every word source a server's terminal gets, its files read with `reader` (its own SFTP).
    func addServerSources(servers: @escaping @MainActor () -> [ServerConfiguration], reader: any TerminalFolderReader) {
        addLibrary(servers: servers)
        addTools()
        addScreen()
        addFolder(reader: reader, home: "", kind: Self.folderArgument(for:))
        // A server's SFTP paths start in its home folder.
        addCommands(reader: reader, home: "")
    }

    /// The machine's programs and the shell's own commands, for a command's first word (`TerminalTypeAheadCommands`),
    /// read with `reader`; once. `home`: this Mac's home folder, or "" for a server, whose SFTP paths start in it.
    func addCommands(reader: any TerminalFolderReader, home: String) {
        guard !wordSources.contains(where: { $0.source == .commands }) else { return }
        let source = TerminalTypeAheadCommands(machine: machine, reader: reader, home: home)
        source.onLoaded = { [weak self] in self?.lineChanged(self?.model?.typeAheadLine) }
        wordSources.append((.commands, { line in source.words(line: line) }))
    }

    /// What the folder can fill for the word being typed, by the common tools' account of the line.
    static func folderArgument(for line: String) -> TerminalFolderArgument? {
        switch CommandSpecs.completion(forLine: line)?.argumentKind {
        case .branch: .branch
        case .remote: .remote
        case .file: .file
        case .folder: .folder
        case .script: .script
        case .target: .target
        default: nil
        }
    }

    /// Words already on screen, once.
    func addScreen() {
        guard !wordSources.contains(where: { $0.source == .screen }) else { return }
        wordSources.append((.screen, { [weak self] line in
            guard let model = self?.model else { return [] }
            return TerminalTypeAheadScreen.words(line: line, screen: model.getVisibleText(lastNLines: 60))
        }))
    }

    func candidates(for typed: String) -> [TerminalTypeAheadCandidate] {
        let context = TerminalTypeAheadContext(folder: folder(), previousCommand: history.lastCommand(on: machine))
        var candidates: [TerminalTypeAheadCandidate] = []
        if settings.uses(.history) || settings.uses(.imported) {
            candidates += TerminalTypeAheadEngine.historyCandidates(typed: typed, records: history.records(for: machine),
                                                                    context: context)
                .filter { settings.uses($0.source) }
        }
        if settings.uses(.snippet) {
            let values = snippets().map { (command: $0.command, useCount: $0.useCount, lastUsed: $0.lastUsed) }
            candidates += TerminalTypeAheadEngine.snippetCandidates(typed: typed, snippets: values, context: context)
        }
        // Word by word only once something is typed: an empty line's chips are whole commands.
        if !typed.isEmpty {
            for (source, words) in wordSources where settings.uses(source) {
                candidates += TerminalTypeAheadEngine.wordCandidates(typed: typed, words: words(typed), source: source)
            }
        }
        // The on-device model only where nothing else has a command for the line.
        if settings.uses(.assistant), !typed.isEmpty,
           !candidates.contains(where: { $0.command.hasPrefix(typed) && $0.command != typed }),
           let command = assistant.command(for: typed, recent: recent, folder: folder()) {
            candidates.append(TerminalTypeAheadCandidate(command: command, score: 0.3, source: .assistant))
        }
        return candidates
    }
}
