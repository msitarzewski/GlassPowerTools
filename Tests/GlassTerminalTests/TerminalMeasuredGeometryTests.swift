import Foundation
import Testing
@testable import GlassTerminal

/// The PTY gets what the view holds (2026-10-04: an iPhone on its side with the keyboard up).
@Suite("Measured terminal size")
@MainActor
struct TerminalMeasuredGeometryTests {
    @Test("a configured size keeps its floor; a measured one is the truth down to 2 rows")
    func ranges() {
        #expect(TerminalGeometry(rows: 4, columns: 60).rows == 8)
        #expect(TerminalGeometry(measuredRows: 4, columns: 60).rows == 4)
        #expect(TerminalGeometry(measuredRows: 0, columns: 3).rows == 2)
        #expect(TerminalGeometry(measuredRows: 0, columns: 3).columns == 10)
    }

    @Test("four visible rows reach the host as four")
    func resizeReachesHost() async throws {
        var resizes: [String] = []
        let session = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"),
                                      terminalResizeSink: { rows, columns in resizes.append("\(columns)x\(rows)") })
        session.state = .connected
        session.updateTerminalGeometry(rows: 4, columns: 96)
        for _ in 0..<50 where resizes.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(resizes.last == "96x4")
    }
}
