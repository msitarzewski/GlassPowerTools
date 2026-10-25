//
//  TerminalPasteReviewSheet.swift
//  Glass Power Tools — GlassTerminal
//

import SwiftUI
import GlassTerminalEmulator

/// A paste the terminal holds for review: several lines, or more than a line's worth
/// (`SwiftTermPastePolicy`). One sheet for a connection's terminal and a Mac's local shell; there were
/// two, the same but for their wording.
///
/// Text a terminal program wrapped to fit its window — Claude Code's and Codex's replies — can have
/// its lines joined again (`TerminalWrappedPaste`; the owner, 2026-10-19). The checkbox is shown only
/// for such text, starts as it was last left, and is remembered on this device.
struct TerminalPasteReviewSheet: View {
    @Environment(SettingsManager.self) private var settingsManager
    let request: SwiftTermPasteReview
    let onCancel: () -> Void
    let onPaste: (String) -> Void
    private let repair: TerminalWrappedPaste.Repair?
    @State private var editedText: String
    @State private var joinsWrappedLines = false

    init(
        request: SwiftTermPasteReview,
        onCancel: @escaping () -> Void,
        onPaste: @escaping (String) -> Void
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onPaste = onPaste
        repair = request.exceedsMaximumSize ? nil : TerminalWrappedPaste.repair(request.content)
        _editedText = State(initialValue: request.content)
    }

    private var editedByteCount: Int { editedText.utf8.count }
    private var canPaste: Bool {
        !request.exceedsMaximumSize && SwiftTermPastePolicy.isAllowed(editedText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(request.bracketedPasteMode
                    ? "The remote program requested bracketed paste. Review the content before it is sent."
                    : "Multiline or large pasted content can execute multiple shell commands. Review it before sending.")
                    .foregroundStyle(.secondary)

                LabeledContent("Original size", value: "\(request.byteCount) bytes, \(request.lineCount) lines")

                if request.exceedsMaximumSize {
                    ContentUnavailableView(
                        "Paste Too Large",
                        systemImage: "doc.badge.ellipsis",
                        description: Text("The clipboard exceeds the \(SwiftTermPastePolicy.maximumPayloadBytes)-byte terminal paste limit. Nothing was sent.")
                    )
                } else {
                    if let repair {
                        wrappedLines(repair)
                    }
                    TextEditor(text: $editedText)
                        .font(.system(.body, design: .monospaced))
                        .terminalTextInputDefaults()
                        .accessibilityLabel("Editable terminal paste content")
                        .accessibilityIdentifier("terminal-paste-text")
                    Text("\(editedByteCount) of \(SwiftTermPastePolicy.maximumPayloadBytes) bytes")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(editedByteCount > SwiftTermPastePolicy.maximumPayloadBytes ? .red : .secondary)
                }
            }
            .padding()
            .navigationTitle("Review Terminal Paste")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                if !request.exceedsMaximumSize {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Paste") { onPaste(editedText) }
                            // ⌘↩ sends it: Return is the text's own, a new line in what is pasted
                            // (the owner, 2026-10-14: "should allow a command return to submit").
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!canPaste)
                    }
                }
            }
        }
        // A Mac sheet's minimum. On an iPhone it made the sheet 560 points wide on a 402-point
        // screen, clipped on both sides with Cancel, Paste and the switch off its edges (found by
        // TerminalPasteUITests, 2026-10-24); a phone or iPad sheet takes the size it is given.
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
        #endif
        .interactiveDismissDisabled()
        .onAppear {
            guard let repair, settingsManager.joinsWrappedPastes else { return }
            joinsWrappedLines = true
            editedText = repair.text
        }
    }

    /// The checkbox, and what it does to this paste.
    private func wrappedLines(_ repair: TerminalWrappedPaste.Repair) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Join Wrapped Lines", isOn: Binding(
                get: { joinsWrappedLines },
                set: { join in
                    joinsWrappedLines = join
                    // The text as it came, or joined: an edit made since is replaced.
                    editedText = join ? repair.text : request.content
                    settingsManager.joinsWrappedPastes = join
                    settingsManager.saveSettings()
                }))
                .accessibilityIdentifier("terminal-paste-join-wrapped")
            Text("These lines look wrapped to fit a window \(repair.width) columns wide. Joined, \(repair.originalLineCount) lines become \(repair.lineCount). Remembered for the next paste.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
