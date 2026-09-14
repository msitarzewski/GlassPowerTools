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
        default: return .plaintext
        }
    }
}
