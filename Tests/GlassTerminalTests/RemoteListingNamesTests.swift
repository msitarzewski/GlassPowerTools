import Foundation
import Testing
import GlassSSHTransport
import GlassShell
@testable import GlassTerminal

/// B-X22 (2026-10-13): the editor's remote folders are listed through the terminal's SFTP, and the
/// editor joins each name the server sends onto the folder's path.
@Suite("A remote listing leaves out names that would leave the folder")
struct RemoteListingNamesTests {
    @Test("Names with a slash or NUL, and . or .., are left out; ordinary names, dotfiles included, stay")
    func unsafeNamesAreLeftOut() {
        let folder = SFTPAttributes(size: 0, permissions: 0o040755)
        let file = SFTPAttributes(size: 1, permissions: 0o100644)
        let listed = [
            SFTPEntry(name: "src", path: "/p/src", attributes: folder),
            SFTPEntry(name: ".env", path: "/p/.env", attributes: file),
            SFTPEntry(name: "../../etc", path: "/p/../../etc", attributes: folder),
            SFTPEntry(name: "a/b", path: "/p/a/b", attributes: file),
            SFTPEntry(name: "x\0y", path: "/p/x\0y", attributes: file),
            SFTPEntry(name: "..", path: "/p/..", attributes: folder),
            SFTPEntry(name: "", path: "/p/", attributes: file),
        ]
        let entries = GlassTerminalDirectoryLister.entries(from: listed)
        #expect(entries.map(\.name) == ["src", ".env"])
        #expect(entries.map(\.isDirectory) == [true, false])
    }
}
