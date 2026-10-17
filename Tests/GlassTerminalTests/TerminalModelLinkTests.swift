import Foundation
import Testing
@testable import GlassTerminal

/// A terminal's link to a 3D model (D78): downloaded, kept only if its bytes are a model's, and
/// refused in words otherwise. The network is a stand-in: each test's session answers from a table.
@Suite("A model's link, downloaded", .serialized)
struct TerminalModelLinkTests {
    /// Answers every request with the status and bytes the table holds for its URL.
    nonisolated final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var answers: [URL: (status: Int, body: Data)] = [:]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url, let answer = Self.answers[url],
                  let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                                 headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return URLSession(configuration: configuration)
    }

    private func inbox() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalModelLinkTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A USDZ's opening: a zip whose first entry is a stored `.usdc`.
    private let usdz = Data([0x50, 0x4B, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00] + Array(repeating: 0, count: 16)
                            + [10, 0, 0, 0] + Array("scene.usdc".utf8) + Array(repeating: 0, count: 200))

    @Test("a model is kept under its link's name, in a folder of its own")
    func keepsAModel() async throws {
        let url = try #require(URL(string: "https://example.com/ar/imac-with-accessories-blue.usdz"))
        Stub.answers[url] = (200, usdz)
        let inbox = try inbox()
        defer { try? FileManager.default.removeItem(at: inbox) }
        let file = try await TerminalModelDownload.download(url, session: session, inbox: inbox)
        #expect(file.lastPathComponent == "imac-with-accessories-blue.usdz")
        #expect(file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
                == inbox.standardizedFileURL.path)
        #expect(try Data(contentsOf: file) == usdz)
    }

    @Test("a web page behind a model's name is refused, and nothing is kept")
    func refusesAPage() async throws {
        let url = try #require(URL(string: "https://example.com/not-really.usdz"))
        Stub.answers[url] = (200, Data("<!doctype html><title>Sign in</title>".utf8))
        let inbox = try inbox()
        defer { try? FileManager.default.removeItem(at: inbox) }
        await #expect(throws: TerminalModelDownload.Failure.notAModel(name: "not-really.usdz")) {
            try await TerminalModelDownload.download(url, session: session, inbox: inbox)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
    }

    @Test("a server's refusal and a file past the limit say so in words")
    func refusals() async throws {
        let missing = try #require(URL(string: "https://example.com/gone.usdz"))
        Stub.answers[missing] = (404, Data())
        let large = try #require(URL(string: "https://example.com/large.usdz"))
        Stub.answers[large] = (200, usdz)
        let inbox = try inbox()
        defer { try? FileManager.default.removeItem(at: inbox) }
        await #expect(throws: TerminalModelDownload.Failure.server(status: 404)) {
            try await TerminalModelDownload.download(missing, session: session, inbox: inbox)
        }
        await #expect(throws: TerminalModelDownload.Failure.tooLarge(bytes: Int64(usdz.count), limit: 64)) {
            try await TerminalModelDownload.download(large, session: session, inbox: inbox, limit: 64)
        }
        let words = TerminalModelDownload.Failure.server(status: 404).errorDescription ?? ""
        #expect(words.contains("404") && words.contains("browser"), "\(words)")
    }

    @Test("a link with no file name is saved as a model all the same")
    func names() throws {
        #expect(TerminalModelDownload.fileName(for: try #require(URL(string: "https://example.com/a/b.usdz?x=1"))) == "b.usdz")
        #expect(TerminalModelDownload.fileName(for: try #require(URL(string: "https://example.com/"))) == "model.usdz")
    }
}
