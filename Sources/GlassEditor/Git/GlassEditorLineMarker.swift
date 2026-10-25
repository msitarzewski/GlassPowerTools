//
//  GlassEditorLineMarker.swift
//  Glass Power Tools — GlassEditor
//
//  The marks beside an open file's lines (2026-10-23: "add gutter marks"): green where lines were
//  added since the last commit, amber where they were changed, a red wedge where they were removed.
//
//  Worked out here, against the text being typed, rather than asked of git: git knows only what is
//  saved, and a mark that waits for ⌘S is a mark that is wrong while you type. Git is asked once
//  for what the file said at the last commit, and again only when that commit, or what git says
//  about the file, changes.
//

import Foundation
import Observation
import GlassEditorCore
import GlassEditorUI

@MainActor
final class GlassEditorLineMarker {
    let repository: GlassEditorGitRepository
    /// The file, absolute, on the project's machine.
    let path: String
    private weak var document: GlassEditorDocument?

    /// The file at the last commit; nil when there is nothing to compare it with.
    private var base: String?
    /// What the base was read for: when this changes, it is read again.
    private var baseFor: BaseKey?
    private var reading: Task<Void, Never>?
    private var comparing: Task<Void, Never>?
    private var stopped = false

    private struct BaseKey: Equatable {
        var ready: Bool
        var commit: String?
        var change: GlassEditorGitChange?
    }

    /// The most text compared, in UTF-16 units; a larger file has no marks.
    static let textCeiling = 4 * 1024 * 1024
    /// How long typing pauses before the marks catch up.
    static let pause: Duration = .milliseconds(150)

    init(document: GlassEditorDocument, repository: GlassEditorGitRepository, path: String) {
        self.document = document
        self.repository = repository
        self.path = path
    }

    func start() {
        watchRepository()
        watchText()
        baseMayHaveChanged()
    }

    func stop() {
        stopped = true
        reading?.cancel()
        comparing?.cancel()
        if document?.model.lineChanges.isEmpty == false { document?.model.lineChanges = [] }
    }

    /// Waits for the marks in flight (tests).
    func settled() async {
        while !stopped {
            if let reading { await reading.value }
            if let comparing { await comparing.value }
            if reading == nil, comparing == nil { return }
        }
    }

    // MARK: Watching

    private func watchRepository() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.repository.state
            _ = self.repository.status.commit
            _ = self.repository.change(atPath: self.path)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                self.baseMayHaveChanged()
                self.watchRepository()
            }
        }
    }

    private func watchText() {
        withObservationTracking { [weak self] in
            _ = self?.document?.model.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                self.compareSoon()
                self.watchText()
            }
        }
    }

    // MARK: The last commit

    private func baseMayHaveChanged() {
        let key = BaseKey(ready: repository.state == .ready, commit: repository.status.commit,
                          change: repository.change(atPath: path))
        guard key != baseFor else { return }
        baseFor = key
        reading?.cancel()
        reading = Task { [weak self] in
            guard let self else { return }
            let text = await self.repository.committedText(ofPath: self.path)
            guard !Task.isCancelled, !self.stopped else { return }
            self.base = text
            self.reading = nil
            self.compareSoon(after: .zero)
        }
    }

    // MARK: Comparing

    private func compareSoon(after pause: Duration = GlassEditorLineMarker.pause) {
        comparing?.cancel()
        comparing = Task { [weak self] in
            if pause > .zero { try? await Task.sleep(for: pause) }
            guard let self, !Task.isCancelled else { return }
            await self.compare()
            if !Task.isCancelled { self.comparing = nil }
        }
    }

    private func compare() async {
        guard let model = document?.model else { return }
        guard let base, model.utf16Length <= Self.textCeiling else {
            if !model.lineChanges.isEmpty { model.lineChanges = [] }
            return
        }
        let text = model.text
        // Off the main thread: a long file with changes far apart is real work.
        let changes = await Task.detached(priority: .userInitiated) {
            LineChanges.between(base: base, current: text)
        }.value
        guard !Task.isCancelled, !stopped, model.text == text else { return }
        if changes != model.lineChanges { model.lineChanges = changes }
    }
}
