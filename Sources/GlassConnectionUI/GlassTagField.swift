import SwiftUI

/// Pure tag-list rules shared by every Glass tag editor: one flat, system-wide vocabulary.
/// Labels, groups and clients are uses of tags, not tag types.
public enum GlassTagList {
    /// Trims whitespace, drops empties and case-insensitive duplicates, keeps the first spelling
    /// and the order of entry.
    public static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            out.append(tag)
        }
        return out
    }

    /// Splits typed text on commas and newlines, then appends every new token to `tags`.
    public static func adding(_ text: String, to tags: [String]) -> [String] {
        let tokens = text.split(whereSeparator: { $0 == "," || $0.isNewline }).map(String.init)
        return normalized(tags + tokens)
    }

    public static func contains(_ tags: [String], _ tag: String) -> Bool {
        let needle = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tags.contains { $0.lowercased() == needle }
    }
}

/// Suggestion ranking for a tag field: what the vocabulary offers for the text typed so far.
public enum GlassTagSuggestions {
    /// Prefix matches first, then substring matches, case-insensitive; already-chosen tags and
    /// duplicates are excluded. An empty query offers the vocabulary in its own order.
    public static func matches(for query: String, in vocabulary: [String], excluding chosen: [String],
                               limit: Int = 8) -> [String] {
        let candidates = GlassTagList.normalized(vocabulary).filter { !GlassTagList.contains(chosen, $0) }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(candidates.prefix(limit)) }
        let prefix = candidates.filter { $0.lowercased().hasPrefix(needle) }
        let inner = candidates.filter { !$0.lowercased().hasPrefix(needle) && $0.lowercased().contains(needle) }
        return Array((prefix + inner).prefix(limit))
    }
}

/// A token editor for tags: chips with a remove control, a trailing text field that commits on
/// Return or comma, Backspace on an empty field removing the last chip, and suggestions drawn
/// from the system-wide vocabulary while the field has focus. Chips wrap to the width available.
public struct GlassTagField: View {
    @Binding private var tags: [String]
    private let suggestions: [String]
    private let placeholder: String
    private let identifier: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    /// - Parameters:
    ///   - tags: the edited list; the field keeps it normalised (see `GlassTagList.normalized`).
    ///   - suggestions: the vocabulary offered while typing, normally every tag in the library.
    ///   - placeholder: prompt text for the empty input.
    ///   - accessibilityIdentifier: base identifier; chips are `<base>.tag.<n>`, the input is
    ///     `<base>.input`, suggestions are `<base>.suggestion.<n>`.
    public init(tags: Binding<[String]>, suggestions: [String] = [], placeholder: String = "Add…",
                accessibilityIdentifier: String) {
        _tags = tags
        self.suggestions = suggestions
        self.placeholder = placeholder
        self.identifier = accessibilityIdentifier
    }

    private var matches: [String] {
        GlassTagSuggestions.matches(for: draft, in: suggestions, excluding: tags)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassTagFlowLayout(spacing: 6) {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    chip(tag, index: index)
                }
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { commitDraft() }
                    .onChange(of: draft) { _, value in
                        if value.contains(",") || value.contains(where: \.isNewline) { commitDraft() }
                    }
                    .onKeyPress(.delete) {
                        guard draft.isEmpty, !tags.isEmpty else { return .ignored }
                        tags.removeLast()
                        return .handled
                    }
                    #if os(macOS)
                    // AppKit's field editor consumes Backspace before `onKeyPress` sees it, even
                    // when the field is empty; a local monitor, live only while this field is
                    // focused and empty, removes the last chip instead.
                    .background(GlassBackspaceMonitor(active: focused && draft.isEmpty) {
                        guard !tags.isEmpty else { return }
                        tags.removeLast()
                    })
                    #endif
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .frame(minWidth: 96, minHeight: 28)
                    .accessibilityIdentifier("\(identifier).input")
            }
            .contentShape(.rect)
            .onTapGesture { focused = true }

            if focused, !matches.isEmpty {
                GlassTagFlowLayout(spacing: 6) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { index, tag in
                        Button {
                            add(tag)
                        } label: {
                            Label(tag, systemImage: "plus")
                                .font(.callout)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().strokeBorder(.secondary.opacity(0.5)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(tag)")
                        .accessibilityIdentifier("\(identifier).suggestion.\(index)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(identifier).suggestions")
                .transition(.opacity)
            }
        }
        .animation(.default, value: tags)
        .animation(.default, value: focused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func chip(_ tag: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.callout)
                .lineLimit(1)
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag)")
            .accessibilityIdentifier("\(identifier).tag.\(index).remove")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(.tint.opacity(0.18)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tag), tag")
        .accessibilityIdentifier("\(identifier).tag.\(index)")
    }

    private func add(_ tag: String) {
        tags = GlassTagList.adding(tag, to: tags)
        draft = ""
        focused = true
    }

    private func commitDraft() {
        let text = draft
        draft = ""
        tags = GlassTagList.adding(text, to: tags)
        focused = true
    }

    private func remove(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }
}

/// Lays subviews out left to right, wrapping to a new row when the proposed width runs out.
public struct GlassTagFlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let y = bounds.minY + row.y + (row.height - size.height) / 2
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                current.width = x - spacing
                rows.append(current)
                y += current.height + spacing
                current = Row(y: y)
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty {
            current.width = x - spacing
            rows.append(current)
        }
        return rows
    }
}

#if os(macOS)
import AppKit

/// Observes Backspace while `active`; the handler runs on the main actor and the event is consumed.
private struct GlassBackspaceMonitor: NSViewRepresentable {
    var active: Bool
    var onBackspace: () -> Void

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.active = active
        context.coordinator.onBackspace = onBackspace
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var active = false
        var onBackspace: () -> Void = {}
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.active, event.keyCode == 51, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
                self.onBackspace()
                return nil
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
