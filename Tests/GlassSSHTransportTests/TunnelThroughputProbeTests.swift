import Foundation
import Testing
@testable import GlassSSHTransport

/// How fast the database tunnel is, against the same service reached directly (2026-10-05: 100
/// rows took 9.5 s through a tunnel). Gated: needs the test host and GPT_TUNNEL_PROBE_PORT, a
/// service on the host that answers "B" with 50 MB and "P" with one byte. Prints, asserts nothing
/// about speed — a measurement, not a pass mark.
@Suite("Tunnel throughput (gated probe)", .serialized)
struct TunnelThroughputProbeTests {
    /// A plain blocking socket, the same for both paths.
    private func measure(host: String, port: Int) throws -> (bulkSeconds: Double, pingMs: Double) {
        func open() throws -> Int32 {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                                 ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var info: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, String(port), &hints, &info) == 0, let info else { throw POSIXError(.EHOSTUNREACH) }
            defer { freeaddrinfo(info) }
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var one: Int32 = 1
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
            guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
            return fd
        }
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        // Bulk: 50 MB.
        let bulk = try open()
        let start = Date()
        _ = "B".withCString { send(bulk, $0, 1, 0) }
        var total = 0
        while total < 50 * 1024 * 1024 {
            let n = recv(bulk, &buffer, buffer.count, 0)
            if n <= 0 { break }
            total += n
        }
        let bulkSeconds = Date().timeIntervalSince(start)
        close(bulk)
        // Ping: 200 one-byte round trips.
        let ping = try open()
        let pingStart = Date()
        for _ in 0..<200 {
            _ = "P".withCString { send(ping, $0, 1, 0) }
            _ = recv(ping, &buffer, 1, 0)
        }
        let pingMs = Date().timeIntervalSince(pingStart) * 1000 / 200
        close(ping)
        return (bulkSeconds, pingMs)
    }

    /// A measurement, printed, not a check: the test host and GPT_TUNNEL_PROBE_PORT set.
    @Test(.enabled(if: IntegrationEnvironment.isConfigured && ProcessInfo.processInfo.environment["GPT_TUNNEL_PROBE_PORT"] != nil,
                   "a throughput probe: set the test host and GPT_TUNNEL_PROBE_PORT"))
    func compareTunnelWithDirect() async throws {
        let port = try #require(ProcessInfo.processInfo.environment["GPT_TUNNEL_PROBE_PORT"].flatMap(Int.init))
        let host = IntegrationEnvironment.host!
        let direct = try measure(host: host, port: port)
        print(String(format: "DIRECT : 50 MB in %.2f s (%.1f MB/s), round trip %.2f ms", direct.bulkSeconds, 50 / direct.bulkSeconds, direct.pingMs))

        let transport = IntegrationTransport.make()
        try await transport.connect()
        let endpoint = try await DatabaseTunnelConsumer(transport: transport).localEndpoint(forDatabaseAt: "127.0.0.1", port: port)
        let tunnelled = try await Task.detached { try self.measure(host: "127.0.0.1", port: endpoint.port) }.value
        print(String(format: "TUNNEL : 50 MB in %.2f s (%.1f MB/s), round trip %.2f ms", tunnelled.bulkSeconds, 50 / tunnelled.bulkSeconds, tunnelled.pingMs))
        await endpoint.tunnel.close()
        await transport.close()
    }
}
