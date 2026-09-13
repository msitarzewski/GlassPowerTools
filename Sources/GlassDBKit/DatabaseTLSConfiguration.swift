//
//  DatabaseTLSConfiguration.swift
//  Glass Power Tools — GlassDBKit
//
//  One place where a `DatabaseTLSPolicy` becomes a NIOSSL configuration. Until D13 this switch
//  existed twice, byte for byte, in `MySQLAdapter.makeTLSConfiguration` and
//  `PostgreSQLAdapter.makeTLS`; two copies of a decision about what is verified is one copy too
//  many, and the CA-only mode had to be added to both. The adapters now differ only in how they
//  carry the result: MySQL takes a `TLSConfiguration` and a server hostname, PostgreSQL takes an
//  `NIOSSLContext` and sets the name on its options.
//

import Foundation
import NIOSSL

extension DatabaseTLSPolicy {
    /// The NIOSSL configuration this policy means, plus the hostname the handler should match
    /// against — `nil` when the policy deliberately matches no name.
    ///
    /// `connectionHost` is the address the socket is opened to, used only by the two policies
    /// that say "verify against the server I am contacting".
    func makeTLSConfiguration(connectionHost: String) throws -> (TLSConfiguration?, String?) {
        switch self {
        case .disabled:
            return (nil, nil)

        case .requiredSystemTrust:
            return (Self.baseConfiguration(), connectionHost)

        case .requiredSystemTrustForHost(let serverName):
            return (Self.baseConfiguration(), serverName)

        case .requiredCertificates(let certificateSources, let serverName):
            var configuration = Self.baseConfiguration()
            configuration.trustRoots = .certificates(try Self.certificates(from: certificateSources))
            configuration.certificateVerification = .fullVerification
            return (configuration, serverName ?? connectionHost)

        case .requiredCertificatesWithoutHostnameVerification(let certificateSources):
            var configuration = Self.baseConfiguration()
            configuration.trustRoots = .certificates(try Self.certificates(from: certificateSources))
            // Verifies the chain against the supplied roots and nothing else. NIOSSL:
            // "Certificates will be validated against the trust store, but will not be checked
            // to see if they are valid for the given hostname."
            configuration.certificateVerification = .noHostnameVerification
            // No hostname to match means no hostname to send: passing one would set SNI while
            // claiming no name is checked, which reads as if a name were being verified.
            return (configuration, nil)
        }
    }

    private static func baseConfiguration() -> TLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.minimumTLSVersion = .tlsv12
        return configuration
    }

    /// Parses user-supplied trust roots, failing before any socket is opened. A policy that
    /// names no usable certificate must never reach the network: with an empty `trustRoots` a
    /// verifying handshake would fail anyway, but it would fail as a network error rather than
    /// as the configuration error it is.
    private static func certificates(
        from sources: [DatabaseTLSCertificate]
    ) throws -> [NIOSSLCertificate] {
        guard !sources.isEmpty else {
            throw DatabaseError.invalidTLSCertificate("At least one certificate is required.")
        }
        do {
            let certificates = try sources.flatMap { source -> [NIOSSLCertificate] in
                switch source.format {
                case .pem:
                    return try NIOSSLCertificate.fromPEMBytes(Array(source.bytes))
                case .der:
                    return [try NIOSSLCertificate(bytes: Array(source.bytes), format: .der)]
                }
            }
            guard !certificates.isEmpty else {
                throw DatabaseError.invalidTLSCertificate("No certificates were found in the supplied data.")
            }
            return certificates
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.invalidTLSCertificate(error.localizedDescription)
        }
    }
}
