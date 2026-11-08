import Foundation
import Testing
@testable import GlassTerminal

/// Type-ahead's ranking (D102, 2026-11-06): which command to offer for a line, among what each source offers.
@Suite("Type-ahead: choosing what to offer")
struct TypeAheadEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ command: String, count: Int = 1, daysAgo: Double = 0, folders: [String: Int] = [:],
                        after: [String: Int] = [:], status: Int? = nil, imported: Bool = false) -> TerminalCommandRecord {
        TerminalCommandRecord(command: command, count: count, lastUsed: now.addingTimeInterval(-daysAgo * 86_400),
                              folders: folders, after: after, lastStatus: status, imported: imported)
    }

    private func best(_ typed: String, _ records: [TerminalCommandRecord],
                      folder: String? = nil, previous: String? = nil) -> String? {
        let context = TerminalTypeAheadContext(folder: folder, previousCommand: previous, now: now)
        let candidates = TerminalTypeAheadEngine.historyCandidates(typed: typed, records: records, context: context)
        return TerminalTypeAheadEngine.choose(typed: typed, candidates: candidates).best?.command
    }

    @Test("only commands that start with what's typed, and never what's typed itself")
    func prefix() {
        let records = [record("git status"), record("git stash"), record("ls"), record("git")]
        let context = TerminalTypeAheadContext(now: now)
        let found = TerminalTypeAheadEngine.historyCandidates(typed: "git", records: records, context: context).map(\.command)
        #expect(Set(found) == ["git status", "git stash"])
    }

    @Test("often and lately win; the folder it ran in and the command before it count")
    func ranking() {
        let often = record("make test", count: 20, daysAgo: 30)
        let lately = record("make build", count: 1, daysAgo: 0)
        #expect(best("make", [often, lately]) == "make test", "twenty runs a month ago over one today")
        #expect(best("make", [record("make test", count: 2, daysAgo: 0), record("make build", count: 2, daysAgo: 10)]) == "make test")

        let here = record("npm run dev", count: 1, daysAgo: 1, folders: ["/srv/shop": 1])
        let elsewhere = record("npm run build", count: 2, daysAgo: 1, folders: ["/srv/blog": 2])
        #expect(best("npm run", [here, elsewhere], folder: "/srv/shop") == "npm run dev", "the folder it ran in")
        #expect(best("npm run", [here, elsewhere], folder: "/srv/blog") == "npm run build")

        let next = record("git push", count: 1, daysAgo: 2, after: ["git commit -m wip": 3])
        let other = record("git pull", count: 2, daysAgo: 2)
        #expect(best("git p", [next, other], previous: "git commit -m wip") == "git push", "what usually comes next")
        #expect(best("git p", [next, other], previous: nil) == "git pull")
    }

    @Test("a command that last failed, or was only read from the machine's own history, counts for less")
    func penalties() {
        let failed = record("cargo test", count: 3, daysAgo: 0, status: 101)
        let passed = record("cargo build", count: 2, daysAgo: 0, status: 0)
        #expect(best("cargo", [failed, passed]) == "cargo build")
        let imported = record("docker ps -a", count: 3, daysAgo: 0, imported: true)
        let seen = record("docker ps", count: 2, daysAgo: 0)
        #expect(best("docker", [imported, seen]) == "docker ps")
    }

    @Test("the best for the grey text needs something typed; the chips also serve an empty line, each command once")
    func choosing() {
        let candidates = [
            TerminalTypeAheadCandidate(command: "ls -la", score: 3, source: .history),
            TerminalTypeAheadCandidate(command: "ls -la", score: 1, source: .snippet),
            TerminalTypeAheadCandidate(command: "cd ..", score: 2, source: .history),
            TerminalTypeAheadCandidate(command: "pwd", score: 1, source: .history),
            TerminalTypeAheadCandidate(command: "top", score: 0.5, source: .history),
        ]
        let empty = TerminalTypeAheadEngine.choose(typed: "", candidates: candidates)
        #expect(empty.best == nil)
        #expect(empty.choices.map(\.command) == ["ls -la", "cd ..", "pwd"])
        let typed = TerminalTypeAheadEngine.choose(typed: "l", candidates: candidates)
        #expect(typed.best?.command == "ls -la" && typed.best?.source == .history)
        #expect(typed.choices.map(\.command) == ["ls -la"])
    }

    @Test("snippets by use; a snippet of several lines is never offered for one")
    func snippets() {
        let snippets = [(command: "kubectl get pods -A", useCount: 5, lastUsed: Optional(now)),
                        (command: "kubectl logs -f", useCount: 0, lastUsed: nil),
                        (command: "kubectl apply -f a.yaml\nkubectl apply -f b.yaml", useCount: 9, lastUsed: Optional(now))]
        let found = TerminalTypeAheadEngine.snippetCandidates(typed: "kubectl", snippets: snippets,
                                                              context: TerminalTypeAheadContext(now: now))
        #expect(found.map(\.command) == ["kubectl get pods -A", "kubectl logs -f"])
        #expect(found[0].score > found[1].score)
    }

    @Test("the library: user@address for ssh (with -p off 22), user@address: for scp, the address for ping; lately used first")
    func library() {
        let machines = [
            TerminalTypeAheadLibrary.Machine(address: "alpha.example.com", user: "ann", port: 22,
                                             lastConnected: now.addingTimeInterval(-30 * 86_400)),
            TerminalTypeAheadLibrary.Machine(address: "192.0.2.10", user: "deploy", port: 2222, lastConnected: now),
        ]
        func words(_ line: String) -> [String] { TerminalTypeAheadLibrary.words(line: line, machines: machines, now: now).map(\.word) }
        #expect(words("ssh ") == ["deploy@192.0.2.10 -p 2222", "ann@alpha.example.com"])
        #expect(words("sudo ssh a") == ["deploy@192.0.2.10 -p 2222", "ann@alpha.example.com"], "after sudo; the engine filters by prefix")
        #expect(words("scp build.tar ") == ["deploy@192.0.2.10:", "ann@alpha.example.com:"])
        #expect(words("ping ") == ["192.0.2.10", "alpha.example.com"])
        #expect(words("ssh -i ").isEmpty, "the key file goes there, not a machine")
        #expect(words("ssh -").isEmpty && words("scp ./").isEmpty && words("ls ").isEmpty)
        let candidates = TerminalTypeAheadEngine.wordCandidates(
            typed: "ssh an", words: TerminalTypeAheadLibrary.words(line: "ssh an", machines: machines, now: now), source: .library)
        #expect(candidates.map(\.command) == ["ssh ann@alpha.example.com"])
    }

    @Test("words on screen: from two characters typed, nearer the prompt first, without trailing punctuation")
    func screen() {
        let screen = [
            "CONTAINER ID   IMAGE     NAMES",
            "3f2a9c1b7d4e   nginx     web",
            "commit 3f9e8d7c6b5a49382716 (HEAD -> main)",
            "See ./scripts/deploy.sh.",
        ]
        func words(_ line: String) -> [String] { TerminalTypeAheadScreen.words(line: line, screen: screen).map(\.word) }
        #expect(words("docker logs 3f") == ["3f9e8d7c6b5a49382716", "3f2a9c1b7d4e"], "the later line first")
        #expect(words("bash ./sc") == ["./scripts/deploy.sh"], "the sentence's full stop isn't the file's")
        #expect(words("docker logs 3").isEmpty, "one character offers nothing")
        #expect(words("ls -").isEmpty)
    }

    @Test("the model's answer: its first line, unquoted, kept only when it continues what's typed and holds no secret")
    func assistantAnswer() {
        #expect(TerminalTypeAheadAssistant.cleaned("```\ngit push origin main\n```", typed: "git p") == "git push origin main")
        #expect(TerminalTypeAheadAssistant.cleaned("`npm test`", typed: "npm") == "npm test")
        #expect(TerminalTypeAheadAssistant.cleaned("$ make build", typed: "make") == "make build")
        #expect(TerminalTypeAheadAssistant.cleaned("ls -la", typed: "git") == nil, "it doesn't continue the line")
        #expect(TerminalTypeAheadAssistant.cleaned("git", typed: "git") == nil)
    }

    @Test("word sources complete the word being typed; quotes and escaped spaces stay in the word")
    func words() {
        #expect(TerminalTypeAheadEngine.currentWord(of: "git checkout ma") == ("git checkout ", "ma"))
        #expect(TerminalTypeAheadEngine.currentWord(of: "git checkout ") == ("git checkout ", ""))
        #expect(TerminalTypeAheadEngine.currentWord(of: "cd \"My Fo") == ("cd ", "\"My Fo"))
        #expect(TerminalTypeAheadEngine.currentWord(of: "cd My\\ Fo") == ("cd ", "My\\ Fo"))
        let found = TerminalTypeAheadEngine.wordCandidates(typed: "git checkout ma",
                                                           words: [(word: "main", score: 1), (word: "master", score: 0.5),
                                                                   (word: "feature", score: 2), (word: "ma", score: 3)],
                                                           source: .folder)
        #expect(found.map(\.command) == ["git checkout main", "git checkout master"])
    }
}
