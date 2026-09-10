//
//  SFTPBrowserHelperTests.swift
//  glas.sh's SFTP browser-helper tests, restored against GlassTerminal's SFTPCompatibility types
//  (the browser's Citadel-shaped shim over the engine's SFTPSession). Bodies are unchanged.
//

import Testing
import Foundation
import GlassEditorCore
@testable import GlassTerminal

@Suite struct SFTPBrowserHelperTests {
    @Test func sftpOutlineIdentifiesDuplicateBasenamesByTheirFullPaths() {
        let component = SFTPPathComponent(filename: "config", longname: "-rw------- config", attributes: .init())
        let root = SFTPBrowserEntry(component: component, parentPath: "/", depth: 0)
        let first = SFTPBrowserEntry(component: component, parentPath: "/one", depth: 1)
        let second = SFTPBrowserEntry(component: component, parentPath: "/two", depth: 1)
        #expect(root.id == "/config")
        #expect(first.id == "/one/config")
        #expect(second.id == "/two/config")
        #expect(Set([root.id, first.id, second.id]).count == 3)
        #expect(first.filename == "config")
        #expect(first.parentPath == "/one")
    }
    @Test func sftpOutlineBatchOperationsDoNotProcessSelectedDescendantsTwice() {
        func entry(_ name: String, in parent: String) -> SFTPBrowserEntry {
            .init(component: .init(filename: name, longname: name, attributes: .init()), parentPath: parent, depth: 0)
        }
        let folder = entry("one", in: "/")
        let child = entry("config", in: "/one")
        let grandchild = entry("nested", in: "/one/subfolder")
        let similarPrefix = entry("config", in: "/one-more")
        #expect(SFTPBrowserEntry.topLevelSelection([child, folder, grandchild, similarPrefix]).map(\.id)
            == ["/one", "/one-more/config"])
        #expect(SFTPBrowserEntry.topLevelSelection([child, similarPrefix]).map(\.id)
            == ["/one/config", "/one-more/config"])
    }
    @Test func sftpTableSortsEveryDataColumnAndKeepsDirectoriesFirst() {
        func tableEntry(
            _ name: String,
            isDirectory: Bool = false,
            size: UInt64? = nil,
            modified: TimeInterval? = nil,
            permissions: UInt32? = nil
        ) -> SFTPBrowserTableEntry {
            let accessModificationTime = modified.map {
                SFTPFileAttributes.AccessModificationTime(
                    accessTime: Date(timeIntervalSince1970: $0),
                    modificationTime: Date(timeIntervalSince1970: $0)
                )
            }
            var attributes = SFTPFileAttributes(
                size: size,
                accessModificationTime: accessModificationTime
            )
            attributes.permissions = permissions
            return SFTPBrowserTableEntry(
                entry: .init(
                    filename: name,
                    longname: isDirectory ? "drwx------ \(name)" : "-rw------- \(name)",
                    attributes: attributes
                ),
                isDirectory: isDirectory
            )
        }

        let nameRows = [
            tableEntry("file10"),
            tableEntry("folder-z", isDirectory: true),
            tableEntry("file2"),
            tableEntry("folder-a", isDirectory: true),
        ]
        #expect(
            nameRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .name)
            ]).map(\.entry.filename)
                == ["folder-a", "folder-z", "file2", "file10"]
        )
        #expect(
            nameRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .name, order: .reverse)
            ]).map(\.entry.filename)
                == ["folder-z", "folder-a", "file10", "file2"]
        )

        let sizeRows = [
            tableEntry("unknown"),
            tableEntry("large", size: 900),
            tableEntry("folder", isDirectory: true),
            tableEntry("small-b", size: 10),
            tableEntry("small-a", size: 10),
        ]
        #expect(
            sizeRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .size)
            ]).map(\.entry.filename)
                == ["folder", "small-a", "small-b", "large", "unknown"]
        )
        #expect(
            sizeRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .size, order: .reverse)
            ]).map(\.entry.filename)
                == ["folder", "large", "small-a", "small-b", "unknown"]
        )

        let metadataRows = [
            tableEntry("unknown"),
            tableEntry("newer-private", modified: 200, permissions: 0o100600),
            tableEntry("older-public", modified: 100, permissions: 0o100644),
        ]
        #expect(
            metadataRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .modified)
            ]).map(\.entry.filename)
                == ["older-public", "newer-private", "unknown"]
        )
        #expect(
            metadataRows.sorted(using: [
                SFTPBrowserTableSortComparator(column: .permissions, order: .reverse)
            ]).map(\.entry.filename)
                == ["older-public", "newer-private", "unknown"]
        )
    }
    @Test func sftpDownloadReadBatchStopsBeforeEOFAndRejectsOversizedData() throws {
        let requests = SFTPBrowserView.downloadReadWindow(
            from: 0,
            through: UInt64(SFTPBrowserView.downloadReadChunkSize) * 3
        )
        let eofDecision = try SFTPBrowserView.downloadReadBatchDecision(
            requests: requests,
            readableByteCounts: [Int(requests[0].length), 0, Int(requests[2].length)]
        )
        #expect(eofDecision.acceptedResponseCount == 1)
        #expect(eofDecision.reachedEOF)

        #expect(throws: SFTPError.self) {
            try SFTPBrowserView.downloadReadBatchDecision(
                requests: requests,
                readableByteCounts: [Int(requests[0].length) + 1, 0, 0]
            )
        }
    }
    @Test func sftpV3RemoteStatNeverInventsNanoseconds() {
        let attributes = SFTPFileAttributes(
            size: 4_096,
            accessModificationTime: .init(
                accessTime: Date(timeIntervalSince1970: 1_700_000_000),
                modificationTime: Date(timeIntervalSince1970: 1_700_000_123.875)
            )
        )

        let stat = SFTPBrowserView.remoteStat(from: attributes)

        #expect(stat.size == 4_096)
        #expect(stat.modificationSeconds == 1_700_000_123)
        #expect(stat.modificationNanoseconds == nil)
    }
}
