import os

extension Logger {
    /// The engine never logs host names, paths, or credential material at info level or above.
    nonisolated static let sshTransport = Logger(subsystem: "com.glasspowertools", category: "ssh-transport")
}
