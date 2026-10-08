//
//  TerminalFindBar.swift
//  Glass Power Tools — GlassTerminal
//
//  The one find bar for every terminal (2026-10-08). A Mac's local pane and every SSH terminal had
//  a bar each, and the two had drifted: different labels, Return going different ways, and neither
//  closing on Escape. Both now show this one, over the top of the terminal.
//

import SwiftUI

struct TerminalFindBar: View {
    @Bindable var controller: TerminalFindController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                field
                status
                stepButtons
                closeButton
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("terminal-find-message")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 280, maxWidth: 460)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .onAppear { fieldFocused = true }
        .onChange(of: controller.focusRequest) { _, _ in fieldFocused = true }
    }

    private var field: some View {
        TextField("Find", text: $controller.query)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            #endif
            .focused($fieldFocused)
            .onSubmit {
                controller.step(.older)
                // Return again goes on to the next older match.
                fieldFocused = true
            }
            .onKeyPress(.escape) {
                controller.close()
                return .handled
            }
            #if os(macOS)
            .onExitCommand { controller.close() }
            #endif
            .accessibilityLabel("Find in terminal")
            .accessibilityIdentifier("terminal-find-field")
    }

    @ViewBuilder
    private var status: some View {
        if controller.isSearching {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Searching")
        } else if let label = controller.outcome?.label, !label.isEmpty {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("terminal-find-count")
        }
    }

    private var stepButtons: some View {
        HStack(spacing: 4) {
            Button {
                controller.step(.older)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(minWidth: 24, minHeight: 24)
            }
            .help("Older match")
            .accessibilityLabel("Older match")
            .accessibilityIdentifier("terminal-find-older")

            Button {
                controller.step(.newer)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(minWidth: 24, minHeight: 24)
            }
            .help("Newer match")
            .accessibilityLabel("Newer match")
            .accessibilityIdentifier("terminal-find-newer")
        }
        .buttonStyle(.plain)
        .disabled(controller.query.isEmpty)
    }

    private var closeButton: some View {
        Button {
            controller.close()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        #if !os(macOS)
        .frame(minWidth: 44, minHeight: 44)
        #endif
        .contentShape(Circle())
        .help("Close")
        .accessibilityLabel("Close find")
        .accessibilityIdentifier("terminal-find-close")
    }

    /// A failure says what to do; otherwise the source's limit, if it has one.
    private var message: String? {
        controller.outcome?.failure ?? controller.notice
    }
}
