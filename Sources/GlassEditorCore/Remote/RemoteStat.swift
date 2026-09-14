import Foundation

/// Cheap remote file identity — what an SFTP stat can actually provide.
/// Modeled on glas.sh's `SFTPLocalFileIdentity` (SFTPBrowserView.swift:78–94).
/// Every field is optional because remote servers genuinely omit them; absence
/// is represented, never defaulted (projectRules.md, API Design).
public struct RemoteStat: Sendable, Hashable, Codable {
    public var size: UInt64?
    public var modificationSeconds: Int64?
    public var modificationNanoseconds: Int64?

    public init(
        size: UInt64? = nil,
        modificationSeconds: Int64? = nil,
        modificationNanoseconds: Int64? = nil
    ) {
        self.size = size
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
    }

    /// True when this stat carries no usable identity signal at all.
    public var isEmpty: Bool {
        size == nil && modificationSeconds == nil
    }
}

/// SHA-256 of file content. Free at open for edit-in-place — the transfer reads
/// the whole file anyway, and glas.sh already computes exactly this
/// (SFTPBrowserView.swift:902,916,935). Tier 2 of conflict detection
/// (INTEGRATION.md B2): consulted only when the stat tier reports change,
/// killing coarse-mtime false positives.
public struct ContentDigest: Sendable, Hashable, Codable {
    /// 32 bytes of SHA-256.
    public var bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    public init?(hexString: String) {
        guard hexString.count == 64 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        self.bytes = out
    }

    public var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
