//
//  GlassEditorDiffView.swift
//  Glass Power Tools — GlassEditor
//
//  One file's lines in a diff (2026-10-28: "first class (diff viewer, all of it!)"): unified, or
//  side by side; the words that changed inside a changed line highlighted, as GitHub and Sublime
//  Merge do; and — where the diff is the working tree's — each hunk staged, unstaged or thrown
//  away, or only the lines chosen in it, by clicking their numbers.
//
//  The building block Changes, a commit's details and a stash's all use: the caller draws the
//  file's header and decides what can be done; this draws the hunks.
//

import SwiftUI
import GlassConnectionUI

/// Unified or side by side.
public enum GlassEditorDiffLayout: String, CaseIterable, Sendable {
    case unified, split

    var title: String { self == .unified ? "Unified" : "Side by Side" }

    /// Side by side only where two columns of code fit; unified otherwise.
    static func fitting(_ chosen: GlassEditorDiffLayout, width: CGFloat) -> GlassEditorDiffLayout {
        chosen == .split && width < 700 ? .unified : chosen
    }
}

/// What can be done to a hunk, or to the lines chosen in it.
enum GlassEditorHunkAction: Hashable {
    case stage, unstage, discard

    func title(lines: Int) -> String {
        let what = lines > 0 ? (lines == 1 ? "Line" : "\(lines) Lines") : "Hunk"
        switch self {
        case .stage: return "Stage \(what)"
        case .unstage: return "Unstage \(what)"
        case .discard: return "Discard \(what)"
        }
    }

    var symbol: String {
        switch self {
        case .stage: "plus.circle"
        case .unstage: "minus.circle"
        case .discard: "arrow.uturn.backward.circle"
        }
    }
}

/// The diff options every diff shares, kept for the app: unified or side by side, how much context,
/// whitespace.
@MainActor
enum GlassEditorDiffSettings {
    static let layoutKey = "editor.git.diffLayout"
    static let contextKey = "editor.git.diffContext"
    static let whitespaceKey = "editor.git.ignoreWhitespace"

    /// Git's 3 lines, more, or the whole file: what `diffContext` takes.
    static func context(_ stored: Int) -> Int? {
        stored <= 0 ? nil : (stored >= GlassEditorGitRepository.wholeFile ? GlassEditorGitRepository.wholeFile : stored)
    }
}

/// The menu that sets them, on every diff's bar.
struct GlassEditorDiffOptionsMenu: View {
    @AppStorage(GlassEditorDiffSettings.layoutKey) private var layout = GlassEditorDiffLayout.unified
    @AppStorage(GlassEditorDiffSettings.contextKey) private var context = 0
    @AppStorage(GlassEditorDiffSettings.whitespaceKey) private var ignoresWhitespace = false

