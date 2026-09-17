import Foundation

/// The v1 grammar set (D-004). `plaintext` is a real language whose highlighter
/// emits a single `.plain` run — not an error state and not a fallback surprise.
public enum LanguageID: String, Sendable, Hashable, Codable, CaseIterable {
    case sql
    case json
    case bash
    case yaml
    case toml
    case markdown
    // 2026-09-16: the languages that are actually on the machines this app connects to. Without
    // these the editor could colour a compose file and a schema and nothing anyone writes.
    case python
    case javascript
    case go
    case rust
    case c
    case php
    // 2026-09-17: the language this project is written in, and the one every Apple plist and
    // scheme file is. Swift's grammar has to be generated — see the package manifest.
    case swift
    case xml
    case plaintext

    /// Best-effort mapping from a file extension. Unknown extensions are
    /// `plaintext` — the honest default, never a guessed grammar.
    public static func forFileExtension(_ ext: String) -> LanguageID {
        switch ext.lowercased() {
        case "sql", "mysql", "ddl": return .sql
        case "json", "jsonc", "geojson", "webmanifest": return .json
        case "sh", "bash", "zsh", "bashrc", "zshrc", "profile": return .bash
        case "yml", "yaml": return .yaml
        case "toml": return .toml
        case "md", "markdown", "mdown": return .markdown
        case "py", "pyw", "pyi": return .python
        // JSX and TypeScript ride the JavaScript grammar: it parses both well enough to colour,
        // and a wrong-but-close highlight beats plain grey. A real TypeScript grammar is a
        // separate dependency and can replace this later without touching a call site.
        case "js", "mjs", "cjs", "jsx", "ts", "tsx", "mts", "cts": return .javascript
        case "go": return .go
        case "rs": return .rust
        case "c", "h": return .c
        case "php", "phtml": return .php
        case "swift": return .swift
        // `.plist`, `.xcscheme`, `.entitlements` and `.storyboard` are all XML, and a developer on
        // this platform opens them constantly. `.svg` and `.xib` likewise.
        case "xml", "plist", "svg", "xib", "storyboard", "xcscheme", "entitlements", "xsd", "xsl",
             "xslt", "rss", "atom", "pom": return .xml
        default: return .plaintext
        }
    }

    /// The language a file's **first bytes** give away, for a file whose name does not say.
    ///
    /// `Makefile`, `Dockerfile`, a shell script called `deploy`, a `.env`, a plist with no
    /// extension — a developer's tree is full of files with no extension or a misleading one, and
    /// an editor that calls all of them plain text is wrong about the common case. Only the
    /// evidence that is actually conclusive counts here: an interpreter line names its own
    /// language, an XML prolog is XML, and a document that starts with a brace and parses as JSON
    /// is JSON. Anything less certain stays plaintext, because a wrong grammar colours worse than
    /// none.
    public static func forContent(_ content: String) -> LanguageID {
        let head = content.prefix(4096)
        let trimmed = head.drop { $0 == "\u{FEFF}" }.drop { $0.isWhitespace }

        if trimmed.hasPrefix("#!") {
            let line = trimmed.prefix { !$0.isNewline }.lowercased()
            if line.contains("python") { return .python }
            if line.contains("node") || line.contains("deno") || line.contains("bun") { return .javascript }
            if line.contains("php") { return .php }
            if line.contains("swift") { return .swift }
            if line.contains("bash") || line.contains("zsh") || line.contains("/sh")
                || line.hasSuffix(" sh") { return .bash }
            // An interpreter this build has no grammar for. Still not plaintext-by-accident: it is
            // a script, and the shell grammar reads a script better than nothing does.
            return .bash
        }
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<!DOCTYPE") { return .xml }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            // Parsed, not guessed: a Swift dictionary literal and a JSON object look alike at the
            // first character and nowhere else.
            if let data = content.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .json
            }
        }
        return .plaintext
    }
}
