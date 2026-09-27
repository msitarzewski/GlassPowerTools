import Foundation

public struct RDPFileImport: Sendable {
    public let connection: DesktopConnection
    public let notices: [String]
}

/// Imports a connection draft, never credentials, trust decisions or executable settings.
public enum RDPFileImporter {
    public static let maximumBytes = 1_048_576

    public static func read(from url: URL) throws -> RDPFileImport {
        guard url.isFileURL, url.pathExtension.lowercased() == "rdp" else { throw RDPFileImportError.notRDPFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw RDPFileImportError.notRDPFile }
        guard (values.fileSize ?? 0) <= maximumBytes else { throw RDPFileImportError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try parse(data, suggestedName: url.deletingPathExtension().lastPathComponent)
    }

    public static func parse(_ data: Data, suggestedName: String) throws -> RDPFileImport {
        guard data.count <= maximumBytes else { throw RDPFileImportError.tooLarge }
        let text = try decode(data)
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard lines.count <= 8_192 else { throw RDPFileImportError.tooLarge }
        var fields: [String: Field] = [:]
        var notices = Set<Notice>()
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { throw RDPFileImportError.malformedLine(index + 1) }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let type = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, key.count <= 128, ["s", "i", "b"].contains(type) else {
                throw RDPFileImportError.malformedLine(index + 1)
            }
            if ["password", "password 51", "password51", "gatewaypassword"].contains(key) {
                notices.insert(.password)
                continue
            }
            guard supportedFields.contains(key) else { notices.insert(.other); continue }
            guard fields[key] == nil else { throw RDPFileImportError.repeatedSetting }
            fields[key] = Field(type: type, value: parts[2].trimmingCharacters(in: .whitespaces))
        }
        func string(_ key: String) throws -> String? {
            guard let field = fields[key] else { return nil }
            guard field.type == "s" else { throw RDPFileImportError.invalidValue }
            return field.value
        }
        func integer(_ key: String) throws -> Int? {
            guard let field = fields[key] else { return nil }
            guard field.type == "i", let value = Int(field.value) else { throw RDPFileImportError.invalidValue }
            return value
        }
        func flag(_ key: String) throws -> Bool? {
            guard let value = try integer(key) else { return nil }
            guard value == 0 || value == 1 else { throw RDPFileImportError.invalidValue }
            return value == 1
        }

        func nonEmpty(_ key: String) throws -> Bool { !(try string(key) ?? "").isEmpty }

        // These workflows cannot be represented by a direct saved desktop.
        if let gateway = try string("gatewayhostname"), !gateway.isEmpty { throw RDPFileImportError.gateway }
        if try flag("remoteapplicationmode") == true || nonEmpty("remoteapplicationprogram") {
            throw RDPFileImportError.remoteApp
        }
        if try nonEmpty("loadbalanceinfo") || nonEmpty("pcb") {
            throw RDPFileImportError.broker
        }
        if try flag("enablerdsaadauth") == true || flag("targetisaadjoined") == true { throw RDPFileImportError.entra }
        if try nonEmpty("alternate shell") || nonEmpty("shell working directory") {
            throw RDPFileImportError.remoteProgram
        }

        guard let address = try string("full address"), !address.isEmpty else { throw RDPFileImportError.missingHost }
        let endpoint = try splitAddress(address)
        let separatePort = try integer("server port")
        if let separatePort, !(1...65_535).contains(separatePort) { throw DesktopError.invalidPort }
        if let port = endpoint.port, let separatePort, Int(port) != separatePort { notices.insert(.port) }
        var username = try string("username") ?? ""
        var domain = try string("domain") ?? ""
        if let slash = username.firstIndex(of: "\\") {
            let prefix = String(username[..<slash])
            let account = String(username[username.index(after: slash)...])
            guard !prefix.isEmpty, !account.isEmpty, !account.contains("\\"),
                  domain.isEmpty || domain.caseInsensitiveCompare(prefix) == .orderedSame else {
                throw DesktopError.invalidAccount
            }
            domain = prefix
            username = account
        }
        let name = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        var connection = DesktopConnection(name: name.isEmpty ? endpoint.host : String(name.prefix(256)),
            host: endpoint.host, port: endpoint.port ?? separatePort.map(UInt16.init) ?? 3389,
            username: username, domain: domain)

        let width = try integer("desktopwidth")
        let height = try integer("desktopheight")
        if width != nil || height != nil {
            let requested = DesktopSize(width: width ?? connection.desktop.width, height: height ?? connection.desktop.height)
            guard (200...8192).contains(requested.width), (200...8192).contains(requested.height) else {
                throw DesktopError.invalidDesktop
            }
            connection.desktop = DesktopSize.fitting(width: Double(requested.width), height: Double(requested.height))
            if connection.desktop != requested { notices.insert(.resolution) }
        } else if let size = try integer("desktop size id") {
            let sizes = [DesktopSize(width: 640, height: 480), DesktopSize(width: 800, height: 600),
                         DesktopSize(width: 1024, height: 768), DesktopSize(width: 1280, height: 1024),
                         DesktopSize(width: 1600, height: 1200)]
            guard sizes.indices.contains(size) else { throw DesktopError.invalidDesktop }
            connection.desktop = sizes[size]
        }
        connection.clipboardEnabled = try flag("redirectclipboard") ?? false
        if let audio = try integer("audiomode") {
            guard (0...2).contains(audio) else { throw RDPFileImportError.invalidValue }
            connection.audioEnabled = audio == 0
            if audio == 1 { notices.insert(.audio) }
        }
        if let level = try integer("authentication level") {
            guard (0...3).contains(level) else { throw RDPFileImportError.invalidValue }
            if level != 1 { notices.insert(.authentication) }
        }
        if try flag("enablecredsspsupport") == false { notices.insert(.authentication) }
        if try flag("negotiate security layer") == false { notices.insert(.authentication) }
        if let gatewayMethod = try integer("gatewayusagemethod"), gatewayMethod != 0 { notices.insert(.other) }

        return RDPFileImport(connection: try connection.validated(),
            notices: Notice.allCases.filter { notices.contains($0) }.map(\.message))
    }

