//
//  TerminalLinkTarget.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  What a link in the terminal's text points at (the owner, 2026-10-14: "Add context detectors …
//  for URLs and local paths. I'd like to detect a local path to a log … and offer a right click >
//  watch log file"): an address, or a path on the machine the terminal shows.
//
//  SwiftTerm finds the link — an OSC 8 hyperlink, or text its Ghostty-style rules recognise,
//  across a soft-wrapped line too (`Terminal.link(at:mode:)`). Those rules take any `a/b.c` for a
//  relative path, so `github.com/owner/repo` would be a file; Apple's link detector
//  (`NSDataDetector`), which knows a domain, decides that one, and finds a bare address such as
//  `example.com`, which SwiftTerm's rules leave alone.
//

import Foundation

public enum TerminalLinkTarget: Equatable, Sendable {
    /// An address: a web page, `mailto:`, `ssh://` and the like.
    case url(URL)
    /// A path as the terminal printed it — absolute, `~/…`, `$VAR/…` or relative to the shell's
    /// folder — with a `:line` or `:line:column` after it removed.
    case path(String)

    /// What `text`, a link SwiftTerm found, points at; nil when it is neither.
    public init?(link text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if Self.hasScheme(text) {
            guard let url = URL(string: text) else { return nil }
            if url.isFileURL {
                guard url.path.hasPrefix("/") else { return nil }
                self = .path(url.path)
            } else {
                self = .url(url)
            }
            return
        }
        // A path written from the root, the home folder, a variable or the shell's folder is one
        // whatever it looks like; only a bare `a/b` might be an address instead.
        let rooted = ["/", "~/", "./", "../", "$"].contains { text.hasPrefix($0) }
        if !rooted, let url = Self.detectedAddress(in: text, covering: text.startIndex..<text.endIndex) {
            self = .url(url)
            return
        }
        guard text.contains("/") else { return nil }
        self = .path(Self.withoutLocation(text))
    }

    /// The address Apple's link detector finds in `line` at `column` (a cell of an ASCII line is
    /// one UTF-16 unit; a wider one moves the count), when SwiftTerm found nothing there.
    public static func address(in line: String, at column: Int) -> URL? {
        let units = line.utf16
        guard column >= 0, column < units.count else { return nil }
        let index = String.Index(utf16Offset: column, in: line)
        return detectedAddress(in: line, covering: index..<line.index(after: index))
    }

    /// The address `NSDataDetector` sees spanning all of `range`. Asked about a whole link, that
    /// means the link is an address from end to end: in `src/main.rs` it may see `main.rs` (a
    /// Serbian domain), but not the whole, so that stays a path.
    private static func detectedAddress(in text: String, covering range: Range<String.Index>) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let wanted = NSRange(range, in: text)
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, !url.isFileURL,
                  match.range.location <= wanted.location,
                  NSMaxRange(match.range) >= NSMaxRange(wanted) else { continue }
            return url
        }
        return nil
    }

    /// `scheme:` at the front, as a URL has and a path does not: `https://`, `mailto:`, `file:`.
    /// A path such as `app.log:12` has a colon too, so a scheme is one of letters, digits and
    /// `+-.` followed by `//`, or one of the few that never take them.
    private static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return false }
        return text[colon...].hasPrefix("://") || ["mailto", "tel", "news", "file"].contains(scheme.lowercased())
    }

    /// `app.log:12:3` → `app.log`: a compiler's or a log's place in the file is not the file's name.
    static func withoutLocation(_ path: String) -> String {
        var rest = Substring(path)
        for _ in 0..<2 {
            guard let colon = rest.lastIndex(of: ":"), colon > rest.startIndex else { break }
            let digits = rest[rest.index(after: colon)...]
            guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { break }
            rest = rest[..<colon]
        }
        return String(rest)
    }
}
