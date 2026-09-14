import Foundation

/// Where a document came from, which determines who owns saving it.
///
/// - `.local`: the package owns atomic write-then-rename.
/// - `.remote`: the package owns the conflict *decision* only; the consumer
///   (glas.sh) owns the transfer, which already does SHA-256 verification and
///   atomic commit (INTEGRATION.md B1). The package never opens a socket.
/// - `.ephemeral`: no backing store — a query tab, a scratch buffer. Saving is
///   the consumer's concern (e.g. glassdb persists query text its own way).
public enum DocumentOrigin: Sendable, Hashable {
    case local(URL)
    case remote(RemoteDocumentRef)
    case ephemeral(id: UUID)
}

/// Opaque reference to a remote file. The package never interprets `host` or
/// `path` beyond display and identity — no networking, no path resolution.
public struct RemoteDocumentRef: Sendable, Hashable {
    /// Consumer's connection identity (e.g. a glas.sh session UUID).
    public var connectionID: UUID
    /// Display host, e.g. "umbp.tail1234.ts.net".
    public var host: String
    /// Remote absolute path as the consumer's transport understands it.
    public var path: String

    public init(connectionID: UUID, host: String, path: String) {
        self.connectionID = connectionID
        self.host = host
        self.path = path
    }
}

/// Line-ending style, detected at open and preserved on save unless the user
/// explicitly changes it (projectRules.md, Data Safety).
public enum LineEndingStyle: Sendable, Hashable, Codable {
    case lf
    case crlf
    case cr
    /// The file mixes styles. `dominant` is what new lines use; save preserves
    /// existing endings byte-for-byte rather than normalizing silently.
    case mixed(dominant: DominantLineEnding)

    public enum DominantLineEnding: String, Sendable, Hashable, Codable {
        case lf, crlf, cr
    }

    /// The string a new line break inserts under this style.
    public var newlineString: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        case .mixed(let dominant):
            switch dominant {
            case .lf: return "\n"
            case .crlf: return "\r\n"
            case .cr: return "\r"
            }
        }
    }
}
