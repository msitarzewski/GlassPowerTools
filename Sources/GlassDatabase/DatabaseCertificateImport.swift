//
//  DatabaseCertificateImport.swift
//  Glass Power Tools — GlassDatabase
//
//  Reads a certificate file the user picked and says what is in it, so a trust root is checked
//  while the sheet is open rather than at the next connection attempt.
//
//  Shaped after `Sources/GlassTerminal/SSHPrivateKeyImport.swift`, the house pattern for
//  importing trust material: refuse by size before reading anything, parse through the engine
//  that owns the format rather than re-implementing it here, and hand the caller back facts for
//  the form's own state. The parsing itself is `DatabaseTLSCertificate.inspect()` in GlassDBKit,
//  which owns NIOSSL.
//

import Foundation
import UniformTypeIdentifiers
import GlassDBKit

enum DatabaseCertificateImportError: LocalizedError, Equatable {
    case unreadable
    case tooLarge(Int)
    case notACertificate(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "The file could not be read."
        case .tooLarge(let bytes):
            "The file is \(bytes) bytes; a certificate is far smaller. Choose the certificate file itself, not an archive or a database."
        case .notACertificate(let reason):
            "This is not a certificate file. \(reason)"
        }
    }
}

enum DatabaseCertificateImport {
    /// The record's own bound, so a file that imports can always be saved.
    static let maximumFileSize = DatabaseConnectionConfig.maximumTLSCertificateBytes

    /// What a server's CA is usually saved as. `.data` is included because a CA file often has
    /// no extension the system recognises at all (`ca.pem` from a MySQL data directory), and the
    /// contents decide the format in any case.
    static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for filenameExtension in ["pem", "crt", "cer", "der", "ca-bundle"] {
            if let type = UTType(filenameExtension: filenameExtension) {
                types.insert(type, at: 0)
            }
        }
        if let x509 = UTType("public.x509-certificate") { types.insert(x509, at: 0) }
        return types
    }

    /// Reads a user-chosen file inside its security scope and parses it. Returns the bytes to
    /// store and what they contain; the caller keeps both in the draft until commit.
    ///
    /// Nothing is copied anywhere: unlike the SQLite import there is no managed file, because
    /// the bytes go into the record itself.
    static func read(from url: URL) throws -> (bytes: Data, inspection: DatabaseTLSCertificateInspection) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Refuse by size before loading: a mischosen multi-gigabyte file must not be read into
        // memory just to be rejected.
        let size: Int
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch {
            throw DatabaseCertificateImportError.unreadable
        }
        guard size <= maximumFileSize else { throw DatabaseCertificateImportError.tooLarge(size) }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.uncached])
        } catch {
            throw DatabaseCertificateImportError.unreadable
        }
        guard data.count <= maximumFileSize else {
            throw DatabaseCertificateImportError.tooLarge(data.count)
        }
        guard !data.isEmpty else {
            throw DatabaseCertificateImportError.notACertificate("The file is empty.")
        }
        return (data, try inspect(data))
    }

    /// Parses stored bytes. Used by the importer and again when an existing service is opened
    /// for editing, so a record whose certificate has since expired says so in the sheet.
    static func inspect(_ bytes: Data) throws -> DatabaseTLSCertificateInspection {
        let material = DatabaseTLSCertificate(
            bytes: bytes,
            format: DatabaseConnectionConfig.certificateFormat(of: bytes)
        )
        do {
            return try material.inspect()
        } catch let error as DatabaseError {
            throw DatabaseCertificateImportError.notACertificate(
                error.errorDescription ?? "The contents could not be parsed as PEM or DER."
            )
        } catch {
            throw DatabaseCertificateImportError.notACertificate(error.localizedDescription)
        }
    }

    /// One line for the form: how many certificates, the first one's fingerprint, and a warning
    /// when any of them is outside its validity window. The fingerprint is the whole point — it
    /// is what a user compares against `openssl x509 -fingerprint -sha256 -in ca.pem -noout`
    /// on the server, the same out-of-band check the terminal's host-key fingerprint gets.
    static func summary(
        of inspection: DatabaseTLSCertificateInspection,
        asOf now: Date = Date()
    ) -> String {
        guard let first = inspection.certificates.first else { return "No certificates found." }
        var parts: [String] = []
        parts.append(inspection.count == 1 ? "1 certificate" : "\(inspection.count) certificates")
        parts.append("SHA-256 \(first.fingerprintSHA256)")
        let outOfWindow = inspection.expiredCertificates(asOf: now)
        if !outOfWindow.isEmpty {
            parts.append(outOfWindow.count == inspection.count
                         ? "Outside its validity window — the server will not be accepted."
                         : "\(outOfWindow.count) of these are outside their validity window.")
        }
        return parts.joined(separator: " · ")
    }
}
