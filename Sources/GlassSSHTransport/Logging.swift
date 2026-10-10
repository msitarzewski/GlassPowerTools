import os

extension Logger {
    /// The engine never logs host names, paths, or credential material at info level or above.
    nonisolated static let sshTransport = Logger(subsystem: "com.glasspowertools", category: "ssh-transport")
    /// Which connection each terminal opened, joined or waited for, and why (W21). The terminal's
    /// own SSH log (`sh.glas`, `ssh`), so one stream shows a recurrence end to end:
    /// `log stream --predicate 'subsystem == "sh.glas" AND category == "ssh"'`.
    nonisolated static let sshConnections = Logger(subsystem: "sh.glas", category: "ssh")
}
