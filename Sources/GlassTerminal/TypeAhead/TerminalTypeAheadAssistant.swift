//
//  TerminalTypeAheadAssistant.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead's on-device AI source (D102, 2026-11-06): when nothing else has a command for the line, the model the
//  AI Assistant uses (Apple's, on this device; nothing leaves it) is asked for the likely next one, from the last few
//  commands run and the folder. Off unless turned on in Settings ▸ Suggestions; asked only once typing pauses, one
//  question at a time, each answer kept for the same line. `tasks/2026-11/2026-11-06_type-ahead.md`, source 8.
//

import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class TerminalTypeAheadAssistant {
    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "type-ahead")
    /// How long typing must pause before the model is asked.
    nonisolated static let pause: Duration = .milliseconds(600)

    private var pending: Task<Void, Never>?
    private var answers: [String: String] = [:]
    /// The model answered: the line's suggestion can be worked out again.
    var onAnswer: (() -> Void)?

    /// The model's command for `typed`, once it has answered; asks it (after a pause) when it hasn't.
    func command(for typed: String, recent: [String], folder: String?) -> String? {
        let key = [typed, folder ?? "", recent.suffix(3).joined(separator: "\n")].joined(separator: "\u{0}")
        if let answer = answers[key] {
            return answer.hasPrefix(typed) && answer != typed ? answer : nil
        }
        ask(key: key, typed: typed, recent: Array(recent.suffix(8)), folder: folder)
        return nil
    }

    private func ask(key: String, typed: String, recent: [String], folder: String?) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            let answer = await Self.ask(typed: typed, recent: recent, folder: folder)
            guard !Task.isCancelled, let self else { return }
            self.answers[key] = answer ?? ""
            if self.answers.count > 200 { self.answers.removeAll() }
            if answer != nil { self.onAnswer?() }
        }
    }

    /// The model's one-line answer, kept only when it continues what's typed and carries no secret.
    nonisolated static func ask(typed: String, recent: [String], folder: String?) async -> String? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.availability == .available else { return nil }
        let session = LanguageModelSession(instructions: """
            You complete shell commands. Given the commands just run and the folder, reply with the single most \
            likely next command, which must begin exactly with the text typed so far. Reply with the command alone: \
            no explanation, no quotes, no code fences.
            """)
        let prompt = """
            Commands just run, oldest first:
            \(recent.isEmpty ? "(none)" : recent.joined(separator: "\n"))
            Folder: \(folder ?? "unknown")
            Typed so far: \(typed)
            """
        do {
            let response = try await session.respond(to: prompt)
            return cleaned(response.content, typed: typed)
        } catch {
            logger.notice("The on-device model gave no suggestion: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// The answer's first line, fences and quotes taken off; nil unless it continues `typed` and may be offered.
    nonisolated static func cleaned(_ answer: String, typed: String) -> String? {
        var line = answer.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") } ?? ""
        for mark in ["`", "\"", "'"] where line.hasPrefix(mark) && line.hasSuffix(mark) && line.count > 1 {
            line = String(line.dropFirst().dropLast())
        }
        if line.hasPrefix("$ ") { line = String(line.dropFirst(2)) }
        guard line.hasPrefix(typed), line != typed, line.count <= 300,
              TerminalCommandHistory.keeps(line) else { return nil }
        return line
    }
}
