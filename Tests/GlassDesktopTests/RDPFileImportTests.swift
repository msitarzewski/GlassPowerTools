import Foundation
import Testing
@testable import GlassDesktop

@Suite("RDP file import")
struct RDPFileImportTests {
    @Test func importsEditableConnectionFields() throws {
        let result = try parse("""
        FULL ADDRESS:s:[2001:db8::7]:3390
        username:s:LAB\\alice
        domain:s:lab
        desktopwidth:i:1600
        desktopheight:i:900
        redirectclipboard:i:1
        audiomode:i:0
        """)
        let value = result.connection
        #expect(value.name == "Office")
        #expect(value.host == "2001:db8::7")
        #expect(value.port == 3390)
        #expect(value.username == "alice" && value.domain == "LAB")
        #expect(value.desktop == DesktopSize(width: 1600, height: 900))
        #expect(value.clipboardEnabled && value.audioEnabled)
        #expect(result.notices.isEmpty)
    }

    @Test(arguments: [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252])
    func readsCommonTextEncodings(_ encoding: String.Encoding) throws {
        let source = "full address:s:desktop.example\r\nusername:s:André\r\n"
        let data = try #require(source.data(using: encoding))
        let value = try RDPFileImporter.parse(data, suggestedName: "Office").connection
        #expect(value.username == "André")
        if encoding == .utf16LittleEndian || encoding == .utf16BigEndian || encoding == .utf8 {
            let bom: [UInt8] = encoding == .utf8 ? [0xEF, 0xBB, 0xBF] : encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
            #expect(try RDPFileImporter.parse(Data(bom) + data, suggestedName: "Office").connection.username == "André")
        }
    }

    @Test func handlesAddressesPortsAndAccountsWithoutGuessing() throws {
        let ipv6 = try parse("full address:s:2001:db8::1\nserver port:i:3391\nusername:s:alice@example.test")
        #expect(ipv6.connection.host == "2001:db8::1" && ipv6.connection.port == 3391)
        #expect(ipv6.connection.username == "alice@example.test" && ipv6.connection.domain.isEmpty)
        let scoped = try parse("full address:s:[fe80::1%en0]:3389")
        #expect(scoped.connection.host == "fe80::1%en0")
        let explicit = try parse("full address:s:desktop.example:3390\nserver port:i:3389")
        #expect(explicit.connection.port == 3390)
        #expect(explicit.notices.count == 1)
    }

    @Test func leavesCredentialsAndTrustOutOfImportedData() throws {
        let result = try parse("""
        full address:s:desktop.example
        password 51:b:DEADBEEF-IMPORT-SECRET
        password:s:IMPORT-SECRET
        authentication level:i:0
        enablecredsspsupport:i:0
        negotiate security layer:i:0
        signature:s:IMPORT-SIGNATURE
        """)
        #expect(result.connection.authentication == .networkLevel)
        #expect(result.connection.certificateSHA256 == nil)
        #expect(result.connection.mobility == .deviceOnly)
        #expect(!result.connection.clipboardEnabled && !result.connection.audioEnabled)
        let saved = String(decoding: try JSONEncoder().encode(result.connection), as: UTF8.self)
        #expect(!saved.contains("IMPORT-SECRET") && !saved.contains("IMPORT-SIGNATURE"))
        #expect(!result.notices.joined().contains("IMPORT-SECRET"))
        #expect(result.notices.count == 3)
        let second = try parse("full address:s:desktop.example")
        #expect(result.connection.id != second.connection.id)
        #expect(result.connection.credentialID != second.connection.credentialID)
    }

