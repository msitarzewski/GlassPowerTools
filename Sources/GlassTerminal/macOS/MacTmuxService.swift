//
//  MacTmuxService.swift
//  Glass Power Tools — GlassTerminal
//
//  This Mac's tmux server, started by launchd rather than by the app (2026-10-12). The owner force
//  quit a scratch app an agent had left running, and every local terminal ended with it: the app
//  had been launched from inside one of the tmux sessions. macOS counts everything an app starts,
//  and everything those start, in the app's resource coalition — the tmux server (daemonized, so
//  its parent and process group are its own regardless) and every pane. Once the app that started
//  the server has quit, as an update quits it, each of them answers for itself, and the Dock's
//  Force Quit of an app launched from a pane ends the whole coalition: on this Mac, a probe app
//  force quit that way took its server and two bystander panes with it in the same second.
//
//  A server launchd runs is a coalition of its own, alive while it runs, and an app started from a
//  pane is the server's to answer for: the same Force Quit, the same probe, under such a server,
//  ended the probe alone.
//
//  So when no server runs, the app asks launchd to run one, from a job file in the app's Application
//  Support folder, not LaunchAgents — it is no login item, and starts only when a local terminal
//  needs it. The job runs the app's own executable as the host (`MacTmuxHost`), which starts tmux:
//  run by launchd directly, tmux answered for its panes, and macOS asked for the Desktop folder in
//  tmux's name rather than the app's. The job has the environment a pane's first claim used to give
//  the server, so its shells start the same. A server already running is left alone, whoever
//  started it; one that will not start leaves the claim to start it, as before. Settings ▸ Terminal
//  can end the server, and with it the host (`stopDefaultServer`).
//

#if os(macOS)
import Foundation
import os

nonisolated enum MacTmuxService {
    private static let logger = Logger(subsystem: "sh.glas", category: "local-tmux")
    static let label = "com.glasspowertools.tmux"
    /// How long launchd's server has to answer.
    static let startTimeout: Duration = .seconds(3)

    /// Variables launchd gives every job in the person's session itself, current for this login:
    /// written into the job, a stale agent socket or temporary folder would outlive the login.
    static let fromLaunchd: Set<String> = ["SSH_AUTH_SOCK", "TMPDIR", "__CF_USER_TEXT_ENCODING", "XPC_FLAGS"]

    /// The job's file.
    static func jobURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Glass Power Tools", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    /// The job: the host, which runs tmux, at a terminal's priority, with the pane's environment.
    /// `serverArguments` only for a test's private server.
    static func job(label: String = label, host: String, tmux: String, environment: [String: String],
                    serverArguments: [String] = []) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [host, MacTmuxHost.flag, tmux] + serverArguments,
            "EnvironmentVariables": environment.filter { !fromLaunchd.contains($0.key) },
            "RunAtLoad": true,
            "KeepAlive": false,
            // A background job is throttled; this one runs what people type.
            "ProcessType": "Interactive",
            // The panes are the server's; launchd leaves them be if it ever stops the job.
            "AbandonProcessGroup": true,
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    /// Whether a tmux server answers, without starting one (`-N`).
    static func serverRunning(tmux: String, serverArguments: [String] = [],
                              run: (_ executable: String, _ arguments: [String]) -> String? = { MacLocalTmux.run($0, $1) }) -> Bool {
        run(tmux, serverArguments + ["-N", "list-sessions"]) != nil
    }

    enum Outcome: Equatable { case alreadyRunning, started, couldNotStart }

    /// A tmux server runs, under launchd if this call started it.
    @discardableResult
    static func ensureServer(host: String, tmux: String, environment: [String: String], label: String = label,
                             serverArguments: [String] = [], jobURL: URL? = jobURL(),
                             run: (_ executable: String, _ arguments: [String]) -> String? = { MacLocalTmux.run($0, $1) },
                             wait: (Duration) -> Void = { Thread.sleep(forTimeInterval: Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18) })
        -> Outcome {
        if serverRunning(tmux: tmux, serverArguments: serverArguments, run: run) { return .alreadyRunning }
        guard let jobURL else { return .couldNotStart }
        do {
            try FileManager.default.createDirectory(at: jobURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: job(label: label, host: host, tmux: tmux, environment: environment,
                                      serverArguments: serverArguments),
                format: .xml, options: 0)
            try data.write(to: jobURL, options: .atomic)
        } catch {
            logger.error("The tmux job could not be written: \(error.localizedDescription, privacy: .public)")
            return .couldNotStart
        }
        let domain = "gui/\(getuid())"
        // A job left from a server that ended is loaded and stopped: out first, so the new file and
        // its environment are the ones that run.
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        guard run("/bin/launchctl", ["bootstrap", domain, jobURL.path]) != nil else {
            logger.error("launchd would not take the tmux job; the terminal starts tmux itself")
            return .couldNotStart
        }
        var waited: Duration = .zero
        while waited < startTimeout {
            if serverRunning(tmux: tmux, serverArguments: serverArguments, run: run) {
                logger.notice("This Mac's tmux server started under launchd")
                return .started
            }
            wait(.milliseconds(50))
            waited += .milliseconds(50)
        }
        logger.error("launchd's tmux server did not answer in time; the terminal starts tmux itself")
        return .couldNotStart
    }

    /// A server confirmed this recently is taken as still running: a pane's configuration is
    /// resolved on every redraw, and asking tmux each time would cost a process each.
    static let confirmationLasts: Duration = .seconds(10)
    private static let confirmed = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)

    /// `ensureServer` for the default server, at most once in `confirmationLasts` while it runs:
    /// before a claim makes a session and before a pane attaches, either of which would otherwise
    /// start the server in the app's group.
    static func ensureDefaultServer(tmux: String, environment: [String: String]) {
        // This Mac's tmux and no other: a test's shim names a private server, and the job and its
        // label are the owner's — booting them out would end every session.
        guard tmux == MacLocalTmux.executablePath(), let host = appExecutable() else { return }
        let now = ContinuousClock.now
        if let last = confirmed.withLock({ $0 }), now - last < confirmationLasts { return }
        if ensureServer(host: host, tmux: tmux, environment: environment) != .couldNotStart {
            confirmed.withLock { $0 = now }
        }
    }

    /// The app's executable, to run as the host; nil in anything but the app (a test runner).
    static func appExecutable(bundle: Bundle = .main) -> String? {
        bundle.bundleURL.pathExtension == "app" ? bundle.executablePath : nil
    }

    /// Ends this Mac's tmux server — every local terminal in it — and with it the host, for
    /// Settings ▸ Terminal. The job is taken out too, so nothing is left loaded.
    static func stopDefaultServer(tmux: String) {
        guard tmux == MacLocalTmux.executablePath() else { return }
        stopServer(tmux: tmux)
        confirmed.withLock { $0 = nil }
    }

    static func stopServer(tmux: String, label: String = label, serverArguments: [String] = [],
                           run: (_ executable: String, _ arguments: [String]) -> String? = { MacLocalTmux.run($0, $1) }) {
        _ = run(tmux, serverArguments + ["kill-server"])
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        logger.notice("This Mac's tmux server was ended from Settings")
    }

    /// Takes a test's job away again.
    static func remove(label: String, jobURL: URL, run: (_ executable: String, _ arguments: [String]) -> String? = { MacLocalTmux.run($0, $1) }) {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: jobURL)
    }
}
#endif
