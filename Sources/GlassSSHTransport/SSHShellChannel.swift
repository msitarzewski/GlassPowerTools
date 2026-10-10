import Foundation
@preconcurrency import Citadel
import NIOCore
@preconcurrency import NIOSSH

/// The PTY glas.sh requested for every interactive session (`runInteractiveTTY`, Models.swift:2320).
public struct SSHPTYRequest: Sendable, Hashable {
    public var columns: Int
    public var rows: Int
    public init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}

public enum SSHShellOutput: Sendable {
    case stdout(Data)
    case stderr(Data)
}

/// How an interactive shell ended, delivered once as the output stream finishes.
public enum SSHShellExit: Sendable, Equatable {
    /// The remote side closed cleanly (EOF, `exit`, logout).
    case remoteClosed
    case cancelled
    case failed(String)
}

/// An interactive shell over a PTY. Output arrives on `output`; input goes through `write`.
/// The stream finishes with `remoteClosed`, `cancelled` or `failed` recorded in `exit`.
public actor SSHShellChannel {
    public nonisolated let output: AsyncStream<SSHShellOutput>
    private let outputContinuation: AsyncStream<SSHShellOutput>.Continuation
    private var writer: TTYStdinWriter?
    private var task: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var readyResolved = false
    private var readyFailure: Error?
    private(set) public var exit: SSHShellExit?
    private var columns: Int
    private var rows: Int
    private let onActivity: @Sendable () -> Void

    init(pty: SSHPTYRequest, onActivity: @escaping @Sendable () -> Void) {
        let (stream, continuation) = AsyncStream<SSHShellOutput>.makeStream()
        output = stream
        outputContinuation = continuation
        columns = pty.columns
        rows = pty.rows
        self.onActivity = onActivity
    }

    /// Keep shell line behaviour intact while ensuring CR isn't rewritten to NL (glas.sh
    /// `preferredPTYTerminalModes`).
    nonisolated static func preferredTerminalModes() -> SSHTerminalModes {
        SSHTerminalModes([.OCRNL: 0])
    }

    func start(client: SSHClient, options: SSHConnectionOptions) async throws {
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: options.terminalType,
            terminalCharacterWidth: columns,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: Self.preferredTerminalModes()
        )
        var mergedEnvironment = options.environment
        if mergedEnvironment["TERM"] == nil { mergedEnvironment["TERM"] = options.terminalType }
        if mergedEnvironment["COLORTERM"] == nil { mergedEnvironment["COLORTERM"] = "truecolor" }
        let environment = mergedEnvironment.map {
            SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: $0.key, value: $0.value)
        }

        task = Task { [weak self] in
            await self?.run(client: client, pty: pty, environment: environment)
        }
        try await awaitReady()
    }

    private func run(client: SSHClient, pty: SSHChannelRequestEvent.PseudoTerminalRequest, environment: [SSHChannelRequestEvent.EnvironmentRequest]) async {
        do {
            try await client.withPTY(pty, environment: environment) { [weak self] inbound, outbound in
                await self?.becameReady(outbound)
                for try await chunk in inbound {
                    let buffer: ByteBuffer
                    switch chunk {
                    case .stdout(let out): buffer = out
                    case .stderr(let err): buffer = err
                    }
                    let data = Data(buffer.readableBytesView)
                    let isStderr: Bool
                    if case .stderr = chunk { isStderr = true } else { isStderr = false }
                    await self?.deliver(isStderr ? .stderr(data) : .stdout(data))
                }
            }
            guard !Task.isCancelled else { finish(.cancelled); return }
            finish(.remoteClosed)
        } catch let channelError as ChannelError where SSHTransportError.isChannelClosedError(channelError) {
            finish(Task.isCancelled ? .cancelled : .remoteClosed)
        } catch is CancellationError {
            finish(.cancelled)
        } catch {
            if Task.isCancelled { finish(.cancelled); return }
            if SSHTransportError.isChannelClosedError(error) { finish(.remoteClosed); return }
            // The server would not open the channel (MaxSessions), or never answered: `start` says
            // so, rather than that the channel closed, so the opener can try another connection (W21).
            if SSHTransportError.isSessionChannelRefused(error) {
                failReady(SSHTransportError.sessionLimitReached)
            } else if SSHTransportError.isSessionOpenUnanswered(error) {
                failReady(error)
            }
            finish(.failed(String(describing: error)))
        }
    }

    private func becameReady(_ outbound: TTYStdinWriter) {
        writer = outbound
        guard !readyResolved else { return }
        readyResolved = true
        readyFailure = nil
        let continuation = readyContinuation
        readyContinuation = nil
        continuation?.resume()
    }

    private func deliver(_ chunk: SSHShellOutput) {
        onActivity()
        outputContinuation.yield(chunk)
    }

    private func finish(_ reason: SSHShellExit) {
        guard exit == nil else { return }
        exit = reason
        writer = nil
        failReady(reason == .cancelled ? CancellationError() : SSHTransportError.channelClosed)
        outputContinuation.finish()
    }

    private func awaitReady() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if writer != nil {
                    continuation.resume()
                } else if readyResolved {
                    continuation.resume(throwing: readyFailure ?? SSHTransportError.notConnected)
                } else {
                    readyContinuation = continuation
                }
            }
        } onCancel: {
            Task { [weak self] in await self?.failReady(CancellationError()) }
        }
    }

    private func failReady(_ error: Error) {
        guard !readyResolved else { return }
        readyResolved = true
        readyFailure = error
        let continuation = readyContinuation
        readyContinuation = nil
        continuation?.resume(throwing: error)
    }

    // MARK: Public operations

    public var isOpen: Bool { writer != nil && exit == nil }

    public func write(_ data: Data) async throws {
        guard let writer else { throw SSHTransportError.notConnected }
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        try await writer.write(buffer)
    }

    public func write(_ text: String) async throws {
        try await write(Data(text.utf8))
    }

    public func sendCommand(_ command: String) async throws {
        try await write(command + "\n")
    }

    public func resize(columns: Int, rows: Int) async throws {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        guard let writer else { return }
        try await writer.changeSize(cols: self.columns, rows: self.rows, pixelWidth: 0, pixelHeight: 0)
    }

    /// Cancels the PTY task and waits for it to unwind.
    public func close() async {
        let running = task
        task = nil
        running?.cancel()
        failReady(CancellationError())
        await running?.value
        finish(.cancelled)
    }
}
