//
//  RecordEditorView.swift
//  glassdb
//
//  Full-screen modal for editing a single database row.
//  Staging model: edits highlighted, batched, applied on explicit save.
//

import SwiftUI
import GlassDBKit
import GlassEditorCore
import GlassEditorUI
import GlassLayers

enum RecordJSONText {
    static func compact(_ text: String) throws -> String {
        _ = try object(from: text)

        var result = String()
        result.reserveCapacity(text.utf8.count)
        var isInsideString = false
        var isEscaped = false

        for character in text {
            if isInsideString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
                result.append(character)
            } else if !jsonWhitespace.contains(character) {
                result.append(character)
            }
        }
        return result
    }

    static func pretty(_ text: String) throws -> String {
        _ = try object(from: text)

        let characters = Array(text)
        var result = String()
        result.reserveCapacity(text.utf8.count + 32)
        var indent = 0
        var expandedContainers: [Bool] = []
        var isInsideString = false
        var isEscaped = false

        func appendLineBreak() {
            result.append("\n")
            result.append(String(repeating: "  ", count: indent))
        }

        for (index, character) in characters.enumerated() {
            if isInsideString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
                result.append(character)
            case "{", "[":
                result.append(character)
                let closing: Character = character == "{" ? "}" : "]"
                let next = characters[(index + 1)...].first { !jsonWhitespace.contains($0) }
                let expands = next != closing
                expandedContainers.append(expands)
                if expands {
                    indent += 1
                    appendLineBreak()
                }
            case "}", "]":
                if expandedContainers.popLast() == true {
                    indent = max(0, indent - 1)
                    appendLineBreak()
                }
                result.append(character)
            case ",":
                result.append(character)
                appendLineBreak()
            case ":":
                result.append(": ")
            default:
                if !jsonWhitespace.contains(character) {
                    result.append(character)
                }
            }
        }
        return result
    }

    static func isEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = try? object(from: lhs),
              let right = try? object(from: rhs) else { return false }
        guard let leftObject = left as? NSObject else { return false }
        return leftObject.isEqual(right)
    }

    private static let jsonWhitespace: Set<Character> = [" ", "\t", "\n", "\r"]

    private static func object(from text: String) throws -> Any {
        try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: [.fragmentsAllowed]
        )
    }
}

// MARK: - Staged Edit Model

struct StagedEdit: Identifiable {
    let id = UUID()
    let columnIndex: Int
    let columnName: String
    let columnType: String
    /// The engine whose spelling `columnType` is in, when it is known.
    ///
    /// Only the size rules need it, and only for the two type names the engines disagree about:
    /// MySQL's bare `text` and `blob` cap at 65,535 **bytes**, while the same names mean roughly a
    /// gigabyte on PostgreSQL and SQLite. `ColumnTypeConstraint.parse` therefore leaves those two
    /// unconstrained when this is `nil`, which is the safe direction — a missing limit only fails
    /// to warn, whereas a borrowed one would refuse values that store perfectly well.
    var dialect: DatabaseDialect?
    let isPrimaryKey: Bool
    let isNullable: Bool
    let isUnsigned: Bool
    let isGenerated: Bool
    let defaultValue: String?
    let originalValue: DatabaseValue
    var editText: String
    var isNull: Bool
    var useDefault: Bool

    var isModified: Bool {
        if isGenerated { return false }
        if useDefault { return false }
        if isNull != originalValue.isNull { return true }
        if isNull { return false }
        if isJSON {
            return !RecordJSONText.isEquivalent(editText, originalValue.displayString)
        }
        return editText != originalValue.displayString
    }

    var typeLower: String { columnType.lowercased() }
    var isJSON: Bool {
        let baseType = typeLower.split(separator: "(", maxSplits: 1).first.map(String.init) ?? typeLower
        return baseType == "json" || baseType == "jsonb"
    }
    var isLargeText: Bool { typeLower.contains("text") || typeLower.contains("blob") }
    /// Only MySQL's boolean convention, which is `tinyint(1)` — never a bare `tinyint`, which is
    /// an integer from -128 through 127. Until 2026-09-12 a bare `tinyint` was treated as boolean:
    /// a score column rendered as a toggle reading "False", and saving would have written 0 over
    /// the stored value. (MySQL 8.0.19+ drops display widths, so a `tinyint(4)` is reported as
    /// plain `tinyint` while `tinyint(1)` keeps its width precisely because it means boolean.)
    var isBool: Bool { typeLower.contains("bool") || typeLower.hasPrefix("tinyint(1)") }
    var isBinary: Bool { typeLower.contains("binary") || typeLower.contains("blob") || typeLower.hasPrefix("bit") }

