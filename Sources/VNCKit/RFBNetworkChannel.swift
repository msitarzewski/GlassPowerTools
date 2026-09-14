import Foundation
import Network

/// TCP channel over Network.framework. Reads are served from an internal buffer and refilled
/// with bounded receives; writes are serialized in call order.
public actor RFBNetworkChannel: RFBByteSource, RFBByteSink {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.glassdt.vnc.channel")
    private var buffer: [UInt8] = []
    private var bufferOffset = 0
    private var closed = false

    public init(host: String, port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port), !host.isEmpty else {
            throw RFBError.invalidConfiguration("The host or port is invalid.")
        }
        let parameters = NWParameters.tcp
        parameters.serviceClass = .responsiveData
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.connectionTimeout = 20
        }
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
    }

    public func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let box = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: box.resume(.success(()))
                case .failed(let error): box.resume(.failure(RFBError.connectionFailed(Self.describe(error))))
                case .waiting(let error): box.resume(.failure(RFBError.connectionFailed(Self.describe(error))))
                case .cancelled: box.resume(.failure(RFBError.cancelled))
                default: break
                }
            }
            connection.start(queue: queue)
        }
        connection.stateUpdateHandler = nil
    }

    public func close() {
        closed = true
        connection.cancel()
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        guard count >= 0 else { throw RFBError.protocolViolation("Negative read length.") }
        guard count <= RFBLimits.maximumEncodedRectangleBytes else { throw RFBError.resourceLimit("The server message is too large.") }
        while buffer.count - bufferOffset < count {
            if closed { throw RFBError.cancelled }
            let needed = count - (buffer.count - bufferOffset)
            let chunk = try await receive(minimum: needed, maximum: max(needed, 256 * 1024))
            if bufferOffset > 0 {
                buffer.removeFirst(bufferOffset)
                bufferOffset = 0
            }
            buffer.append(contentsOf: chunk)
        }
        let result = Array(buffer[bufferOffset..<(bufferOffset + count)])
        bufferOffset += count
        if bufferOffset == buffer.count { buffer.removeAll(keepingCapacity: true); bufferOffset = 0 }
        return result
    }

    private func receive(minimum: Int, maximum: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], any Error>) in
            connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { content, _, isComplete, error in
                if let error { continuation.resume(throwing: RFBError.connectionFailed(Self.describe(error))); return }
                let bytes = content.map { [UInt8]($0) } ?? []
                if bytes.count < minimum {
                    continuation.resume(throwing: isComplete ? RFBError.connectionClosed : RFBError.connectionFailed("The connection returned a short read."))
                    return
                }
                continuation.resume(returning: bytes)
            }
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard !closed else { throw RFBError.cancelled }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: RFBError.connectionFailed(Self.describe(error))) }
                else { continuation.resume(returning: ()) }
            })
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "The server refused the connection."
            case .ETIMEDOUT: return "The connection timed out."
            case .EHOSTUNREACH, .ENETUNREACH: return "The host is unreachable."
            case .ECONNRESET: return "The server reset the connection."
            default: return "Network error \(code.rawValue)."
            }
        case .dns: return "The host name could not be resolved."
        case .tls: return "A TLS error occurred."
        default: return "The connection failed."
        }
    }
}

private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    init(_ continuation: CheckedContinuation<T, any Error>) { self.continuation = continuation }
    func resume(_ result: Result<T, any Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
    }
}