    var body: some View {
        Menu {
            Picker("Layout", selection: $layout) {
                ForEach(GlassEditorDiffLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Context", selection: $context) {
                Text("3 Lines Around Changes").tag(0)
                Text("10 Lines Around Changes").tag(10)
                Text("Whole File").tag(GlassEditorGitRepository.wholeFile)
            }
            .pickerStyle(.inline)
            Toggle("Ignore Whitespace", isOn: $ignoresWhitespace)
        } label: {
            Label("Diff Options", systemImage: "slider.horizontal.3")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Unified or side by side, how many lines around each change, and whitespace")
        .accessibilityIdentifier("editor-diff-options")
    }
}

/// A file's hunks and lines.
struct GlassEditorDiffBody: View {
    let file: GlassEditorFileDiff
    /// Unique across everything on screen: the rows' identities.
    let rowID: String
    let layout: GlassEditorDiffLayout
    let fontSize: Double
    /// Wrap Long Lines, the window's or every editor's, as the editor's own text has it (the owner,
    /// 2026-10-29: "The wrap long lines setting doesn't seem to apply to the diff views"). Off, a
    /// hunk's lines are one line apiece and scroll sideways together under its bar.
    var wraps = true
    /// What each hunk's bar offers; none for a commit's diff.
    var actions: [GlassEditorHunkAction] = []
    var perform: ((GlassEditorHunkAction, Int, Set<Int>?) -> Void)?
    /// The lines chosen in each hunk, by their index in it.
    var chosen: Binding<[Int: Set<Int>]>?
    /// Opens the file at a line as it is now.
    var open: ((Int) -> Void)?
    var isDisabled = false

    private var choosable: Bool { chosen != nil && !actions.isEmpty && GlassEditorGitPatch.canPatch(file) }

    var body: some View {
        let rows = GlassEditorDiffRows.rows(of: file, id: rowID, layout: layout)
        let width = numberWidth
        if wraps {
            ForEach(rows) { row in
                switch row.content {
                case .hunk(let index):
                    hunkBar(index)
                case .line(let hunk, let line, let highlights):
                    unifiedRow(hunk: hunk, line: line, highlights: highlights, width: width)
                case .pair(let hunk, let left, let right):
                    splitRow(hunk: hunk, left: left, right: right, width: width)
                }
            }
        } else {
            // The bar stays the window's width, so its buttons stay in view; the lines scroll.
            ForEach(GlassEditorDiffRows.hunks(of: rows)) { hunk in
                hunkBar(hunk.index)
                unwrapped(hunk, width: width)
            }
        }
    }

    // MARK: Lines that don't wrap

    /// A hunk's lines, one line apiece, scrolled sideways together: each as wide as the widest, so
    /// their colours end at one edge, and none narrower than the window. Side by side, each side is
    /// a column of its own; a line never wraps, so the two sides' rows stay level.
    private func unwrapped(_ hunk: GlassEditorDiffRows.Hunk, width: CGFloat) -> some View {
        GlassEditorSidewaysScroll { viewport in
            switch layout {
            case .unified:
                column {
                    ForEach(hunk.rows) { row in
                        if case .line(let h, let line, let highlights) = row.content {
                            unifiedRow(hunk: h, line: line, highlights: highlights, width: width, least: viewport)
                        }
                    }
                }
            case .split:
                let lines = file.hunks[hunk.index].lines
                let highlights = GlassEditorDiffRows.highlights(of: file.hunks[hunk.index], in: rowID, hunk: hunk.index)
                HStack(alignment: .top, spacing: 0) {
                    column {
                        ForEach(hunk.rows) { row in
                            if case .pair(let h, let left, _) = row.content {
                                half(left.map { lines[$0] }, hunk: h, index: left, number: left.flatMap { lines[$0].oldNumber },
                                     highlights: left.flatMap { highlights[$0] } ?? [], width: width, least: viewport / 2)
                            }
                        }
                    }
                    Divider()
                    column {
                        ForEach(hunk.rows) { row in
                            if case .pair(let h, _, let right) = row.content {
                                half(right.map { lines[$0] }, hunk: h, index: right, number: right.flatMap { lines[$0].newNumber },
                                     highlights: right.flatMap { highlights[$0] } ?? [], width: width, least: viewport / 2)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Rows as wide as the widest of them: a stack at its own ideal width hands that width to each.
    private func column<Content: View>(@ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { rows() }
            .font(.system(size: fontSize, design: .monospaced))
            .fixedSize(horizontal: true, vertical: false)
    }

    /// A line's text: wrapped to the width there is, or one line as long as it is.
    @ViewBuilder
    private func lineText(_ text: AttributedString) -> some View {
        if wraps {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: A hunk's bar

    private func hunkBar(_ index: Int) -> some View {
        let hunk = file.hunks[index]
        let lines = chosen?.wrappedValue[index]?.count ?? 0
        return HStack(spacing: 8) {
            Text(hunk.heading.isEmpty ? hunk.range : "\(hunk.range)  \(hunk.heading)")
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if lines > 0 {
                Button("Clear") { chosen?.wrappedValue[index] = nil }
                    .buttonStyle(.borderless)
                    .help("Choose no lines: the buttons act on the whole hunk again")
            }
            if GlassEditorGitPatch.canPatch(file) {
                ForEach(actions, id: \.self) { action in
                    Button(action.title(lines: lines), systemImage: action.symbol) {
                        perform?(action, index, lines > 0 ? chosen?.wrappedValue[index] : nil)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isDisabled)
                    .accessibilityIdentifier("editor-hunk-\(action)-\(rowID)-\(index)")
                }
            }
        }
        .font(.system(size: fontSize * 0.85, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: Unified

    private func unifiedRow(hunk: Int, line index: Int, highlights: [Range<Int>], width: CGFloat,
                            least: CGFloat = 0) -> some View {
        let line = file.hunks[hunk].lines[index]
        let isChosen = chosen?.wrappedValue[hunk]?.contains(index) == true
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            numbers(line, hunk: hunk, index: index, width: width, isChosen: isChosen)
            Text(Self.sign(line.kind))
                .frame(width: fontSize * 1.6)
                .foregroundStyle(Self.tint(line.kind) == .clear ? Color.secondary : Self.tint(line.kind))
            lineText(Self.styled(line.text, highlights: highlights, kind: line.kind))
            if line.noNewlineAtEnd { noNewline }
        }
        .frame(minWidth: least, alignment: .leading)
        .font(.system(size: fontSize, design: .monospaced))
        .padding(.vertical, 1)
        .background(Self.tint(line.kind).opacity(isChosen ? 0.34 : 0.16))
        .overlay(alignment: .leading) {
            if isChosen { Rectangle().fill(Color.accentColor).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { openLine(line) }
        .contextMenu { lineMenu(line, hunk: hunk, index: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(line) + (isChosen ? ", chosen" : ""))
        .accessibilityActions { lineAccessibilityActions(line, hunk: hunk, index: index) }
    }

    /// The old and new numbers; pressed, they choose the line for a hunk's buttons.
    @ViewBuilder
    private func numbers(_ line: GlassEditorDiffLine, hunk: Int, index: Int, width: CGFloat, isChosen: Bool) -> some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: width, alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: width, alignment: .trailing)
        }
        .foregroundStyle(isChosen ? Color.accentColor : .secondary)
        .contentShape(Rectangle())
        .onTapGesture { toggle(hunk: hunk, index: index) }
        .help(choosable && line.kind != .context ? "Choose this line, to stage or discard only the lines you choose" : "")
    }

    private var noNewline: some View {
        Image(systemName: "arrow.uturn.left")
            .foregroundStyle(.secondary)
            .help("No newline at the end of the file")
            .padding(.trailing, 8)
    }

    // MARK: Side by side

    private func splitRow(hunk: Int, left: Int?, right: Int?, width: CGFloat) -> some View {
        let lines = file.hunks[hunk].lines
        let highlights = GlassEditorDiffRows.highlights(of: file.hunks[hunk], in: rowID, hunk: hunk)
        return HStack(alignment: .top, spacing: 0) {
            half(left.map { lines[$0] }, hunk: hunk, index: left, number: left.flatMap { lines[$0].oldNumber },
                 highlights: left.flatMap { highlights[$0] } ?? [], width: width)
            Divider()
            half(right.map { lines[$0] }, hunk: hunk, index: right, number: right.flatMap { lines[$0].newNumber },
                 highlights: right.flatMap { highlights[$0] } ?? [], width: width)
        }
        .font(.system(size: fontSize, design: .monospaced))
    }

    @ViewBuilder
    private func half(_ line: GlassEditorDiffLine?, hunk: Int, index: Int?, number: Int?, highlights: [Range<Int>],
                      width: CGFloat, least: CGFloat = 0) -> some View {
        if let line, let index {
            let isChosen = chosen?.wrappedValue[hunk]?.contains(index) == true
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(number.map(String.init) ?? "")
                    .frame(width: width, alignment: .trailing)
                    .foregroundStyle(isChosen ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(hunk: hunk, index: index) }
                Text(Self.sign(line.kind))
                    .frame(width: fontSize * 1.4)
                    .foregroundStyle(Self.tint(line.kind) == .clear ? Color.secondary : Self.tint(line.kind))
                lineText(Self.styled(line.text, highlights: highlights, kind: line.kind))
                if line.noNewlineAtEnd { noNewline }
            }
            .padding(.vertical, 1)
            .frame(minWidth: least, maxWidth: .infinity, alignment: .leading)
            .background(Self.tint(line.kind).opacity(isChosen ? 0.34 : 0.16))
            .overlay(alignment: .leading) {
                if isChosen { Rectangle().fill(Color.accentColor).frame(width: 3) }
            }
            .contentShape(Rectangle())
            .onTapGesture { openLine(line) }
            .contextMenu { lineMenu(line, hunk: hunk, index: index) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(line) + (isChosen ? ", chosen" : ""))
            .accessibilityActions { lineAccessibilityActions(line, hunk: hunk, index: index) }
        } else if wraps {
            // Nothing on this side: the other side's line is new, or gone.
            Color.secondary.opacity(0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        } else {
            // The same, one line tall: in a column of its own there is no other side to match.
            Text(" ")
                .padding(.vertical, 1)
                .frame(minWidth: least, maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .accessibilityHidden(true)
        }
    }

    // MARK: Lines

    private func toggle(hunk: Int, index: Int) {
        guard choosable, let chosen, file.hunks[hunk].lines[index].kind != .context, !isDisabled else { return }
        var lines = chosen.wrappedValue[hunk] ?? []
        if lines.contains(index) { lines.remove(index) } else { lines.insert(index) }
        chosen.wrappedValue[hunk] = lines.isEmpty ? nil : lines
    }

    private func openLine(_ line: GlassEditorDiffLine) {
        // Where the line is in the file now: a removed line's place is the line after it.
        guard let open, let target = line.newNumber ?? line.oldNumber else { return }
        open(target)
    }

    @ViewBuilder
    private func lineMenu(_ line: GlassEditorDiffLine, hunk: Int, index: Int) -> some View {
        if let open, let target = line.newNumber ?? line.oldNumber {
            Button("Open at Line \(target)", systemImage: "arrow.up.forward.square") { open(target) }
        }
        Button("Copy Line", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(line.text) }
        if choosable, line.kind != .context {
            Divider()
            let isChosen = chosen?.wrappedValue[hunk]?.contains(index) == true
            Button(isChosen ? "Unchoose Line" : "Choose Line", systemImage: isChosen ? "checkmark.circle" : "circle") {
                toggle(hunk: hunk, index: index)
            }
            ForEach(actions, id: \.self) { action in
                Button(action.title(lines: 1), systemImage: action.symbol) { perform?(action, hunk, [index]) }
                    .disabled(isDisabled)
            }
        }
    }

    @ViewBuilder
    private func lineAccessibilityActions(_ line: GlassEditorDiffLine, hunk: Int, index: Int) -> some View {
        if open != nil { Button("Open") { openLine(line) } }
        if choosable, line.kind != .context {
            Button(chosen?.wrappedValue[hunk]?.contains(index) == true ? "Unchoose" : "Choose") { toggle(hunk: hunk, index: index) }
            ForEach(actions, id: \.self) { action in
                Button(action.title(lines: 1)) { perform?(action, hunk, [index]) }
            }
        }
    }

    /// Wide enough for the file's largest line number.
    private var numberWidth: CGFloat {
        let largest = file.hunks.map { max($0.oldStart + $0.oldCount, $0.newStart + $0.newCount) }.max() ?? 1
        return CGFloat(String(largest).count) * fontSize * 0.62 + 10
    }

    static func sign(_ kind: GlassEditorDiffLine.Kind) -> String {
        switch kind { case .added: "+"; case .removed: "−"; case .context: " " }
    }

    static func tint(_ kind: GlassEditorDiffLine.Kind) -> Color {
        switch kind { case .added: .green; case .removed: .red; case .context: .clear }
    }

    /// The line with its changed words marked, tabs as four spaces: Text's own tab is narrow and
    /// uneven. The marks are counted in the line's own characters, before the tabs are widened.
    static func styled(_ text: String, highlights: [Range<Int>], kind: GlassEditorDiffLine.Kind) -> AttributedString {
        guard !text.isEmpty else { return AttributedString(" ") }
        let characters = Array(text)
        var marked = [Bool](repeating: false, count: characters.count)
        for range in highlights {
            for offset in range where offset < characters.count { marked[offset] = true }
        }
        var result = AttributedString()
        var start = 0
        while start < characters.count {
            var end = start
            while end < characters.count, marked[end] == marked[start] { end += 1 }
            var piece = AttributedString(String(characters[start..<end]).replacingOccurrences(of: "\t", with: "    "))
            if marked[start] { piece.backgroundColor = tint(kind).opacity(0.38) }
            result += piece
            start = end
        }
        return result
    }

    static func spoken(_ line: GlassEditorDiffLine) -> String {
        switch line.kind {
        case .added: "Added, line \(line.newNumber ?? 0): \(line.text)"
        case .removed: "Removed, was line \(line.oldNumber ?? 0): \(line.text)"
        case .context: "Line \(line.newNumber ?? 0): \(line.text)"
        }
    }
}

/// A file's rows, worked out once per diff: the word highlights cost a comparison per changed
/// line, and a body is drawn far more often than its diff changes.
@MainActor
enum GlassEditorDiffRows {
    struct Row: Identifiable {
        enum Content {
            case hunk(Int)
            case line(hunk: Int, line: Int, highlights: [Range<Int>])
            case pair(hunk: Int, left: Int?, right: Int?)
        }
        let id: String
        let content: Content
    }

    private struct Entry {
        var file: GlassEditorFileDiff
        var layout: GlassEditorDiffLayout
        var rows: [Row]
        var highlights: [Int: [Int: [Range<Int>]]]
    }

    private static var cache: [String: Entry] = [:]

    static func rows(of file: GlassEditorFileDiff, id: String, layout: GlassEditorDiffLayout) -> [Row] {
        if let entry = cache[id], entry.layout == layout, entry.file == file { return entry.rows }
        var rows: [Row] = []
        var highlights: [Int: [Int: [Range<Int>]]] = [:]
        for (h, hunk) in file.hunks.enumerated() {
            rows.append(Row(id: "\(id)#\(h)", content: .hunk(h)))
            let marks = GlassEditorWordDiff.highlights(of: hunk)
            highlights[h] = marks
            switch layout {
            case .unified:
                for l in hunk.lines.indices {
                    rows.append(Row(id: "\(id)#\(h).\(l)", content: .line(hunk: h, line: l, highlights: marks[l] ?? [])))
                }
            case .split:
                for (r, pair) in GlassEditorSplitRow.rows(of: hunk).enumerated() {
                    rows.append(Row(id: "\(id)#\(h)|\(r)", content: .pair(hunk: h, left: pair.left, right: pair.right)))
                }
            }
        }
        if cache.count > 400 { cache = [:] }
        cache[id] = Entry(file: file, layout: layout, rows: rows, highlights: highlights)
        return rows
    }

    /// The rows under each hunk's bar, for a diff drawn a hunk at a time.
    struct Hunk: Identifiable {
        let id: String
        let index: Int
        var rows: [Row]
    }

    static func hunks(of rows: [Row]) -> [Hunk] {
        var hunks: [Hunk] = []
        for row in rows {
            if case .hunk(let index) = row.content {
                hunks.append(Hunk(id: row.id, index: index, rows: []))
            } else if !hunks.isEmpty {
                hunks[hunks.count - 1].rows.append(row)
            }
        }
        return hunks
    }

    static func highlights(of hunk: GlassEditorDiffHunk, in id: String, hunk index: Int) -> [Int: [Range<Int>]] {
        cache[id]?.highlights[index] ?? GlassEditorWordDiff.highlights(of: hunk)
    }
}

/// A sideways scroll that tells its content how wide it is on screen.
private struct GlassEditorSidewaysScroll<Content: View>: View {
    @ViewBuilder let content: (_ viewport: CGFloat) -> Content
    @State private var viewport: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) { content(viewport) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewport = $0 }
    }
}