    /// What the column's declared type permits — `varchar(40)`, `decimal(10,2)`, `tinyint`.
    var constraint: ColumnTypeConstraint? {
        ColumnTypeConstraint.parse(columnType, isUnsigned: isUnsigned, dialect: dialect)
    }

    /// How full the field is, for the live counter. Nil when the type has no size to show.
    var usage: (used: Int, limit: Int)? {
        guard !isNull, !useDefault, !isGenerated else { return nil }
        return constraint?.usage(of: editText)
    }

    var validationError: String? {
        guard !isGenerated, !useDefault else { return nil }
        if isNull {
            return isNullable ? nil : "‘\(columnName)’ cannot be NULL."
        }
        do {
            _ = try boundValue()
        } catch {
            return error.localizedDescription
        }
        // The size check runs after the type check, so "abc" in an int reports that it is not a
        // number rather than that it is out of range.
        return constraint?.overflowMessage(for: editText, column: columnName)
    }

    static func initialValue(for column: ColumnInfo, columnIndex: Int,
                             dialect: DatabaseDialect? = nil) -> StagedEdit {
        let usesDefault = column.isGenerated || column.defaultValue != nil
        return StagedEdit(
            columnIndex: columnIndex,
            columnName: column.name,
            columnType: column.type,
            dialect: dialect,
            isPrimaryKey: column.isPrimaryKey,
            isNullable: column.isNullable,
            isUnsigned: column.isUnsigned,
            isGenerated: column.isGenerated,
            defaultValue: column.defaultValue,
            originalValue: .null,
            editText: "",
            isNull: column.isNullable || usesDefault,
            useDefault: usesDefault
        )
    }

    func boundValue() throws -> DatabaseValue {
        if isGenerated {
            throw RecordValueError.invalidValue(column: columnName, expected: "a server-generated value that cannot be edited")
        }
        if isNull { return .null }
        let value = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseType = typeLower.split(separator: "(", maxSplits: 1).first.map(String.init) ?? typeLower

        if isBool {
            switch value.lowercased() {
            case "1", "true": return .bool(true)
            case "0", "false": return .bool(false)
            default: throw RecordValueError.invalidValue(column: columnName, expected: "true, false, 1, or 0")
            }
        }
        if ["tinyint", "smallint", "mediumint", "int", "integer", "bigint"].contains(baseType) {
            if isUnsigned, let parsed = UInt64(value) { return .uint(parsed) }
            if !isUnsigned, let parsed = Int64(value) { return .int(parsed) }
            throw RecordValueError.invalidValue(column: columnName, expected: isUnsigned ? "an unsigned integer" : "an integer")
        }
        if ["decimal", "numeric"].contains(baseType) {
            guard Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) != nil else {
                throw RecordValueError.invalidValue(column: columnName, expected: "an exact decimal number")
            }
            return .decimal(value)
        }
        if ["float", "double", "real"].contains(baseType) {
            guard let parsed = Double(value), parsed.isFinite else {
                throw RecordValueError.invalidValue(column: columnName, expected: "a finite number")
            }
            return .double(parsed)
        }
        if baseType == "json" || baseType == "jsonb" {
            guard let compact = try? RecordJSONText.compact(value) else {
                throw RecordValueError.invalidValue(column: columnName, expected: "valid JSON")
            }
            return .json(compact)
        }
        if baseType == "bit" {
            let bits = value.filter { !$0.isWhitespace }
            guard !bits.isEmpty, bits.allSatisfy({ $0 == "0" || $0 == "1" }) else {
                throw RecordValueError.invalidValue(column: columnName, expected: "a sequence of 0 and 1 bits")
            }
            var padded = bits
            let remainder = padded.count % 8
            if remainder != 0 { padded = String(repeating: "0", count: 8 - remainder) + padded }
            var bytes = Data()
            var index = padded.startIndex
            while index < padded.endIndex {
                let end = padded.index(index, offsetBy: 8)
                guard let byte = UInt8(padded[index..<end], radix: 2) else {
                    throw RecordValueError.invalidValue(column: columnName, expected: "a sequence of 0 and 1 bits")
                }
                bytes.append(byte)
                index = end
            }
            return .bit(bytes)
        }
        if isBinary {
            guard let data = Data(base64Encoded: value) else {
                throw RecordValueError.invalidValue(column: columnName, expected: "Base64-encoded binary data")
            }
            return .data(data)
        }
        let temporalKind: DatabaseTemporalValue.Kind?
        switch baseType {
        case "date": temporalKind = .date
        case "time": temporalKind = .time
        case "datetime": temporalKind = .dateTime
        case "timestamp": temporalKind = .timestamp
        case "year": temporalKind = .year
        default: temporalKind = nil
        }
        if let temporalKind {
            // Until 2026-09-12 anything at all was accepted here and failed at the server.
            if let message = ColumnValueFormat.parse(columnType)?.formatMessage(for: value, column: columnName) {
                throw RecordValueError.malformed(message)
            }
            return .temporal(DatabaseTemporalValue(rawValue: value, kind: temporalKind))
        }
        // `enum`, `set` and `uuid` arrive here as strings; the declared type says what they allow.
        if let message = ColumnValueFormat.parse(columnType)?.formatMessage(for: value, column: columnName) {
            throw RecordValueError.malformed(message)
        }
        return .string(editText)
    }
}

