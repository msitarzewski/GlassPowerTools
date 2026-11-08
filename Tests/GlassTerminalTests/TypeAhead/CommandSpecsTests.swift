//
//  CommandSpecsTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Type-ahead (D102, 2026-11-06), source 6, "Common tools": the data loads, holds together, and says what the word
//  being typed can be for representative lines across tools; the line is split as a shell would split it.
//

import Foundation
import Testing
@testable import GlassTerminal

@Suite("Common tools' data: what the word being typed can be")
struct CommandSpecsTests {
    /// A typed line and what the reader should say about its last word.
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let line: String
        /// The first candidates, in order; `nil` to leave them unchecked.
        var first: [String]? = nil
        /// Words that must be among the candidates.
        var including: [String] = []
        /// Words that must not be among them.
        var excluding: [String] = []
        /// The expected kind; `.some(nil)` for "no kind", `nil` to leave it unchecked.
        var kind: CommandArgumentKind?? = nil
        /// The expected word prefix; `nil` to leave it unchecked.
        var prefix: String? = nil
        var testDescription: String { "“\(line)”" }
    }

    /// git's subcommands that start with “ch”, in the data's order (most common first).
    nonisolated static let gitCh = ["checkout", "cherry-pick", "check-ignore", "cherry"]

    nonisolated static let cases: [Case] = [
        // Subcommands, most common first.
        Case(line: "git ch", first: gitCh, kind: .some(nil), prefix: "ch"),
        Case(line: "git ", first: ["status", "add", "commit"], kind: .some(nil), prefix: ""),
        Case(line: "docker compose u", first: ["up", "unpause"]),
        Case(line: "kubectl get po", first: ["pods", "poddisruptionbudgets", "podtemplates"], kind: .value),
        Case(line: "sudo systemctl rest", first: ["restart"]),
        Case(line: "apt-get ins", first: ["install"]),
        Case(line: "/usr/bin/git ch", first: gitCh),
        Case(line: "git remote add ", kind: .value),
        Case(line: "git remote ", including: ["add", "remove", "set-url"], kind: .some(nil)),
        // Arguments by kind.
        Case(line: "git checkout ", kind: .branch, prefix: ""),
        Case(line: "git checkout -b ", kind: .value),
        Case(line: "git checkout -- ", kind: .file),
        Case(line: "git push ", kind: .remote),
        Case(line: "git push origin ", kind: .branch),
        Case(line: "git push origin main ", kind: .branch),
        Case(line: "git stash list ", kind: CommandArgumentKind.none),
        Case(line: "npm run ", kind: .script),
        Case(line: "make ", kind: .target),
        Case(line: "make -j8 ", kind: .target),
        Case(line: "make -j ", kind: .value),
        Case(line: "make -C ", kind: .folder),
        Case(line: "cd ", kind: .folder),
        Case(line: "ssh ", kind: .host),
        Case(line: "ssh -i ", kind: .file),
        Case(line: "docker exec -it ", kind: .container),
        Case(line: "docker run --rm ", kind: .image),
        Case(line: "systemctl restart ", kind: .service),
        Case(line: "journalctl -u ", kind: .service),
        Case(line: "kill -9 ", kind: .process),
        Case(line: "brew install ", kind: .package),
        Case(line: "tar -xzf ", kind: .file),
        // Bundled one-letter options: the last letter's value is the next word.
        Case(line: "git commit -am ", kind: .value),
        Case(line: "ssh -vp ", kind: .value),
        Case(line: "ssh -vp 2222 ", kind: .host),
        Case(line: "ssh -vp2222 ", kind: .host),
        Case(line: "ls -l ", kind: .file),
        Case(line: "curl -sL ", kind: .url),
        Case(line: "git commit -m \"fix the bu", kind: .value, prefix: "fix the bu"),
        Case(line: "yarn ", including: ["install", "add"], kind: .script),
        Case(line: "pnpm --filter web run ", kind: .script),
        Case(line: "npm run build -- ", kind: .value),
        Case(line: "npm run build ", kind: .value),
        Case(line: "cargo run --release -- ", kind: .value),
        Case(line: "apt install -y ", kind: .package),
        Case(line: "systemctl --user restart ", kind: .service),
        Case(line: "docker compose -f ", kind: .file),
        Case(line: "terraform plan -var-file ", kind: .file),
        Case(line: "helm upgrade -i ", kind: .value),
        Case(line: "chmod ", including: ["+x", "755"], kind: .value),
        Case(line: "chmod 755 ", kind: .file),
        Case(line: "launchctl kickstart -k ", kind: .service),
        Case(line: "tmux attach -t ", kind: .value),
        Case(line: "dig example.com M", first: ["MX"], kind: .value),
        // Options.
        Case(line: "ls -l", including: ["-l"], kind: .some(nil), prefix: "-l"),
        Case(line: "tar -x", including: ["-x"]),
        Case(line: "git status --unt", first: ["--untracked-files"]),
        Case(line: "ls | grep -", including: ["-i", "-v", "-r", "-n"], excluding: ["-1", "-S"]),
        Case(line: "ls -l -", excluding: ["-l"]),
        Case(line: "docker run -e A=1 -", including: ["-e", "-d"]),
        Case(line: "git log --pretty=one", first: ["oneline"], kind: .value, prefix: "one"),
        Case(line: "kubectl get pods -o ", including: ["json", "yaml", "wide"], kind: .value),
        Case(line: "curl -X P", first: ["POST", "PUT", "PATCH"], kind: .value),
        Case(line: "dig +sh", first: ["+short"]),
        Case(line: "less +", first: ["+F", "+G"]),
        Case(line: "go test -r", first: ["-race", "-run"]),
        Case(line: "pip install --up", first: ["--upgrade", "--upgrade-strategy"]),
        Case(line: "swift build -c ", first: ["debug", "release"], kind: .value),
        Case(line: "xcodebuild -scheme App te", first: ["test", "test-without-building"]),
        Case(line: "xcodebuild -scheme App test -dest", first: ["-destination", "-destination-timeout"]),
        // Persistent options hold below the subcommand that declares them, before or after.
        Case(line: "kubectl -n kube-system get po", first: ["pods", "poddisruptionbudgets", "podtemplates"]),
        Case(line: "kubectl get pods -n ", kind: .value),
        Case(line: "kubectl get pods --cont", first: ["--context"]),
        // Words that run another command.
        Case(line: "sudo ", kind: .command),
        Case(line: "sudo systemc", first: ["systemctl"], kind: .command),
        Case(line: "sudo -u admin systemctl st", including: ["start", "status", "stop"]),
        Case(line: "sudo -u adm", kind: .user, prefix: "adm"),
        Case(line: "sudo -u admin ", kind: .command),
        Case(line: "time make ", kind: .target),
        Case(line: "env FOO=1 BAR=2 git ch", first: gitCh),
        Case(line: "xargs -n1 grep -", including: ["-i", "-v"]),
        Case(line: "ssh alpha ls -", including: ["-l", "-a", "-1", "-h"]),
        Case(line: "find . -name '*.log' -exec grep -", including: ["-i", "-v"]),
        Case(line: "kubectl exec -it web -- ls -", including: ["-l", "-a"]),
        Case(line: "watch -n 2 kubectl get po", first: ["pods", "poddisruptionbudgets", "podtemplates"]),
        // Only the last command counts.
        Case(line: "cd /srv && git ch", first: gitCh),
        Case(line: "make; npm run ", kind: .script),
        Case(line: "true || git ch", first: gitCh),
        Case(line: "FOO=1 make ", kind: .target),
        Case(line: "if true; then git ch", first: gitCh),
        Case(line: "echo $(git ch", first: gitCh),
        Case(line: "ls > ", kind: .file),
        Case(line: "ls 2>/dev/null -", including: ["-l"]),
    ]

    @Test("representative lines", arguments: cases)
    func completes(_ c: Case) throws {
        let completion = try #require(CommandSpecs.completion(forLine: c.line))
        let words = completion.candidates.map(\.word)
        if let first = c.first {
            #expect(Array(words.prefix(first.count)) == first, "candidates: \(words)")
        }
        for word in c.including { #expect(words.contains(word), "\(word) missing from \(words)") }
        for word in c.excluding { #expect(!words.contains(word), "\(word) shouldn't be in \(words)") }
        if let kind = c.kind { #expect(completion.argumentKind == kind) }
        if let prefix = c.prefix { #expect(completion.wordPrefix == prefix) }
        for candidate in completion.candidates {
            #expect(candidate.word.hasPrefix(completion.wordPrefix), "\(candidate.word) doesn't complete \(completion.wordPrefix)")
            #expect(!candidate.description.isEmpty, "\(candidate.word) has no description")
        }
    }

    @Test("nothing to say", arguments: [
        "echo \"git ch",  // the git is inside quotes, an argument to echo
        "git",  // the command's own name is being typed
        "FOO=1 gi",  // likewise, after an assignment
        "ls | gr",
        "notatool --he",
        "git status # ch",  // a comment
        "git log $(git merge-base a b)",  // the word is a substitution
        "",
    ])
    func nothing(_ line: String) {
        #expect(CommandSpecs.completion(forLine: line) == nil)
    }

    @Test("every option a typed prefix offers is one of the node's, once")
    func optionCandidatesAreTheNodesOwn() throws {
        let completion = try #require(CommandSpecs.completion(forLine: "git checkout -"))
        let words = completion.candidates.map(\.word)
        #expect(words.first == "-b")
        #expect(Set(words).count == words.count, "duplicates in \(words)")
        #expect(!words.contains("-C"), "git's own -C isn't checkout's")
    }

    // MARK: The data

    @Test("the bundled data loads, and every tool can be found by name and alias")
    func loads() throws {
        let library = try CommandSpecs.loaded.get()
        #expect(library.commands.count >= 40)
        for command in library.commands {
            for name in [command.name] + command.aliases {
                #expect(CommandSpecs.commandNames.contains(name))
                #expect(library.command(named: name)?.name == command.name, "\(name) finds another tool")
            }
        }
        for required in ["git", "gh", "docker", "kubectl", "helm", "npm", "yarn", "pnpm", "npx", "node", "pip", "pip3",
                         "python3", "cargo", "go", "swift", "xcodebuild", "make", "just", "brew", "apt", "apt-get",
                         "dnf", "yum", "systemctl", "journalctl", "launchctl", "ssh", "scp", "sftp", "rsync", "mosh",
                         "curl", "wget", "tar", "find", "grep", "ls", "cd", "cp", "mv", "rm", "mkdir", "chmod", "chown",
                         "cat", "less", "tail", "head", "ps", "kill", "top", "htop", "df", "du", "tmux", "terraform",
                         "aws", "sudo", "env", "ping", "dig", "nc", "openssl", "vim", "nvim", "nano", "time", "xargs"] {
            #expect(CommandSpecs.commandNames.contains(required), "\(required) isn't described")
        }
    }

    @Test("every tool and subcommand has a description; names are unique within a level")
    func holdsTogether() throws {
        let library = try CommandSpecs.loaded.get()
        func check(_ specs: [CommandSpec], at path: String) {
            var seen = Set<String>()
            for spec in specs {
                let here = "\(path) \(spec.name)"
                #expect(!spec.description.trimmingCharacters(in: .whitespaces).isEmpty, "\(here) has no description")
                for name in [spec.name] + spec.aliases {
                    #expect(seen.insert(name).inserted, "\(name) twice under\(path.isEmpty ? " the top" : path)")
                }
                var optionNames = Set<String>()
                for option in spec.options {
                    #expect(!option.description.isEmpty, "\(here) \(option.names[0]) has no description")
                    #expect(option.values.isEmpty || option.takes != nil, "\(here) \(option.names[0]): values without a kind")
                    for name in option.names {
                        #expect(name.hasPrefix("-") || name.hasPrefix("+"), "\(here): \(name) isn't an option name")
                        #expect(optionNames.insert(name).inserted, "\(here): option \(name) twice")
                    }
                }
                for argument in spec.args where !argument.values.isEmpty {
                    #expect(!argument.description.isEmpty, "\(here): fixed values without a description")
                }
                check(spec.subcommands, at: here)
            }
        }
        check(library.commands, at: "")
    }

    /// Codable ignores keys it doesn't know, so a misspelt `"takes"` would quietly make an option a flag.
    @Test("the JSON is valid and uses only the keys the reader knows")
    func onlyKnownKeys() throws {
        let url = try #require(CommandSpecs.resourceURL)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(root.keys) == ["format", "about", "commands"])
        let specKeys: Set<String> = ["name", "aliases", "description", "args", "afterDashDash", "options", "subcommands"]
        let optionKeys: Set<String> = ["names", "description", "takes", "values", "optionalValue", "persistent"]
        let argumentKeys: Set<String> = ["kind", "values", "description"]
        func check(_ spec: [String: Any], at path: String) {
            let here = "\(path) \(spec["name"] as? String ?? "?")"
            #expect(Set(spec.keys).isSubset(of: specKeys), "\(here): \(Set(spec.keys).subtracting(specKeys))")
            for option in spec["options"] as? [[String: Any]] ?? [] {
                #expect(Set(option.keys).isSubset(of: optionKeys), "\(here): \(Set(option.keys).subtracting(optionKeys))")
            }
            for case let argument as [String: Any] in spec["args"] as? [Any] ?? [] {
                #expect(Set(argument.keys).isSubset(of: argumentKeys), "\(here): \(Set(argument.keys).subtracting(argumentKeys))")
            }
            for sub in spec["subcommands"] as? [[String: Any]] ?? [] { check(sub, at: here) }
        }
        let commands = try #require(root["commands"] as? [[String: Any]])
        for command in commands { check(command, at: "") }
    }

    @Test("reading the data takes well under the 50 ms budget")
    func loadsQuickly() throws {
        let data = try Data(contentsOf: #require(CommandSpecs.resourceURL))
        let clock = ContinuousClock()
        var fastest = Duration.seconds(1)
        for _ in 0..<3 {
            let started = clock.now
            _ = try CommandSpecLibrary(data: data)
            fastest = min(fastest, clock.now - started)
        }
        #expect(fastest < .milliseconds(50), "fastest of three: \(fastest)")
    }
}

@Suite("A typed line split as a shell would")
struct CommandSpecLineReaderTests {
    typealias Typed = CommandSpecLineReader.TypedCommand

    @Test("quotes and backslashes are removed; a space ends the word being typed")
    func quoting() {
        #expect(CommandSpecLineReader.lastCommand(in: #"a 'b c' "d e" f\ g "#)
                == Typed(words: ["a", "b c", "d e", "f g"], current: "", currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: #"echo "git ch"#)
                == Typed(words: ["echo"], current: "git ch", currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: #"say "a \"b\" \$c" $'d\'e' 'f"g'"#)
                == Typed(words: ["say", #"a "b" $c"#, "d'e"], current: #"f"g"#, currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: "cd My\\ Fo")
                == Typed(words: ["cd"], current: "My Fo", currentIsRedirectTarget: false))
    }

    @Test("only the last command counts")
    func operators() {
        for line in ["a x && d y", "a x; d y", "a x || d y", "a x | d y", "a x & d y", "a x |& d y", "a x\nd y", "a x;d y"] {
            #expect(CommandSpecLineReader.lastCommand(in: line)?.words == ["d"], "\(line)")
            #expect(CommandSpecLineReader.lastCommand(in: line)?.current == "y", "\(line)")
        }
        #expect(CommandSpecLineReader.lastCommand(in: "a 'x;y' \"z|w\"")?.words == ["a", "x;y"])
    }

    @Test("redirections take their own word")
    func redirections() {
        #expect(CommandSpecLineReader.lastCommand(in: "ls 2>/dev/null -")
                == Typed(words: ["ls"], current: "-", currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: "ls > out -a ")
                == Typed(words: ["ls", "-a"], current: "", currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: "make 2>&1 | grep er")
                == Typed(words: ["grep"], current: "er", currentIsRedirectTarget: false))
        #expect(CommandSpecLineReader.lastCommand(in: "sort < in")
                == Typed(words: ["sort"], current: "in", currentIsRedirectTarget: true))
        #expect(CommandSpecLineReader.lastCommand(in: "cmd &>")
                == Typed(words: ["cmd"], current: "", currentIsRedirectTarget: true))
        #expect(CommandSpecLineReader.lastCommand(in: "diff <(sort a) b")?.words.count == 2)
    }

    @Test("an open $(, backquote or subshell is where typing happens; a closed one is part of a word")
    func nesting() {
        #expect(CommandSpecLineReader.lastCommand(in: "echo $(git ch")?.words == ["git"])
        #expect(CommandSpecLineReader.lastCommand(in: "echo \"$(git ch")?.words == ["git"])
        #expect(CommandSpecLineReader.lastCommand(in: "echo `git ch")?.words == ["git"])
        #expect(CommandSpecLineReader.lastCommand(in: "(cd x && make ")?.words == ["make"])
        let closed = CommandSpecLineReader.lastCommand(in: "x=$(git rev-parse HEAD) git log ")
        #expect(closed?.words == ["x=\u{FFFC}", "git", "log"])
        #expect(closed?.current == "")
    }

    @Test("a comment runs to the end of the line")
    func comments() {
        #expect(CommandSpecLineReader.lastCommand(in: "git status # ch") == nil)
        #expect(CommandSpecLineReader.lastCommand(in: "echo a#b")?.current == "a#b")
        #expect(CommandSpecLineReader.lastCommand(in: "echo '# x'")?.current == "# x")
    }
}