    @Test func preservesSupportedResolutionAndExplainsAdjustments() throws {
        let odd = try parse("full address:s:desktop.example\ndesktopwidth:i:1921\ndesktopheight:i:1080")
        #expect(odd.connection.desktop == .standard && odd.notices.count == 1)
        let large = try parse("full address:s:desktop.example\ndesktopwidth:i:8192\ndesktopheight:i:8192")
        #expect(large.connection.desktop == DesktopSize(width: 4096, height: 4096))
        let preset = try parse("full address:s:desktop.example\ndesktop size id:i:2")
        #expect(preset.connection.desktop == DesktopSize(width: 1024, height: 768))
        let remoteAudio = try parse("full address:s:desktop.example\naudiomode:i:1")
        #expect(!remoteAudio.connection.audioEnabled && remoteAudio.notices.count == 1)
    }

    @Test(arguments: [
        "full address:s:host:0", "full address:s:host:65536", "full address:s:host:not-a-port",
        "full address:s:https://host", "full address:s:user@host", "full address:s:[host]",
        "full address:s:2001:invalid::1", "full address:s:[::1]suffix", "full address:s:[::1]:",
        "full address:s:host\nFULL ADDRESS:s:other", "full address:s:host\nredirectclipboard:i:2",
        "full address:s:host\naudiomode:i:3", "full address:s:host\ndesktopwidth:i:-1",
        "full address:s:host\ndesktopheight:i:9999999999999999999999999999",
        "full address:i:7", "full address:s:host\nusername:s:ONE\\alice\ndomain:s:TWO",
        "full address:s:host\nusername:s:ONE\\alice\\extra", "full address:s:host\nmalformed", "username:s:alice"
    ])
    func rejectsMalformedAndAmbiguousInput(_ source: String) {
        #expect(throws: (any Error).self) { try parse(source) }
    }

    @Test(arguments: ["gatewayhostname:s:gateway.example", "remoteapplicationmode:i:1",
                      "remoteapplicationprogram:s:||app", "loadbalanceinfo:s:broker-routing",
                      "pcb:s:broker-id", "enablerdsaadauth:i:1", "targetisaadjoined:i:1",
                      "alternate shell:s:remote-program", "shell working directory:s:C:\\Work"])
    func rejectsUnsupportedConnectionWorkflows(_ setting: String) {
        #expect(throws: (any Error).self) { try parse("full address:s:desktop.example\n" + setting) }
    }

    @Test func boundsFilesAndRejectsInvalidEncoding() throws {
        #expect(throws: (any Error).self) {
            try RDPFileImporter.parse(Data(repeating: 65, count: RDPFileImporter.maximumBytes + 1), suggestedName: "Large")
        }
        #expect(throws: (any Error).self) {
            try RDPFileImporter.parse(Data([0xFF, 0xFE, 0x41]), suggestedName: "Broken")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Office.RDP")
        try Data("full address:s:desktop.example".utf8).write(to: url)
        #expect(try RDPFileImporter.read(from: url).connection.name == "Office")
        #expect(throws: (any Error).self) { try RDPFileImporter.read(from: directory) }
        #expect(throws: (any Error).self) { try RDPFileImporter.read(from: URL(string: "https://example.test/a.rdp")!) }
    }

    @MainActor @Test func reviewDoesNotSaveAndConfirmedImportSurvivesReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = DesktopAppModel(storageDirectory: directory)
        await model.load()
        let draft = try parse("full address:s:localhost:3390\nusername:s:alice\ndesktopwidth:i:1600\ndesktopheight:i:900")
        #expect(model.connections.isEmpty)
        try await model.save(draft.connection, password: nil)
        let relaunched = DesktopAppModel(storageDirectory: directory)
        await relaunched.load()
        #expect(relaunched.errorMessage == nil)
        #expect(relaunched.connections.count == 1)
        #expect(relaunched.connections.first?.host == "localhost")
        #expect(relaunched.connections.first?.port == 3390)
        #expect(relaunched.connections.first?.desktop == DesktopSize(width: 1600, height: 900))
        #expect(relaunched.connections.first?.credentialID == draft.connection.credentialID)
    }

    private func parse(_ source: String) throws -> RDPFileImport {
        try RDPFileImporter.parse(Data(source.utf8), suggestedName: "Office")
    }
}