enum RecordValueError: LocalizedError {
    case invalidValue(column: String, expected: String)
    /// Already a complete sentence naming its column, from `ColumnValueFormat`.
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let column, let expected):
            return "‘\(column)’ must contain \(expected)."
        case .malformed(let message):
            return message
        }
    }
}

// MARK: - Record Editor

struct RecordEditorView: View {
    @Environment(SettingsManager.self) private var settingsManager
    /// The window's own settings (W24): a sheet takes its window's.
    @Environment(\.glassWindowOverrides) private var windowSettings
    @Environment(\.colorScheme) private var colorScheme

    enum RecordEditorMode {
        case edit(rowIndex: Int, originalRow: [DatabaseValue])
        case add
    }

    let columns: [ColumnInfo]
    let mode: RecordEditorMode
    /// The connected engine, so size rules can tell MySQL's 64 KiB `text` from PostgreSQL's.
    var dialect: DatabaseDialect?
    let onSave: ([StagedEdit], RecordEditorMode) -> Void
    let onDiscard: () -> Void

    /// The window's settings over All Databases' (W24).
    private var windowProfile: DatabaseWindowProfile {
        DatabaseWindowProfile.resolved(windowSettings, settings: settingsManager)
    }

    private var isAddMode: Bool {
        if case .add = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .edit(let rowIndex, _): return "Edit Row \(rowIndex + 1)"
        case .add: return "Add Row"
        }
    }

    @State private var edits: [StagedEdit] = []
    @State private var jsonErrors: [Int: String] = [:]
    @State private var confirmingDiscard = false
    // One GlassEditorKit model per JSON column, created alongside the staged
    // edits. The staging model in `edits` stays the source of truth; the
    // editor models mirror it so RecordJSONText-based dirty detection and
    // save semantics are untouched.
    @State private var jsonEditorModels: [Int: GlassEditorModel] = [:]
    @State private var jsonFieldHeights: [Int: CGFloat] = [:]
    @State private var jsonFieldRenderedHeights: [Int: CGFloat] = [:]
    @State private var jsonFieldDragStarts: [Int: CGFloat] = [:]

    private var hasChanges: Bool {
        edits.contains(where: \.isModified)
    }

    private var changeCount: Int {
        edits.filter(\.isModified).count
    }

    private var validationErrors: [Int: String] {
        Dictionary(uniqueKeysWithValues: edits.enumerated().compactMap { index, edit in
            guard let message = jsonErrors[index] ?? edit.validationError else { return nil }
            return (index, message)
        })
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty && (isAddMode || hasChanges)
    }

    private var hasUnsavedChanges: Bool {
        switch mode {
        case .edit:
            return hasChanges
        case .add:
            return edits.enumerated().contains { index, edit in
                guard columns.indices.contains(index) else { return true }
                let initial = StagedEdit.initialValue(for: columns[index], columnIndex: index,
                                                      dialect: dialect)
                return edit.editText != initial.editText
                    || edit.isNull != initial.isNull
                    || edit.useDefault != initial.useDefault
            }
        }
    }

    var body: some View {
        NavigationStack {
            editorFields
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { requestDiscard() }
                            .keyboardShortcut(.cancelAction)
                            .help("Discard changes and close the record editor")
                            .accessibilityIdentifier("record-editor-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isAddMode ? "Insert" : "Apply \(changeCount > 0 ? "(\(changeCount))" : "")") {
                            submit()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                        .help(isAddMode ? "Stage this row for insertion" : "Stage the modified fields for update")
                        .accessibilityIdentifier("record-editor-save")
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 680, maxWidth: 1100)
        .frame(minHeight: 520, idealHeight: 640, maxHeight: 960)
        #endif
        .onAppear { initializeEdits() }
        .onChange(of: colorScheme) { _, newScheme in
            let theme: EditorTheme = newScheme == .dark ? .glassDark : .glassLight
            for model in jsonEditorModels.values {
                model.theme = theme
            }
        }
        .alert("Discard Changes?", isPresented: $confirmingDiscard) {
            Button("Keep Editing", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button("Discard", role: .destructive) { onDiscard() }
        } message: {
            Text("Your staged record changes have not been applied.")
        }
    }

    @ViewBuilder
    private var editorFields: some View {
        #if os(macOS)
        Form {
            fields
        }
        .formStyle(.grouped)
        .controlSize(.regular)
        #else
        List {
            fields
        }
        #endif
    }

    @ViewBuilder
    private var fields: some View {
        ForEach(Array(edits.enumerated()), id: \.element.id) { idx, edit in
            fieldSection(edit: edit, index: idx)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        if isAddMode {
            onSave(edits.filter { !$0.useDefault }, mode)
        } else {
            onSave(edits.filter(\.isModified), mode)
        }
    }

    private func requestDiscard() {
        if hasUnsavedChanges {
            confirmingDiscard = true
        } else {
            onDiscard()
        }
    }

    // MARK: - Field Section

    @ViewBuilder
    private func fieldSection(edit: StagedEdit, index: Int) -> some View {
        Section {
            if edit.isGenerated {
                Label("Generated by server", systemImage: "gearshape.2")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isAddMode && edit.useDefault {
                Label(
                    edit.defaultValue.map { "Use default: \($0)" } ?? "Use column default",
                    systemImage: "arrow.turn.down.right"
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Provide Value") {
                    edits[index].useDefault = false
                    edits[index].isNull = false
                }
                if edit.isNullable {
                    Button("Insert NULL") {
                        edits[index].useDefault = false
                        edits[index].isNull = true
                    }
                }
            } else if edit.isBool {
                boolField(edit: edit, index: index)
            } else if edit.isJSON {
                jsonField(edit: edit, index: index)
            } else if edit.isLargeText {
                largeTextField(edit: edit, index: index)
            } else {
                standardField(edit: edit, index: index)
            }

            if let validationError = validationErrors[index] {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid value for \(edit.columnName): \(validationError)")
                    .accessibilityIdentifier("record-editor-error-\(edit.columnName)")
            }
        } header: {
            HStack(spacing: 6) {
                Text(edit.columnName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if edit.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if edit.isGenerated {
                    Text("GENERATED")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(edit.columnType)
                    .foregroundStyle(.secondary)
                Spacer()
                if edit.isJSON && !edit.isNull && !edit.useDefault {
                    Button("Format") { formatJSON(index: index) }
                        .font(.caption)
                        .fixedSize()
                    Button("Validate") { validateJSON(edits[index].editText, index: index) }
                        .font(.caption)
                        .fixedSize()
                }
                // Typing clears NULL again, so this is a one-way control and belongs beside the
                // column's other tools rather than in a row of its own under the field.
                if edit.isNullable && !edit.isPrimaryKey && !edit.isNull {
                    Button("Set to NULL") {
                        edits[index].isNull = true
                        edits[index].useDefault = false
                        edits[index].editText = ""
                        jsonErrors.removeValue(forKey: index)
                    }
                    .font(.caption)
                    .fixedSize()
                    .accessibilityIdentifier("record-editor-null-\(edit.columnName)")
                }
                if isAddMode && !edit.useDefault && edit.defaultValue != nil {
                    Button("Use Column Default") {
                        edits[index].useDefault = true
                        edits[index].isNull = true
                        edits[index].editText = ""
                        jsonErrors.removeValue(forKey: index)
                    }
                    .font(.caption)
                    .fixedSize()
                    .accessibilityIdentifier("record-editor-default-\(edit.columnName)")
                }
                if let usage = edit.usage, usage.used >= max(0, usage.limit - 10) {
                    // Quiet until it matters: shown only near the limit, amber at it, red past it.
                    Text("\(usage.used)/\(usage.limit)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(usage.used > usage.limit ? .red : .orange)
                        .accessibilityLabel("\(usage.used) of \(usage.limit) used in \(edit.columnName)")
                        .accessibilityIdentifier("record-editor-counter-\(edit.columnName)")
                }
                if edit.isModified {
                    Text("Modified")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Standard Field

    private func standardField(edit: StagedEdit, index: Int) -> some View {
        TextField(
            "Value",
            text: fieldBinding(index: index),
            prompt: edit.isNull ? Text("NULL") : nil
        )
        .labelsHidden()
        .font(.system(.body, design: .monospaced))
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .autocorrectionDisabled()
        .databaseNoAutocapitalization()
        .databaseASCIICapableKeyboard()
        .accessibilityLabel("\(edit.columnName), \(edit.columnType)")
        .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
        .help("Enter a \(edit.columnType) value for \(edit.columnName)")
    }

    // MARK: - Large Text Field

    private func largeTextField(edit: StagedEdit, index: Int) -> some View {
        TextField(
            "Value",
            text: fieldBinding(index: index),
            prompt: edit.isNull ? Text("NULL") : nil,
            axis: .vertical
        )
        .labelsHidden()
        .font(.system(.body, design: .monospaced))
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(3...10)
        .autocorrectionDisabled()
        .databaseNoAutocapitalization()
        .databaseASCIICapableKeyboard()
        .accessibilityLabel("\(edit.columnName), \(edit.columnType)")
        .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
        .help("Enter a \(edit.columnType) value for \(edit.columnName)")
    }

    // MARK: - Boolean Field

    private func boolField(edit: StagedEdit, index: Int) -> some View {
        let isTrue = edit.editText == "1" || edit.editText.lowercased() == "true"
        let displayValue = edit.isNull ? "NULL" : (isTrue ? "True" : "False")

        return HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { !edit.isNull && isTrue },
                    set: { value in
                        edits[index].editText = value ? "1" : "0"
                        edits[index].isNull = false
                        edits[index].useDefault = false
                    }
                )
            )
            .labelsHidden()
            .accessibilityLabel("\(edit.columnName), Boolean value")
            .accessibilityValue(displayValue)
            .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
            .help("Toggle the Boolean value for \(edit.columnName)")
            Text(displayValue)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - JSON Field

    @ViewBuilder
    private func jsonField(edit: StagedEdit, index: Int) -> some View {
        if edit.isNull {
            TextField(
                "Value",
                text: fieldBinding(index: index),
                prompt: Text("NULL")
            )
            .labelsHidden()
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .autocorrectionDisabled()
            .databaseNoAutocapitalization()
            .databaseASCIICapableKeyboard()
            .accessibilityLabel("\(edit.columnName), JSON")
            .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
            .help("Enter valid JSON for \(edit.columnName)")
        } else {
            if let model = jsonEditorModels[index] {
                // Until the user drags, the field autosizes to content within
                // 120–300. A drag pins an explicit height anchored at the
                // rendered height, so the first drag never jumps.
                let pinnedHeight = jsonFieldHeights[index]
                GlassEditorView(model: model)
                    .frame(
                        minHeight: pinnedHeight ?? 120,
                        maxHeight: pinnedHeight ?? 300
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The gutter overlay draws outside the capped frame on
                    // macOS 14+ no-clip views; the field owns its bounds.
                    .clipped()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        jsonFieldRenderedHeights[index] = height
                    }
                    .accessibilityLabel("\(edit.columnName), JSON")
                    .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
                    .help("Enter valid JSON for \(edit.columnName)")
                    .onChange(of: model.text) { _, newText in
                        // Route through the shared binding so staging
                        // semantics (isNull/useDefault/error clearing)
                        // stay identical to typed edits.
                        guard edits[index].editText != newText else { return }
                        fieldBinding(index: index).wrappedValue = newText
                    }

                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 40, height: 4)
                    Spacer()
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .accessibilityLabel("Resize \(edit.columnName) editor")
                .highPriorityGesture(
                    // Global space: the pill travels with the field's bottom
                    // edge, so local translation would feed back into the
                    // height it is changing.
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = jsonFieldDragStarts[index]
                                ?? jsonFieldRenderedHeights[index]
                                ?? 300
                            jsonFieldDragStarts[index] = start
                            jsonFieldHeights[index] = min(800, max(120, start + value.translation.height))
                        }
                        .onEnded { _ in
                            jsonFieldDragStarts.removeValue(forKey: index)
                        }
                )
            } else {
                // Defensive fallback only; models are created with the edits.
                TextEditor(text: fieldBinding(index: index))
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .databaseNoAutocapitalization()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 300)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(edit.columnName), JSON")
                    .accessibilityIdentifier("record-editor-field-\(edit.columnName)")
                    .help("Enter valid JSON for \(edit.columnName)")
            }

        }
    }

    // MARK: - Bindings

    private func fieldBinding(index: Int) -> Binding<String> {
        Binding(
            get: { edits[index].isNull ? "" : edits[index].editText },
            set: { newText in
                edits[index].editText = newText
                edits[index].isNull = false
                edits[index].useDefault = false
                jsonErrors.removeValue(forKey: index)
                // Mirror external writes (NULL-prompt typing, Format) into the
                // JSON editor model; the equality guard breaks the echo cycle
                // for edits that originated in the editor itself.
                if let model = jsonEditorModels[index], model.text != newText {
                    try? model.replaceAllContent(with: newText)
                }
            }
        )
    }

    // MARK: - JSON Helpers

    private func validateJSON(_ text: String, index: Int) {
        guard !text.isEmpty else {
            jsonErrors.removeValue(forKey: index)
            return
        }
        do {
            _ = try RecordJSONText.compact(text)
            jsonErrors.removeValue(forKey: index)
        } catch {
            jsonErrors[index] = error.localizedDescription
        }
    }

    private func formatJSON(index: Int) {
        let text = edits[index].editText
        guard let formatted = try? RecordJSONText.pretty(text) else {
            return
        }
        edits[index].editText = formatted
        jsonErrors.removeValue(forKey: index)
        if let model = jsonEditorModels[index], model.text != formatted {
            try? model.replaceAllContent(with: formatted)
        }
    }

    // MARK: - Init

    private func initializeEdits() {
        jsonErrors.removeAll()
        switch mode {
        case .edit(_, let originalRow):
            edits = columns.enumerated().map { colIndex, col in
                let value = colIndex < originalRow.count ? originalRow[colIndex] : .null
                var edit = StagedEdit(
                    columnIndex: colIndex,
                    columnName: col.name,
                    columnType: col.type,
                    dialect: dialect,
                    isPrimaryKey: col.isPrimaryKey,
                    isNullable: col.isNullable,
                    isUnsigned: col.isUnsigned,
                    isGenerated: col.isGenerated,
                    defaultValue: col.defaultValue,
                    originalValue: value,
                    editText: editorText(for: value),
                    isNull: value.isNull,
                    useDefault: false
                )
                if windowProfile.formatsJSON,
                   edit.isJSON,
                   !edit.isNull,
                   let formatted = try? RecordJSONText.pretty(edit.editText) {
                    edit.editText = formatted
                }
                return edit
            }
        case .add:
            edits = columns.enumerated().map { colIndex, col in
                StagedEdit.initialValue(for: col, columnIndex: colIndex, dialect: dialect)
            }
        }
        rebuildJSONEditorModels()
    }

    /// Builds one editor model per JSON column, including currently-NULL ones
    /// so a NULL-to-typed transition finds its model waiting. The record
    /// editor sheet sits on system material, not the glass canvas, so the
    /// surface is `.opaque`; the canvas mapping belongs to the SQL editor
    /// phase.
    private func rebuildJSONEditorModels() {
        jsonEditorModels.removeAll()
        for edit in edits where edit.isJSON {
            let snapshot = DocumentSnapshot(
                content: edit.isNull ? "" : edit.editText,
                encoding: .utf8(hadBOM: false),
                lineEndings: .lf,
                origin: .ephemeral(id: UUID())
            )
            jsonEditorModels[edit.columnIndex] = GlassEditorModel(
                snapshot: snapshot,
                configuration: GlassEditorConfiguration(
                    showsLineNumbers: windowProfile.showLineNumbers
                ),
                theme: colorScheme == .dark ? .glassDark : .glassLight,
                language: .json,
                surfaceCondition: .opaque
            )
        }
    }

    private func editorText(for value: DatabaseValue) -> String {
        switch value {
        case .data(let data): return data.base64EncodedString()
        case .bit(let data):
            return data.map { String($0, radix: 2).leftPadded(to: 8) }.joined()
        default: return value.isNull ? "" : value.displayString
        }
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
