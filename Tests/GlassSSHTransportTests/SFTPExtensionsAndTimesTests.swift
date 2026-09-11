import Foundation
import Testing
@testable import GlassSSHTransport

@Suite("SFTP extensions and file times")
struct SFTPExtensionsAndTimesTests {
    private let openSSH = SFTPServerExtensions([
        "posix-rename@openssh.com": "1", "hardlink@openssh.com": "1", "fsync@openssh.com": "1",
        "statvfs@openssh.com": "2", "lsetstat@openssh.com": "1",
    ])

    @Test func extensionsAreQueriedByNameAndExactVersion() {
        #expect(openSSH.supportsPOSIXRename && openSSH.supportsHardLink && openSSH.supportsFSync)
        #expect(openSSH.supports("statvfs@openssh.com"))
        #expect(openSSH.supports("statvfs@openssh.com", version: "2"))
        #expect(!openSSH.supports("statvfs@openssh.com", version: "1"), "a version pin is exact")
        #expect(openSSH.version(of: "lsetstat@openssh.com") == "1")
        let bare = SFTPServerExtensions()
        #expect(!bare.supportsPOSIXRename && !bare.supportsHardLink && !bare.supportsFSync)
        #expect(SFTPServerExtensions(["posix-rename@openssh.com": "2"]).supportsPOSIXRename == false, "only version 1 is the OpenSSH contract")
    }

    @Test func selfAndParentReferencesAreNeverEntriesAndNeverSafeNames() {
        #expect(SFTPEntry.isSelfOrParent(".") && SFTPEntry.isSelfOrParent(".."))
        #expect(!SFTPEntry.isSelfOrParent(".hidden") && !SFTPEntry.isSelfOrParent("..."))
        #expect(!SFTPEntry.isSafeName(".") && !SFTPEntry.isSafeName(".."))
        #expect(SFTPEntry.isSafeName(".hidden") && SFTPEntry.isSafeName("..."))
    }

    @Test func attributeChangesSendOnlyWhatIsSetAndRefusePartialTimes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let both = SFTPAttributeChanges(permissions: 0o644, accessed: now, modified: now)
        #expect(!both.isEmpty && !both.hasPartialTimes)
        #expect(both.citadelAttributes.flags.contains(.permissions))
        #expect(both.citadelAttributes.flags.contains(.acmodtime))
        #expect(!both.citadelAttributes.flags.contains(.size))
        #expect(SFTPAttributeChanges(accessed: now).hasPartialTimes)
        #expect(SFTPAttributeChanges().isEmpty)
        #expect(!SFTPAttributeChanges(accessed: now).citadelAttributes.flags.contains(.acmodtime), "a lone time is never sent")
    }

    @Test func setTimesFillsTheMissingSideFromTheFile() async throws {
        let session = FakeSFTPSession()
        try await session.writeFile(Data("x".utf8), to: "/f")
        let a = Date(timeIntervalSince1970: 1_000), m = Date(timeIntervalSince1970: 2_000), m2 = Date(timeIntervalSince1970: 3_000)
        try await session.setTimes(at: "/f", accessed: a, modified: m)
        var attributes = try await session.attributes(at: "/f")
        #expect(attributes.accessTime == a && attributes.modificationTime == m)

        try await session.setTimes(at: "/f", modified: m2)          // only one side given
        attributes = try await session.attributes(at: "/f")
        #expect(attributes.accessTime == a, "the untouched side is preserved from the file")
        #expect(attributes.modificationTime == m2)

        try await session.setTimes(at: "/f")                        // nothing given → no-op
        #expect(try await session.attributes(at: "/f").modificationTime == m2)
        await #expect(throws: SFTPSessionError.partialTimes) {
            try await session.setAttributes(SFTPAttributeChanges(accessed: a), at: "/f")
        }
    }

    @Test func setPermissionsIsASetAttributesConvenience() async throws {
        let session = FakeSFTPSession()
        try await session.writeFile(Data(), to: "/script.sh")
        try await session.setPermissions(0o755, at: "/script.sh")
        #expect(try await session.attributes(at: "/script.sh").mode == 0o755)
    }

    @Test func consumersChooseExtensionsFromWhatTheServerAdvertises() async throws {
        // With posix-rename: replace is atomic and uses it.
        let modern = FakeSFTPSession(extensions: openSSH)
        try await modern.writeFile(Data("old".utf8), to: "/doc")
        try await modern.writeFile(Data("new".utf8), to: "/doc.tmp")
        try await modern.replace("/doc", with: "/doc.tmp")
        #expect(try await modern.readFile(at: "/doc") == Data("new".utf8))
        #expect(await modern.posixRenames == 1)
        try await modern.writeFile(Data("h".utf8), to: "/a")
        try await modern.hardLink("/a", to: "/b")
        #expect(try await modern.readFile(at: "/b") == Data("h".utf8))
        let handle = try await modern.open("/a", mode: .read)
        try await handle.synchronize()

        // Without: replace falls back to remove + rename; the extension calls report unsupported.
        let legacy = FakeSFTPSession()
        try await legacy.writeFile(Data("old".utf8), to: "/doc")
        try await legacy.writeFile(Data("new".utf8), to: "/doc.tmp")
        try await legacy.replace("/doc", with: "/doc.tmp")
        #expect(try await legacy.readFile(at: "/doc") == Data("new".utf8))
        #expect(await legacy.posixRenames == 0)
        await #expect(throws: SFTPSessionError.extensionUnsupported("posix-rename@openssh.com")) { try await legacy.posixRename("/doc", to: "/x") }
        await #expect(throws: SFTPSessionError.extensionUnsupported("hardlink@openssh.com")) { try await legacy.hardLink("/doc", to: "/x") }
        let legacyHandle = try await legacy.open("/doc", mode: .read)
        await #expect(throws: SFTPSessionError.extensionUnsupported("fsync@openssh.com")) { try await legacyHandle.synchronize() }
    }
}
