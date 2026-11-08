import Foundation
import Testing
@testable import GlassTerminal

/// D102 (2026-11-06): type-ahead offers what a machine's shell remembers, read from its history
/// file. The known answers come from outside this code: bytes written by zsh 5.9 (this Mac's
/// `/bin/zsh`) and bash 5.3 (the Linux test server), and the cases fish's own tests read
/// (`tests/history_sample_fish_2_0` and `history_sample_corrupt1` in fish-shell, with the
/// expectations in `src/history/history.rs`).
/// Off the main actor (the test target's default): the parser is `nonisolated`, and its large-file test held the
/// main thread for seconds at a stretch, which every test that draws a terminal waits on (sampled 2026-11-06: a
/// live tmux pane missed its 30 s while this ran).
@Suite("A shell's history file is read the way the shell reads it")
nonisolated struct ShellHistoryFileTests {

    // MARK: zsh

    /// `print -s` of six commands, then `fc -W`, in zsh 5.9 without EXTENDED_HISTORY.
    private static let zsh59Plain = hex("""
        6563686f20636166c3a920c3b120e683b7a5e683bcac0a666f72206920696e203120325c0a646f206563686f20
        24695c0a646f6e650a6563686f20747261696c696e675c200a5c3a20636f6c6f6e2066697273740a6c73202d6c
        610a6563686f20c483a30a
        """)
    /// The same six with EXTENDED_HISTORY set.
    private static let zsh59Extended = hex("""
        3a20313739343030333438333a303b6563686f20636166c3a920c3b120e683b7a5e683bcac0a3a203137393430
        30333438333a303b666f72206920696e203120325c0a646f206563686f2024695c0a646f6e650a3a2031373934
        3030333438333a303b6563686f20747261696c696e675c200a3a20313739343030333438333a303b3a20636f6c
        6f6e2066697273740a3a20313739343030333438333a303b6c73202d6c610a3a20313739343030333438333a30
        3b6563686f20c483a30a
        """)
    private static let zsh59Commands = [
        "echo café ñ 日本",
        "for i in 1 2\ndo echo $i\ndone",
        "echo trailing\\",
        ": colon first",
        "ls -la",
        "echo ă",
    ]

    @Test("zsh's own file: metafied bytes decoded, continued lines joined, its escapes undone")
    func zshPlain() {
        let entries = ShellHistoryFile.parse(Self.zsh59Plain, shell: .zsh)
        #expect(entries.map(\.command) == Self.zsh59Commands)
        #expect(entries.allSatisfy { $0.date == nil }, "a plain zsh file keeps no times")
    }

    @Test("zsh's EXTENDED_HISTORY: the start time read, the command after the semicolon")
    func zshExtended() {
        let entries = ShellHistoryFile.parse(Self.zsh59Extended, shell: .zsh)
        #expect(entries.map(\.command) == Self.zsh59Commands)
        #expect(entries.allSatisfy { $0.date == Date(timeIntervalSince1970: 1_794_003_483) })
    }

    @Test("zsh: the metafied bytes are the hard part, so they are checked byte for byte")
    func zshMetafication() throws {
        // 日 is E6 97 A5 and zsh writes E6 83 B7 A5; ă is C4 83 and zsh writes C4 83 A3.
        let entries = ShellHistoryFile.parse(Data([0xE6, 0x83, 0xB7, 0xA5, 0x0A, 0xC4, 0x83, 0xA3, 0x0A]), shell: .zsh)
        #expect(entries.map(\.command) == ["日", "ă"])
        let first = try #require(entries.first)
        #expect(Array(first.command.utf8) == [0xE6, 0x97, 0xA5])
    }

    @Test("zsh: a broken entry, an empty one and a missing last newline cost nothing else")
    func zshDamage() {
        var data = Data("ls\n".utf8)
        data.append(contentsOf: [0xFF, 0x41, 0x0A])                 // not UTF-8
        data.append(contentsOf: [0x61, 0x83, 0x0A])                 // Meta with nothing after it
        data.append(contentsOf: Data("   \n: 1700000000:0;\n: 1700000000:0;  \n".utf8))
        data.append(contentsOf: Data(": 1700000001:3;git status\npwd".utf8))
        let entries = ShellHistoryFile.parse(data, shell: .zsh)
        #expect(entries.map(\.command) == ["ls", "git status", "pwd"])
        #expect(entries.map(\.date) == [nil, Date(timeIntervalSince1970: 1_700_000_001), nil])
    }

    // MARK: bash

    /// bash 5.3 with `HISTTIMEFORMAT` and `lithist`, `history -s` of five commands, `history -w`.
    /// bash itself, reading this back, loses `#123 not a stamp`: readline takes any `#` and a digit
    /// for a timestamp. The parser keeps it, as the command it was.
    private static let bash53Stamped = hex("""
        23313739333634353630310a6563686f20636166c3a920e697a5e69cac0a23313739333634353630310a666f72
        206920696e203120320a646f206563686f2024690a646f6e650a23313739333634353630310a23313233206e6f
        742061207374616d700a23313739333634353630310a23206120636f6d6d656e740a2331373933363435363031
        0a6c73202d6c610a
        """)

    @Test("bash with timestamps: each command dated, a multi-line one whole, as bash 5.3 reads it")
    func bashStamped() {
        let entries = ShellHistoryFile.parse(Self.bash53Stamped, shell: .bash)
        #expect(entries.map(\.command) == [
            "echo café 日本",
            "for i in 1 2\ndo echo $i\ndone",
            "#123 not a stamp",
            "# a comment",
            "ls -la",
        ])
        #expect(entries.allSatisfy { $0.date == Date(timeIntervalSince1970: 1_793_645_601) })
    }

    @Test("bash without timestamps: one command a line, and a timestamp line dates only the next")
    func bashPlain() {
        let file = "echo foo\nfor i in 1 2\ndo echo $i\ndone\n\n# a comment\n#1700000000\nls\n"
        let entries = ShellHistoryFile.parse(Data(file.utf8), shell: .bash)
        // As bash 5.3 reads the same file without HISTTIMEFORMAT: the loop comes back in pieces.
        #expect(entries.map(\.command) == ["echo foo", "for i in 1 2", "do echo $i", "done", "# a comment", "ls"])
        #expect(entries.map(\.date) == [nil, nil, nil, nil, nil, Date(timeIntervalSince1970: 1_700_000_000)])
    }

    @Test("bash: Windows line ends, a broken entry and a whitespace-only one cost nothing else")
    func bashDamage() {
        var data = Data("#1700000000\r\nls\r\n#1700000001\n".utf8)
        data.append(contentsOf: [0xC3, 0x28, 0x0A])                 // not UTF-8
        data.append(contentsOf: Data("#1700000002\n   \n#1700000003\npwd".utf8))
        let entries = ShellHistoryFile.parse(data, shell: .bash)
        #expect(entries.map(\.command) == ["ls", "pwd"])
        #expect(entries.map(\.date) == [Date(timeIntervalSince1970: 1_700_000_000), Date(timeIntervalSince1970: 1_700_000_003)])
    }

    // MARK: fish

    @Test("fish: escapes undone, `when` read, a last item with no newline skipped, as fish's own test")
    func fishItems() {
        // The constructs of fish's `history_sample_fish_2_0`: a deeper indent, padded `when`,
        // `added_when`, `\n` for a newline, `\\` then `\n`, and an unfinished last line.
        let file = """
            - cmd: echo one
               when:       1700000100
               added_when: 1700000000
            - cmd: function greet\\necho hi\\nend
               when: 1700000200
            - cmd: echo with\\\\\\nbackslash
               when: 1700000300
            - cmd: never finished
            """
        let entries = ShellHistoryFile.parse(Data(file.utf8), shell: .fish)
        #expect(entries.map(\.command) == ["echo one", "function greet\necho hi\nend", "echo with\\\nbackslash"])
        #expect(entries.map(\.date) == [1_700_000_100, 1_700_000_200, 1_700_000_300].map { Date(timeIntervalSince1970: $0) })
    }

    @Test("fish: an item whose last line is unfinished keeps its command, as in fish's corrupt sample")
    func fishUnfinishedInterior() {
        let entries = ShellHistoryFile.parse(Data("- cmd: first\n- cmd: second\n   when: 1700000000".utf8), shell: .fish)
        #expect(entries.map(\.command) == ["first", "second"])
        #expect(entries.map(\.date) == [nil, nil], "the unfinished `when` line is not read")
    }

    @Test("fish: paths, YAML markers and damaged lines are passed over")
    func fishOtherLines() {
        let file = """
            - cmd: cd ~/src
              when: 1700000000
              paths:
                - ~/src
            ---
            garbage line
            - cmd: ls
              when: 1700000001

            """
        let entries = ShellHistoryFile.parse(Data(file.utf8), shell: .fish)
        #expect(entries.map(\.command) == ["cd ~/src", "ls"])
        #expect(entries.map(\.date) == [Date(timeIntervalSince1970: 1_700_000_000), Date(timeIntervalSince1970: 1_700_000_001)])
    }

    @Test("fish: a broken entry and empty ones cost nothing else; an unknown escape stays as written")
    func fishDamage() {
        var data = Data("- cmd: ok\n- cmd: ".utf8)
        data.append(contentsOf: [0xC3, 0x28, 0x0A])                 // not UTF-8
        data.append(contentsOf: Data("- cmd:\n- cmd:    \n- cmd: echo \\q\n".utf8))
        let entries = ShellHistoryFile.parse(data, shell: .fish)
        #expect(entries.map(\.command) == ["ok", "echo \\q"])
    }

    // MARK: Where, and which

    @Test("each shell's history is looked for where it keeps it")
    func paths() {
        #expect(ShellHistoryFile.relativePaths(for: .zsh).first == ".zsh_history")
        #expect(ShellHistoryFile.relativePaths(for: .zsh).contains(".histfile"))
        #expect(ShellHistoryFile.relativePaths(for: .bash) == [".bash_history"])
        #expect(ShellHistoryFile.relativePaths(for: .fish) == [".local/share/fish/fish_history"])
        #expect(TerminalShellKind.allCases.allSatisfy { kind in
            ShellHistoryFile.relativePaths(for: kind).allSatisfy { !$0.hasPrefix("/") && !$0.hasPrefix("~") }
        }, "relative to the home folder")
    }

    @Test("each command once, at its last use, newest first, at most the limit")
    func distinctRecent() {
        func entry(_ command: String, _ seconds: TimeInterval?) -> ShellHistoryEntry {
            ShellHistoryEntry(command: command, date: seconds.map { Date(timeIntervalSince1970: $0) })
        }
        let entries = [entry("a", 1), entry("b", 2), entry("a", 3), entry("c", nil), entry("b", 5), entry("b ", 6)]
        #expect(ShellHistoryFile.distinctRecent(entries, limit: 10)
                == [entry("b ", 6), entry("b", 5), entry("c", nil), entry("a", 3)])
        #expect(ShellHistoryFile.distinctRecent(entries, limit: 2) == [entry("b ", 6), entry("b", 5)])
        #expect(ShellHistoryFile.distinctRecent(entries, limit: 0).isEmpty)
        #expect(ShellHistoryFile.distinctRecent([], limit: 5).isEmpty)
    }

    // MARK: Size

    /// An optimised build reads each of these 13–15 MB files in 23–28 ms (2026-11-06, this Mac).
    /// A debug build under test takes 0.3–0.5 s on a quiet machine and three times that with other
    /// builds running, so a fixed time measures the machine, not the reader (it failed that way
    /// once). The reader is measured instead against the least any reader must do with the same
    /// bytes at the same moment, finding each line and decoding it, best of three each, so a
    /// quadratic step or heavy work per entry fails it and a busy machine does not.
    ///
    /// Both are timed as this thread's own running time (`threadTime`), not the clock's: with the whole suite
    /// running beside it on the iPhone simulator, the clock gave zsh 28 times the splitting (0.69 s against
    /// 0.024 s, and 0.61 s against 0.022 s), and under 27 when run alone (2026-11-06). The reader makes far more
    /// small allocations than the splitting does, so other tests' work in between slowed it more on the clock. The
    /// splitting is also timed over `splittingPasses` passes, so both measurements last about as long.
    @Test("about 10 MB of history, in each shell's format, costs little more than splitting it into lines")
    func largeFiles() {
        let count = 160_000
        var zsh = Data(), bash = Data(), fish = Data()
        zsh.reserveCapacity(14_000_000)
        for index in 0 ..< count {
            let command = "git commit -m \"change number \(index) to the café's menu\" && make test"
            zsh.append(contentsOf: Data(": \(1_700_000_000 + index):0;\(command)\n".utf8))
            bash.append(contentsOf: Data("#\(1_700_000_000 + index)\n\(command)\n".utf8))
            fish.append(contentsOf: Data("- cmd: \(command)\n  when: \(1_700_000_000 + index)\n".utf8))
        }
        #expect(zsh.count > 10_000_000)
        for (data, shell) in [(zsh, TerminalShellKind.zsh), (bash, .bash), (fish, .fish)] {
            var entries: [ShellHistoryEntry] = []
            var lines = 0
            var reading = Duration.seconds(1_000), splitting = Duration.seconds(1_000)
            for _ in 0 ..< 3 {
                reading = min(reading, threadTime { entries = ShellHistoryFile.parse(data, shell: shell) })
                let passes = threadTime { for _ in 0 ..< Self.splittingPasses { lines = linesDecoded(data) } }
                splitting = min(splitting, passes / Self.splittingPasses)
            }
            #expect(entries.count == count, "\(shell)")
            #expect(lines >= count, "\(shell)")
            #expect(reading < splitting * Self.readingAllowance,
                    "\(shell): read in \(reading), split into lines in \(splitting)")
        }
    }

    /// How many times the cost of splitting and decoding lines a reader may take: one and a half
    /// times the most measured in a debug build (bash 7, fish 13–14, zsh 17–18, steady within 5% at
    /// load averages of 60 to 110, 2026-11-06). The splitting is the standard library's optimised
    /// code; the reader here is not. A regular expression compiled for each entry measures 37.
    private static let readingAllowance = 27
    /// Splitting passes per measurement: about the reading's length (zsh's ratio is 17–18).
    private static let splittingPasses = 16
}

/// The time this thread spent running `work`: time the system gave other threads meanwhile isn't counted.
nonisolated private func threadTime(_ work: () -> Void) -> Duration {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return .nanoseconds(Int64(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start))
}

/// The least a history reader does: find each line and decode it as UTF-8. Counts the lines that decode.
nonisolated private func linesDecoded(_ data: Data) -> Int {
    data.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        guard let base = bytes.baseAddress else { return 0 }
        var decoded = 0
        var start = 0
        while start < bytes.count {
            let end = memchr(base + start, 0x0A, bytes.count - start)
                .map { UnsafeRawPointer(base).distance(to: UnsafeRawPointer($0)) } ?? bytes.count
            if String(validating: UnsafeBufferPointer(rebasing: bytes[start ..< end]), as: UTF8.self) != nil { decoded += 1 }
            start = end + 1
        }
        return decoded
    }
}

/// Bytes from a hex dump, ignoring whitespace.
nonisolated private func hex(_ text: String) -> Data {
    var data = Data()
    var high: UInt8?
    for character in text where character.isHexDigit {
        let value = UInt8(character.hexDigitValue!)
        if let first = high {
            data.append(first << 4 | value)
            high = nil
        } else {
            high = value
        }
    }
    return data
}
