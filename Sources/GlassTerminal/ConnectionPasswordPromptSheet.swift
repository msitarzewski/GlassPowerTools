//
//  ConnectionPasswordPromptSheet.swift
//  Glass Power Tools — GlassTerminal
//
//  Moved verbatim from glas.sh's ConnectionManagerView.swift (lines 3519-3646) on 2026-09-10 when the shell
//  took over the connection library. Password prompt used by the connect flow.
//

import SwiftUI

struct ConnectionPasswordPromptSheet: View {
    let server: ServerConfiguration
    let savesPassword: Bool
    let onSubmit: @MainActor (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var failureMessage: String?
    @State private var isSubmitting = false
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "key.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Password Required")
                        .font(.title2.weight(.semibold))

                    Text(promptMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("Password", text: $password)
                        .textContentType(.init(rawValue: ""))
                        .textFieldStyle(.roundedBorder)
                        .focused($passwordIsFocused)
                        .disabled(isSubmitting)
                        .onSubmit(submit)
                        .accessibilityIdentifier("connection-password-prompt.password")

                    if savesPassword {
                        Label("This password will be stored securely in Keychain.", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let failureMessage {
                        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("connection-password-prompt.error")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    password = ""
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)

                Button(actionTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isSubmitting)
                .accessibilityIdentifier("connection-password-prompt.submit")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 480)
        .onAppear {
            passwordIsFocused = true
        }
        .onDisappear {
            submissionTask?.cancel()
            submissionTask = nil
            password = ""
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var promptMessage: String {
        let endpoint = "\(server.username)@\(server.host):\(server.port)"
        if savesPassword {
            return "Enter the password for \(endpoint) to save it and connect."
        }
        return "Enter the password for \(endpoint) to connect."
    }

    private var actionTitle: String {
        if isSubmitting {
            return savesPassword ? "Saving…" : "Connecting…"
        }
        return savesPassword ? "Save & Connect" : "Connect"
    }

    private func submit() {
        guard !password.isEmpty, !isSubmitting else { return }
        failureMessage = nil
        isSubmitting = true
        let submittedPassword = password
        submissionTask = Task { @MainActor in
            let failure = await onSubmit(submittedPassword)
            guard !Task.isCancelled else { return }
            isSubmitting = false
            if let failure {
                failureMessage = failure
                passwordIsFocused = true
            } else {
                password = ""
                dismiss()
            }
            submissionTask = nil
        }
    }
}

// MARK: - Tailscale Device Row

