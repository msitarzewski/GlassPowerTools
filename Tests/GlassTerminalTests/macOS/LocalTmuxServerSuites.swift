#if os(macOS)
import Foundation
import Testing

/// Every suite that swaps `MacLocalTmux.server` for a stand-in, one at a time (2026-10-12). Each
/// was serialized within itself, but nine of them ran beside each other and one's stand-in
/// answered another's test: three tests failed on a full run and passed alone. `.serialized` here
/// covers every suite nested in this one.
@Suite(.serialized)
enum LocalTmuxServerSuites {}

/// The fake server the suites share, by the name the tests use.
typealias MacLocalTmuxTests = LocalTmuxServerSuites.MacLocalTmuxTests

/// The tmux a stand-in names (rule 63). Stand-ins named this Mac's own, and a test window's pane
/// attached with it: `new-session -A` joined the owner's session of that name or made one, and his
/// app reopened six of them as tabs (2026-10-12). This one is no tmux: a pane attaching with it
/// shows nothing until its window closes, and anything else fails as a tmux that could not run.
nonisolated enum TmuxStandIn {
    static let path: String = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-tmux-stand-in")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("tmux")
        let script = "#!/bin/sh\nfor argument in \"$@\"; do [ \"$argument\" = -A ] && exec /bin/cat; done\nexit 1\n"
        try? Data(script.utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }()
}
#endif