    private struct Field { let type: String; let value: String }
    private static let supportedFields: Set<String> = [
        "full address", "server port", "username", "domain", "desktopwidth", "desktopheight", "desktop size id",
        "redirectclipboard", "audiomode", "authentication level", "enablecredsspsupport", "negotiate security layer",
        "gatewayhostname", "gatewayusagemethod", "remoteapplicationmode", "remoteapplicationprogram", "loadbalanceinfo",
        "pcb", "enablerdsaadauth", "targetisaadjoined", "alternate shell", "shell working directory"
    ]

    private static func decode(_ data: Data) throws -> String {
        let text: String?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { text = String(data: data.dropFirst(3), encoding: .utf8) }
        else if data.starts(with: [0xFF, 0xFE]) { text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        else if data.starts(with: [0xFE, 0xFF]) { text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        else if data.prefix(128).contains(0) {
            text = String(data: data, encoding: data.first == 0 ? .utf16BigEndian : .utf16LittleEndian)
        } else { text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) }
        guard let text, !text.contains("\0"), !text.contains("\u{FFFD}") else { throw RDPFileImportError.encoding }
        return text
    }

    private static func splitAddress(_ address: String) throws -> (host: String, port: UInt16?) {
        func port(_ text: Substring) throws -> UInt16 {
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = UInt16(text), value > 0 else { throw DesktopError.invalidPort }
            return value
        }
        if address.hasPrefix("[") {
            guard let close = address.firstIndex(of: "]") else { throw DesktopError.invalidHost }
            let host = String(address[address.index(after: address.startIndex)..<close])
            guard host.contains(":") else { throw DesktopError.invalidHost }
            let suffix = address[address.index(after: close)...]
            if suffix.isEmpty { return (host, nil) }
            guard suffix.first == ":" else { throw DesktopError.invalidHost }
            return (host, try port(suffix.dropFirst()))
        }
        if address.filter({ $0 == ":" }).count == 1, let colon = address.firstIndex(of: ":") {
            return (String(address[..<colon]), try port(address[address.index(after: colon)...]))
        }
        return (address, nil)
    }

    private enum Notice: CaseIterable {
        case password, authentication, port, resolution, audio, other
        var message: String {
            switch self {
            case .password: "Saved passwords aren't imported. Enter it in Password below, or when connecting."
            case .authentication: "Authentication preferences in the file weren't imported. Network Level Authentication and certificate review remain enabled."
            case .port: "The port in the server address takes precedence over the file's separate port setting."
            case .resolution: "The initial resolution was adjusted to fit supported desktop limits."
            case .audio: "Playback on the remote computer isn't imported. Remote audio is off; enable it below to play sound on this device."
            case .other: "Other client-specific settings in the file weren't imported. Review the connection settings below."
            }
        }
    }
}

public enum RDPFileImportError: Error, LocalizedError {
    case notRDPFile, tooLarge, encoding, malformedLine(Int), repeatedSetting, invalidValue, missingHost
    case gateway, remoteApp, broker, entra, remoteProgram
    public var errorDescription: String? {
        switch self {
        case .notRDPFile: "Choose a regular .rdp file."
        case .tooLarge: "This RDP file is too large. Choose a file smaller than 1 MB."
        case .encoding: "The RDP file's text encoding is invalid. Save it as UTF-8 or UTF-16 and try again."
        case .malformedLine(let line): "Line \(line) isn't a valid RDP setting."
        case .repeatedSetting: "The file repeats a connection setting. Remove the duplicate before importing."
        case .invalidValue: "An RDP connection setting has an invalid type or value."
        case .missingHost: "The RDP file doesn't contain a server address."
        case .gateway: "This file specifies an RD Gateway, which this app doesn't support. Import a direct desktop connection instead."
        case .remoteApp: "This is a RemoteApp connection. This app currently imports full desktop connections."
        case .broker: "This file requires broker routing that this app doesn't support. Import a direct desktop connection instead."
        case .entra: "This file requires Microsoft Entra authentication, which this app doesn't support."
        case .remoteProgram: "This file starts a custom remote program. This app currently imports standard desktop sessions."
        }
    }
}
