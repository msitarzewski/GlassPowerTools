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
        default: return .plaintext
        }
    }
}
