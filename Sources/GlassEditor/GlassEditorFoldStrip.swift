//
//  GlassEditorFoldStrip.swift
//  Glass Power Tools — GlassEditor
//
//  The editor's strip below an iPhone Duo's fold (D93, 2026-10-31): stood like a laptop, the code sits
//  above the fold, and here, between the fold and the keyboard's keys, are the keys a code editor
//  wants and a phone's keyboard hides — Tab, brackets and quotes, the arrows, Undo, Redo and Find —
//  as Working Copy puts them below its fold. Each is one undoable edit at the cursor.
//

#if os(iOS)
import SwiftUI
import GlassEditorCore
import GlassEditorUI

struct GlassEditorFoldStrip: View {
    let model: GlassEditorModel
    let find: @MainActor () -> Void

    /// The characters, as they are typed.
    private static let characters = ["{", "}", "(", ")", "[", "]", "\"", "'", "`", "=", ";", ":", "/", "<", ">", "|", "$", "#"]

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    key("Tab", label: "⇥") { insert("\t") }
                    ForEach(Self.characters, id: \.self) { character in
                        key(character, label: character) { insert(character) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 4) {
                icon("Left", "chevron.left") { move(-1) }
                icon("Right", "chevron.right") { move(1) }
                icon("Undo", "arrow.uturn.backward") { _ = model.undo() }
                icon("Redo", "arrow.uturn.forward") { _ = model.redo() }
                icon("Find", "magnifyingglass") { find() }
            }
        }
        .font(.body.monospaced())
        .accessibilityIdentifier("editor-fold-strip")
    }

    private func key(_ name: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(minWidth: 32, minHeight: 36)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(name == label ? "Type \(name)" : name)
    }

    private func icon(_ name: String, _ symbol: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(name, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .frame(width: 36, height: 36)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    /// Types `text` over the selection and puts the cursor after it.
    private func insert(_ text: String) {
        let range = model.selectedRange
        guard (try? model.apply(TextEdit(replacementRange: range, text: text), intent: .typing)) != nil else { return }
        let caret = range.lowerBound + text.utf16.count
        model.reveal(caret..<caret)
    }

    /// Moves the cursor one character, from the selection's near end.
    private func move(_ step: Int) {
        let range = model.selectedRange
        let from = step < 0 ? range.lowerBound : range.upperBound
        let caret = max(0, min(model.text.utf16.count, from + step))
        model.reveal(caret..<caret)
    }
}
#endif
