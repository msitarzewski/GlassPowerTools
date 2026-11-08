//
//  TerminalCommandSecrets.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the commands that must never be kept as history or offered back
//  as a suggestion, because the line itself carries a password, a token or a key. Suggestions are
//  drawn on screen and history is written to disk, so a secret let through here is a secret shown
//  to anyone looking and kept in a file. `tasks/2026-11/2026-11-06_type-ahead.md`.
//
//  It runs on every command typed and every line imported from a shell's history file, tens of
//  thousands at a time, so it reads the line's bytes once into words (quotes removed, the way the
//  shell would split them) and checks those against fixed rules. No regular expressions.
//
//  **What it keeps out:**
//  - A command typed with a space first: zsh's HIST_IGNORE_SPACE and bash's `ignorespace` are how
//    someone says "don't remember this".
//  - A value given to a name that holds a secret: `GITHUB_TOKEN=…`, `export DB_PASSWORD=…`,
//    `--password=…` and `--token …`, `?api_key=…` in a URL, `"password": "…"` in JSON, and fish's
//    `set -x API_KEY …` or `aws configure set aws_secret_access_key …`. A name holds a secret
//    when one of its parts is TOKEN, SECRET, PASSWORD, PASSWD, PASS, PASSPHRASE, AUTH,
//    AUTHORIZATION, CREDENTIAL(S), BEARER, APIKEY, or KEY after API, ACCESS, PRIVATE, SECRET or
//    AUTH (`GITHUBTOKEN` and `DBPASSWORD` count too: those end in one).
//  - The tools' own password options: mysql's and mariadb's `-p<password>` (a bare `-p` asks, so
//    it stays), `sshpass -p`, `htpasswd -b`, `curl -u user:password`, `redis-cli -a`, mongosh's
//    `-p <password>`, `zip -P`, `7z -p<password>`, `ssh-keygen -N`, `docker login -p`, openssl's
//    `pass:<password>`, keytool's `-storepass`.
//  - Credential headers: `Authorization:`, `Proxy-Authorization:`, `Cookie:`, `X-Api-Key:` and
//    other `-token` and `-key` headers.
//  - A password in a URL (`postgres://ann:…@db.example.com`).
//  - Tokens recognisable by their form: AWS access key IDs (`AKIA`, `ASIA`), GitHub (`ghp_`,
//    `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`), GitLab (`glpat-`), Slack (`xox?-`), `sk-` API
//    keys, Stripe (`sk_live_`, `rk_live_`), npm (`npm_`), Hugging Face (`hf_`), Google (`AIza`)
//    and JWTs.
//  - A private key block, and a password echoed or printf'd into `sudo -S`, `passwd --stdin` or
//    `chpasswd`.
//
//  **What it lets through, deliberately:** a name that only says where a secret lives or how it
//  is used — `PASSWORD_STORE_DIR`, `AWS_SHARED_CREDENTIALS_FILE`, `SSH_AUTH_SOCK`,
//  `--password-stdin`, `--secret-id`, `--token-file` (the last part is a folder, file, socket,
//  host, ID, name, type and the like) — and every setting of `pass`, the password manager
//  (`PASSWORD_STORE_*`); flags that switch something on or off (`--no-auth`, `--ask-pass`,
//  `--with-token`); values that are only yes or no (`PasswordAuthentication=no`); and the words
//  alone (`kubectl get secrets`, `git commit -m "fix token parsing"`).
//
//  **False positives it accepts,** because a lost suggestion costs far less than a kept secret:
//  values that only refer elsewhere (`TOKEN=$(pass show x)`, `-H "Authorization: Bearer $TOKEN"`);
//  a sed or grep pattern that names a secret with a value (`sed 's/token=.*//'`); a value that is
//  the name of a secret rather than the secret (`--set auth.existingSecret=db`); and a long run of
//  letters that happens to start like a token.
//

import Foundation

/// The commands whose text may carry a secret, kept out of type-ahead's history and suggestions.
nonisolated enum TerminalCommandSecrets {
    /// True for a command that must never be kept in history or offered as a suggestion.
    static func mayHoldSecret(_ command: String) -> Bool {
        var command = command
        return command.withUTF8 { bytes in
            guard let first = bytes.first else { return false }
            if first == Byte.space { return true }
            if holdsPrivateKey(bytes) || holdsURLPassword(bytes) { return true }
            return CommandWords(bytes).mayHoldSecret()
        }
    }

    // MARK: - The line as written

    private static let beginMarker = Array("-----BEGIN".utf8)
    private static let privateKeyMarker = Array("PRIVATE KEY".utf8)
    private static let schemeMarker = Array("://".utf8)

    /// `-----BEGIN … PRIVATE KEY-----`: OpenSSH, PKCS#1 and #8, EC, and PGP's `PRIVATE KEY BLOCK`.
    private static func holdsPrivateKey(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        find(beginMarker, in: bytes, from: 0) != nil && find(privateKeyMarker, in: bytes, from: 0) != nil
    }

    /// `scheme://user:password@host`. RFC 3986 ends the authority at the first `/`, `?` or `#`;
    /// a password that holds one of those, or an `@`, is percent-encoded, so the last `@` before
    /// that end closes the user part.
    private static func holdsURLPassword(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var from = 0
        while let marker = find(schemeMarker, in: bytes, from: from) {
            let start = marker + schemeMarker.count
            var end = start
            var lastAt: Int?
            while end < bytes.count {
                let byte = bytes[end]
                if byte == Byte.slash || byte == Byte.question || byte == Byte.hash || Byte.endsURL(byte) { break }
                if byte == Byte.at { lastAt = end }
                end += 1
            }
            if let at = lastAt, let colon = (start ..< at).first(where: { bytes[$0] == Byte.colon }), colon + 1 < at {
                return true
            }
            from = start
        }
        return false
    }

    private static func find(_ needle: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard let base = bytes.baseAddress, from < bytes.count else { return nil }
        return needle.withUnsafeBytes { needleBytes in
            guard let found = memmem(base + from, bytes.count - from, needleBytes.baseAddress, needleBytes.count) else {
                return nil
            }
            return UnsafeRawPointer(base).distance(to: UnsafeRawPointer(found))
        }
    }

    // MARK: - Names

    /// Parts of a name that make it hold a secret.
    private static let secretParts: Set<String> = [
        "TOKEN", "TOKENS", "SECRET", "SECRETS", "PASSWORD", "PASSWORDS", "PASSWD", "PASS", "PASSPHRASE",
        "AUTH", "AUTHKEY", "AUTHTOKEN", "AUTHORIZATION", "CREDENTIAL", "CREDENTIALS", "CREDS", "BEARER",
        "APIKEY", "ACCESSKEY", "PRIVATEKEY", "SECRETKEY",
    ]
    /// Endings that do it inside a longer part: `GITHUBTOKEN`, `DBPASSWORD`. Not PASS, which
    /// would take in BYPASS and COMPASS.
    private static let secretEndings = ["TOKEN", "SECRET", "PASSWORD", "PASSWD", "PASSPHRASE", "APIKEY"]
    /// `API_KEY`, `ACCESS_KEY`, `PRIVATE_KEY`: KEY alone is a key file, a sort key, a map key.
    private static let keyQualifiers: Set<String> = ["API", "ACCESS", "PRIVATE", "SECRET", "AUTH"]
    /// A last part that says the value is where a secret is, or how it is used, not the secret.
    private static let describingParts: Set<String> = [
        "DIR", "DIRS", "DIRECTORY", "FOLDER", "FILE", "FILES", "PATH", "URL", "URI", "ENDPOINT", "HOST",
        "HOSTNAME", "PORT", "SERVER", "DOMAIN", "SOCK", "SOCKET", "TYPE", "METHOD", "METHODS", "MODE", "ID",
        "NAME", "ARN", "HELPER", "STDIN", "FD", "ENV", "CMD", "COMMAND", "PROMPT", "LENGTH", "TTL", "TIMEOUT",
        "EXPIRY", "EXPIRES", "EXPIRATION", "REQUIRED", "ENABLED", "DISABLED",
    ]
    /// A flag's first part that makes it a switch taking no value (`--no-auth`, `--ask-pass`).
    private static let switchParts: Set<String> = [
        "NO", "WITH", "WITHOUT", "SKIP", "ASK", "SAVE", "STORE", "USE", "ALLOW", "SHOW", "HIDE", "REQUIRE",
        "ENABLE", "DISABLE", "PROMPT", "FORGET", "CLEAR",
    ]
    /// Values that only say yes or no.
    private static let switchValues: Set<String> = [
        "YES", "NO", "TRUE", "FALSE", "ON", "OFF", "0", "1", "Y", "N", "NONE", "NULL", "NIL",
    ]

    /// Whether a name — a variable, an option, a key, a header — holds a secret.
    fileprivate static func isSecretName<Name: Collection<UInt8>>(_ name: Name) -> Bool {
        let parts = nameParts(name)
        guard let last = parts.last else { return false }
        // `pass`, the password manager, names its settings PASSWORD_STORE_*; none of them is one.
        if parts.count > 1, parts[0] == "PASSWORD", parts[1] == "STORE" { return false }
        if describingParts.contains(last) { return false }
        for (index, part) in parts.enumerated() {
            if secretParts.contains(part) { return true }
            // MYSQL_PWD is MySQL's password variable; PWD alone is the working folder.
            if part == "PWD", parts.count > 1 { return true }
            if part == "KEY", index > 0, keyQualifiers.contains(parts[index - 1]) { return true }
            if secretEndings.contains(where: { part.count > $0.count && part.hasSuffix($0) }) { return true }
        }
        return false
    }

    fileprivate static func isSwitch<Name: Collection<UInt8>>(_ name: Name) -> Bool {
        nameParts(name).first.map(switchParts.contains) ?? false
    }

    fileprivate static func isSwitchValue<Value: Collection<UInt8>>(_ value: Value) -> Bool {
        value.count <= 5 && switchValues.contains(String(decoding: value.map(Byte.upper), as: UTF8.self))
    }

    /// A name's parts, upper-cased, split at anything not a letter or digit and where a lower-case
    /// letter meets an upper-case one: `_authToken` is AUTH and TOKEN, `PasswordAuthentication`
    /// PASSWORD and AUTHENTICATION.
    private static func nameParts<Name: Collection<UInt8>>(_ name: Name) -> [String] {
        var parts: [String] = []
        var part: [UInt8] = []
        var afterLower = false
        for byte in name {
            guard Byte.isAlphanumeric(byte) else {
                if !part.isEmpty { parts.append(String(decoding: part, as: UTF8.self)); part.removeAll() }
                afterLower = false
                continue
            }
            if Byte.isUpper(byte), afterLower, !part.isEmpty {
                parts.append(String(decoding: part, as: UTF8.self))
                part.removeAll()
            }
            part.append(Byte.upper(byte))
            afterLower = !Byte.isUpper(byte)
        }
        if !part.isEmpty { parts.append(String(decoding: part, as: UTF8.self)) }
        return parts
    }

    // MARK: - Tokens

    /// A run of letters, digits, `_`, `-` and `.` that has a known token's form.
    fileprivate static func isToken(_ run: ArraySlice<UInt8>) -> Bool {
        guard run.count >= 16, let first = run.first else { return false }
        switch first {
        case UInt8(ascii: "A"):
            if run.starts(with: Prefix.akia) || run.starts(with: Prefix.asia) {
                // An AWS access key ID: twenty upper-case letters and digits, no more.
                return run.count >= 20 && count(run, from: 4, Byte.isUpperOrDigit) >= 16
                    && (run.count == 20 || !Byte.isAlphanumeric(run[run.startIndex + 20]))
            }
            return run.starts(with: Prefix.google) && count(run, from: 4, Byte.isBase64URL) >= 35
        case UInt8(ascii: "g"):
            if Prefix.github.contains(where: { run.starts(with: $0) }) {
                return count(run, from: 4, Byte.isAlphanumeric) >= 30
            }
            if run.starts(with: Prefix.githubFineGrained) { return count(run, from: 11, Byte.isWordByte) >= 22 }
            return run.starts(with: Prefix.gitlab) && count(run, from: 6, Byte.isBase64URL) >= 20
        case UInt8(ascii: "x"):
            // Slack: xoxa-, xoxb-, xoxp-, xoxo-, xoxs-, xoxr-.
            guard run.starts(with: Prefix.slack), run.count > 5,
                  Prefix.slackKinds.contains(run[run.startIndex + 3]), run[run.startIndex + 4] == Byte.dash else { return false }
            return count(run, from: 5, { Byte.isAlphanumeric($0) || $0 == Byte.dash }) >= 10
        case UInt8(ascii: "s"), UInt8(ascii: "r"):
            if Prefix.stripe.contains(where: { run.starts(with: $0) }) { return count(run, from: 8, Byte.isAlphanumeric) >= 10 }
            return run.starts(with: Prefix.secretKey) && count(run, from: 3, Byte.isBase64URL) >= 20
        case UInt8(ascii: "n"):
            return run.starts(with: Prefix.npm) && count(run, from: 4, Byte.isAlphanumeric) >= 36
        case UInt8(ascii: "h"):
            return run.starts(with: Prefix.huggingFace) && count(run, from: 3, Byte.isAlphanumeric) >= 30
        case UInt8(ascii: "e"):
            return run.starts(with: Prefix.jwt) && isJWT(run)
        default:
            return false
        }
    }

    /// Base64url parts joined by dots, the first a JSON header (`eyJ` is `{"`): a JWT's three, or
    /// an encrypted JWE's five (whose second can be empty).
    private static func isJWT(_ run: ArraySlice<UInt8>) -> Bool {
        let parts = run.split(separator: Byte.dot, omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0].count >= 10 else { return false }
        return parts.count(where: { !$0.isEmpty }) >= 3 && parts.allSatisfy { $0.allSatisfy(Byte.isBase64URL) }
    }

    private static func count(_ run: ArraySlice<UInt8>, from offset: Int, _ matches: (UInt8) -> Bool) -> Int {
        var index = run.startIndex + offset
        while index < run.endIndex, matches(run[index]) { index += 1 }
        return index - (run.startIndex + offset)
    }

    nonisolated private enum Prefix {
        static let akia = Array("AKIA".utf8), asia = Array("ASIA".utf8), google = Array("AIza".utf8)
        static let github = ["ghp_", "gho_", "ghu_", "ghs_", "ghr_"].map { Array($0.utf8) }
        static let githubFineGrained = Array("github_pat_".utf8), gitlab = Array("glpat-".utf8)
        static let slack = Array("xox".utf8)
        static let slackKinds: Set<UInt8> = Set("abposr".utf8)
        static let stripe = ["sk_live_", "sk_test_", "rk_live_", "rk_test_"].map { Array($0.utf8) }
        static let secretKey = Array("sk-".utf8), npm = Array("npm_".utf8), huggingFace = Array("hf_".utf8)
        static let jwt = Array("eyJ".utf8)
    }
}

// MARK: - The line as the shell splits it

/// A command line split into words the way a shell splits it, quotes removed, with where each
/// simple command starts and whether a pipe feeds it. Enough to read options and values; not a
/// shell parser (no expansion, no nesting).
nonisolated private struct CommandWords {
    private typealias Secrets = TerminalCommandSecrets

    struct Word {
        var range: Range<Int>
        /// After `<`, `>` and the like: a file or a here-document's text, not an argument.
        var redirected: Bool
    }
    struct Command {
        var words: Range<Int>
        /// Fed by `|` from the command before it.
        var piped: Bool
        /// Has a here-document or here-string (`<<`, `<<<`).
        var hereText: Bool
    }

    private(set) var text: [UInt8] = []
    private(set) var words: [Word] = []
    private(set) var commands: [Command] = []

    init(_ bytes: UnsafeBufferPointer<UInt8>) {
        text.reserveCapacity(bytes.count)
        var wordStart: Int?
        var redirectNext = false
        var commandStart = 0
        var piped = false
        var hereText = false

        func endWord() {
            guard let start = wordStart else { return }
            words.append(Word(range: start ..< text.count, redirected: redirectNext))
            redirectNext = false
            wordStart = nil
        }
        func endCommand(pipesOn: Bool) {
            endWord()
            if words.count > commandStart {
                commands.append(Command(words: commandStart ..< words.count, piped: piped, hereText: hereText))
            }
            commandStart = words.count
            piped = pipesOn
            hereText = false
        }
        func append(_ byte: UInt8) {
            if wordStart == nil { wordStart = text.count }
            text.append(byte)
        }

        var index = 0
        let count = bytes.count
        func next(_ offset: Int = 1) -> UInt8? { index + offset < count ? bytes[index + offset] : nil }
        while index < count {
            let byte = bytes[index]
            switch byte {
            case Byte.space, Byte.tab, Byte.carriageReturn:
                endWord()
                index += 1
            case Byte.newline, Byte.semicolon, Byte.openParen, Byte.closeParen, Byte.backtick:
                endCommand(pipesOn: false)
                index += 1
            case Byte.pipe:
                if next() == Byte.pipe {
                    endCommand(pipesOn: false)
                    index += 2
                } else {
                    endCommand(pipesOn: true)
                    index += next() == Byte.ampersand ? 2 : 1
                }
            case Byte.ampersand:
                if next() == Byte.greater {
                    endWord()
                    index += 2
                    if index < count, bytes[index] == Byte.greater { index += 1 }
                    redirectNext = true
                } else {
                    endCommand(pipesOn: false)
                    index += next() == Byte.ampersand ? 2 : 1
                }
            case Byte.less, Byte.greater:
                endWord()
                var run = 0
                while index < count, bytes[index] == byte { run += 1; index += 1 }
                if byte == Byte.less, run >= 2 { hereText = true }
                if index < count, bytes[index] == Byte.ampersand || bytes[index] == Byte.pipe { index += 1 }
                redirectNext = true
            case Byte.singleQuote:
                if wordStart == nil { wordStart = text.count }
                index += 1
                while index < count, bytes[index] != Byte.singleQuote { text.append(bytes[index]); index += 1 }
                index += 1
            case Byte.doubleQuote:
                if wordStart == nil { wordStart = text.count }
                index += 1
                while index < count, bytes[index] != Byte.doubleQuote {
                    if bytes[index] == Byte.backslash, let escaped = next(), Byte.escapableInDoubleQuotes(escaped) {
                        if escaped != Byte.newline { text.append(escaped) }
                        index += 2
                    } else {
                        text.append(bytes[index])
                        index += 1
                    }
                }
                index += 1
            case Byte.backslash:
                if let escaped = next() {
                    if escaped != Byte.newline { append(escaped) }
                    index += 2
                } else {
                    index += 1
                }
            default:
                append(byte)
                index += 1
            }
        }
        endCommand(pipesOn: false)
    }

    func bytes(_ word: Int) -> ArraySlice<UInt8> { text[words[word].range] }

    /// The word after `word` in the same command, when it is an argument and not an option.
    func value(after word: Int, in command: Command) -> ArraySlice<UInt8>? {
        let next = word + 1
        guard next < command.words.upperBound, !words[next].redirected else { return nil }
        let value = bytes(next)
        return value.first == Byte.dash ? nil : value
    }

    /// A word's last path component, so `/usr/bin/mysql` is `mysql`.
    func baseName(_ word: Int) -> ArraySlice<UInt8> {
        let all = bytes(word)
        guard let slash = all.lastIndex(of: Byte.slash) else { return all }
        return all[(slash + 1)...]
    }

    // MARK: Rules

    func mayHoldSecret() -> Bool {
        for (index, command) in commands.enumerated() {
            for word in command.words where wordHoldsSecret(word, in: command) { return true }
            if toolHoldsSecret(command) { return true }
            if feedsPasswordOnInput(command, at: index) { return true }
        }
        return false
    }

    /// A token, a `name=value`, a JSON `"name": "value"`, a credential header or an option given
    /// its value.
    private func wordHoldsSecret(_ word: Int, in command: Command) -> Bool {
        let range = words[word].range
        guard !range.isEmpty else { return false }
        // Tokens recognisable by their form, wherever they stand in the word.
        var start = range.lowerBound
        while start < range.upperBound {
            guard Byte.isTokenByte(text[start]) else { start += 1; continue }
            var end = start
            while end < range.upperBound, Byte.isTokenByte(text[end]) { end += 1 }
            if Secrets.isToken(text[start ..< end]) { return true }
            start = end
        }
        for index in range {
            switch text[index] {
            case Byte.equals where assignmentHoldsSecret(at: index, in: range): return true
            case Byte.colon where labelHoldsSecret(at: index, in: range, word: word, command: command): return true
            default: continue
            }
        }
        let all = text[range]
        guard all.first == Byte.dash, let value = value(after: word, in: command) else { return false }
        if all.starts(with: Byte.doubleDash) {
            // `--token abc`; `--token=abc` was read as an assignment above.
            let name = all.dropFirst(2)
            return !name.contains(Byte.equals) && !Secrets.isSwitch(name)
                && Secrets.isSecretName(name) && !Secrets.isSwitchValue(value)
        }
        // Long options with one dash, as keytool and openssl spell them: `-storepass changeit`.
        // openssl's `-passin env:VAR` and `file:path` name where the password is, not the password.
        guard (5 ... 14).contains(all.count) else { return false }
        let name = String(decoding: all.dropFirst().map(Byte.lower), as: UTF8.self)
        guard Self.singleDashSecretOptions.contains(name) else { return false }
        return !Self.passwordSources.contains(where: { value.starts(with: $0) })
    }

    private static let singleDashSecretOptions: Set<String> = [
        "pass", "password", "passwd", "token", "secret", "apikey", "passphrase",
        "storepass", "keypass", "srcstorepass", "deststorepass", "srckeypass", "destkeypass",
    ]
    private static let passwordSources = ["env:", "file:", "fd:", "stdin"].map { Array($0.utf8) }

    /// `NAME=value` anywhere in a word: a variable, `--name=value`, `?name=value`, `-Dname=value`.
    private func assignmentHoldsSecret(at equals: Int, in range: Range<Int>) -> Bool {
        var start = equals
        while start > range.lowerBound, Byte.isNameByte(text[start - 1]) { start -= 1 }
        while start < equals, text[start] == Byte.dash { start += 1 }
        guard start < equals else { return false }
        let value = valueBytes(from: equals + 1, to: range.upperBound)
        return !value.isEmpty && !Secrets.isSwitchValue(value)
            && Secrets.isSecretName(text[start ..< equals])
    }

    /// `"name": "value"` in JSON; a credential header (`Authorization: Bearer …`, also as `-H…`
    /// and as `--header=…`); openssl's `pass:<password>`. A bare `name: value` is not read: commit
    /// messages are written that way (`auth: fix the login`).
    private func labelHoldsSecret(at colon: Int, in range: Range<Int>, word: Int, command: Command) -> Bool {
        var nameEnd = colon
        let quoted = nameEnd > range.lowerBound && text[nameEnd - 1] == Byte.doubleQuote
        if quoted { nameEnd -= 1 }
        // `-HAuthorization: …`: the header starts after the option's two letters.
        let all = text[range]
        let headerAttached = all.starts(with: Byte.headerOption) && all.count > 2 && text[range.lowerBound + 2] != Byte.dash
        let floor = headerAttached ? range.lowerBound + 2 : range.lowerBound
        var nameStart = nameEnd
        while nameStart > floor, Byte.isNameByte(text[nameStart - 1]) { nameStart -= 1 }
        guard nameStart < nameEnd else { return false }
        let name = text[nameStart ..< nameEnd]

        var valueStart = colon + 1
        while valueStart < range.upperBound, text[valueStart] == Byte.space || text[valueStart] == Byte.tab { valueStart += 1 }
        let spaced = valueStart > colon + 1
        if valueStart < range.upperBound, text[valueStart] == Byte.doubleQuote || text[valueStart] == Byte.singleQuote {
            valueStart += 1
        }
        let value = valueBytes(from: valueStart, to: range.upperBound)

        if quoted {
            guard nameStart > range.lowerBound, text[nameStart - 1] == Byte.doubleQuote else { return false }
            if let first = value.first, first == Byte.openBrace || first == Byte.openBracket { return false }
            return !value.isEmpty && !Secrets.isSwitchValue(value) && Secrets.isSecretName(name)
        }
        // Only a name that starts the word, or follows `-H` or `--header=` in it.
        let wordStart = range.lowerBound
        let leading = text[wordStart ..< nameStart]
        guard leading.isEmpty || leading.elementsEqual(Byte.headerOption) || leading.elementsEqual(Byte.headerAssignment) else {
            return false
        }
        if !spaced, Self.isPass(name), !value.isEmpty { return true }
        guard Self.isCredentialHeader(name) else { return false }
        if value.isEmpty { return self.value(after: word, in: command) != nil }
        return value.first != Byte.slash
    }

    private static func isPass(_ name: ArraySlice<UInt8>) -> Bool { name.map(Byte.lower).elementsEqual("pass".utf8) }

    /// Authorization, Proxy-Authorization and Cookie, and headers like `X-Api-Key`,
    /// `X-Auth-Token` and `Private-Token` that end in what they carry.
    private static func isCredentialHeader(_ name: ArraySlice<UInt8>) -> Bool {
        let lower = String(decoding: name.map(Byte.lower), as: UTF8.self)
        if lower == "authorization" || lower == "proxy-authorization" || lower == "cookie" { return true }
        guard name.contains(Byte.dash), Secrets.isSecretName(name) else { return false }
        let last = lower.split(separator: "-").last.map(String.init) ?? lower
        return ["token", "key", "secret", "password", "apikey", "auth"].contains(last)
    }

    /// The value's bytes up to where a URL query, a JSON member or a list item ends.
    private func valueBytes(from start: Int, to end: Int) -> ArraySlice<UInt8> {
        var stop = start
        while stop < end, !Byte.endsValue(text[stop]) { stop += 1 }
        return text[start ..< stop]
    }

    /// The tools that take a password on their command line, each as it spells it.
    private func toolHoldsSecret(_ command: Command) -> Bool {
        var settingAt: Int?
        for word in command.words where !words[word].redirected {
            guard let tool = tool(word) else { continue }
            let after = (word + 1) ..< command.words.upperBound
            switch tool {
            case .mysql:
                // `-pPASSWORD`; a bare `-p` asks for it.
                if after.contains(where: { isAttached(Byte.lowerP, $0) }) { return true }
            case .sshpass, .redis:
                let letter = tool == .sshpass ? Byte.lowerP : Byte.lowerA
                if after.contains(where: { isAttached(letter, $0) || (isOption(letter, $0) && hasArgument($0, command)) }) {
                    return true
                }
            case .mongo:
                if after.contains(where: { isAttached(Byte.lowerP, $0) || (isOption(Byte.lowerP, $0) && value(after: $0, in: command) != nil) }) {
                    return true
                }
            case .zip:
                if after.contains(where: { isAttached(Byte.upperP, $0) || (isOption(Byte.upperP, $0) && hasArgument($0, command)) }) {
                    return true
                }
            case .sevenZip:
                if after.contains(where: { isAttached(Byte.lowerP, $0) }) { return true }
            case .sshKeygen:
                // `-N new` and `-P old` passphrases; `-N ""` is none.
                if after.contains(where: { (isOption(Byte.upperN, $0) || isOption(Byte.upperP, $0)) && nonEmptyArgument($0, command) }) {
                    return true
                }
            case .htpasswd:
                // `-b`: the password is the last argument.
                if after.contains(where: { isShortCluster($0, containing: Byte.lowerB) }) { return true }
            case .curl:
                if after.contains(where: { curlUserHoldsPassword($0, command) }) { return true }
            case .httpie:
                if after.contains(where: { isOption(Byte.lowerA, $0) && (value(after: $0, in: command)?.contains(Byte.colon) ?? false) }) {
                    return true
                }
            case .registry:
                guard command.words.contains(where: { bytes($0).elementsEqual(Byte.login) }) else { continue }
                if after.contains(where: { isAttached(Byte.lowerP, $0) || (isOption(Byte.lowerP, $0) && hasArgument($0, command)) }) {
                    return true
                }
            case .setting:
                settingAt = settingAt ?? word
            case .sudo, .passwd, .chpasswd, .echo, .wrapper:
                continue
            }
        }
        // `set -gx API_KEY abc`, `setenv TOKEN abc`, `aws configure set aws_secret_access_key abc`.
        if let verb = settingAt {
            for word in (verb + 1) ..< command.words.upperBound where !words[word].redirected {
                let all = bytes(word)
                guard all.first != Byte.dash, let value = value(after: word, in: command) else { continue }
                var start = all.endIndex
                while start > all.startIndex, Byte.isNameByte(all[start - 1]) { start -= 1 }
                if start < all.endIndex, Secrets.isSecretName(all[start...]),
                   !Secrets.isSwitchValue(value) {
                    return true
                }
            }
        }
        return false
    }

    /// A password typed into a tool that reads it from standard input, by `echo` or `printf`
    /// through a pipe, or by a here-document.
    private func feedsPasswordOnInput(_ command: Command, at index: Int) -> Bool {
        guard readsPasswordFromInput(command) else { return false }
        if command.hereText { return true }
        var feeder = index
        while commands[feeder].piped, feeder > 0 {
            feeder -= 1
            if let name = commandName(commands[feeder]), tool(name) == .echo { return true }
        }
        return false
    }

    private func readsPasswordFromInput(_ command: Command) -> Bool {
        for word in command.words where !words[word].redirected {
            switch tool(word) {
            case .chpasswd: return true
            case .passwd where command.words.contains(where: { $0 > word && bytes($0).elementsEqual(Byte.stdinOption) }):
                return true
            case .sudo where sudoReadsStdin(after: word, in: command): return true
            default: continue
            }
        }
        return false
    }

    /// sudo's own options, up to the command it runs: `-S` or `--stdin`, alone or in a cluster.
    /// Options of the command it runs (`pacman -S`) are not sudo's.
    private func sudoReadsStdin(after sudo: Int, in command: Command) -> Bool {
        var word = sudo + 1
        while word < command.words.upperBound {
            let all = bytes(word)
            guard all.first == Byte.dash, all.count > 1 else { return false }
            if all.elementsEqual(Byte.doubleDash) { return false }
            if all.starts(with: Byte.doubleDash) {
                if all.elementsEqual(Byte.stdinOption) { return true }
                if !all.contains(Byte.equals), Byte.sudoLongOptionsWithValue.contains(where: { all.elementsEqual($0) }) { word += 1 }
            } else {
                let letters = all.dropFirst()
                if letters.contains(Byte.upperS) { return true }
                if let last = letters.last, Byte.sudoOptionsWithValue.contains(last) { word += 1 }
            }
            word += 1
        }
        return false
    }

    /// The command's own name: its first word that is not a variable assignment or a wrapper
    /// like `command` or `env`.
    private func commandName(_ command: Command) -> ArraySlice<UInt8>? {
        for word in command.words where !words[word].redirected {
            let all = bytes(word)
            if let equals = all.firstIndex(of: Byte.equals), equals > all.startIndex,
               all[..<equals].allSatisfy(Byte.isIdentifierByte) {
                continue
            }
            if all.first == Byte.dash || tool(word) == .wrapper { continue }
            return baseName(word)
        }
        return nil
    }

    /// The tools these rules know, by the name a command calls them.
    nonisolated enum Tool {
        case mysql, sshpass, redis, mongo, zip, sevenZip, sshKeygen, htpasswd, curl, httpie, registry, setting
        case sudo, passwd, chpasswd, echo, wrapper
    }

    private static let tools: [String: Tool] = {
        var tools: [String: Tool] = [
            "sshpass": .sshpass, "redis-cli": .redis, "zip": .zip, "unzip": .zip, "ssh-keygen": .sshKeygen,
            "htpasswd": .htpasswd, "curl": .curl, "http": .httpie, "https": .httpie,
            "sudo": .sudo, "passwd": .passwd, "chpasswd": .chpasswd,
        ]
        for name in ["mongo", "mongosh", "mongodump", "mongorestore", "mongoexport", "mongoimport"] { tools[name] = .mongo }
        for name in ["7z", "7za", "7zr", "7zz"] { tools[name] = .sevenZip }
        // Their `-p` is a password only after `login`; `docker run -p` publishes a port.
        for name in ["docker", "podman", "nerdctl", "buildah", "skopeo", "helm", "oc", "cf", "az"] { tools[name] = .registry }
        for name in ["set", "setenv", "config", "configure"] { tools[name] = .setting }
        for name in ["echo", "printf", "print"] { tools[name] = .echo }
        for name in ["command", "builtin", "exec", "nohup", "time", "env", "nice", "noglob"] { tools[name] = .wrapper }
        return tools
    }()

    /// Which tool a word names, by its last path component, so `/usr/bin/mysql` is mysql. One
    /// lookup a word: the rules run on every command, and most words are no tool at all.
    private func tool(_ word: Int) -> Tool? { tool(baseName(word)) }

    private func tool(_ name: ArraySlice<UInt8>) -> Tool? {
        guard let first = name.first, Byte.isLower(first) || Byte.isDigit(first), name.count <= 16 else { return nil }
        let key = String(decoding: name, as: UTF8.self)
        // mysql, mysqldump, mysqladmin…; mariadb, mariadb-dump…: `-p` is the password in all of them.
        if key.hasPrefix("mysql") || key.hasPrefix("mariadb") { return .mysql }
        return Self.tools[key]
    }

    /// `-<letter><value>` with the value attached, as `-phunter2`.
    private func isAttached(_ letter: UInt8, _ word: Int) -> Bool {
        let all = bytes(word)
        return all.count > 2 && all.first == Byte.dash && all[all.startIndex + 1] == letter
    }

    private func isOption(_ letter: UInt8, _ word: Int) -> Bool {
        let all = bytes(word)
        return all.count == 2 && all.first == Byte.dash && all.last == letter
    }

    /// The next word, as an option's argument: here anything, even something starting with a dash.
    private func hasArgument(_ word: Int, _ command: Command) -> Bool {
        word + 1 < command.words.upperBound && !words[word + 1].redirected
    }

    private func nonEmptyArgument(_ word: Int, _ command: Command) -> Bool {
        hasArgument(word, command) && !bytes(word + 1).isEmpty
    }

    /// `-cb`, `-bB`: single-dash letters, one of them `letter`.
    private func isShortCluster(_ word: Int, containing letter: UInt8) -> Bool {
        let all = bytes(word)
        guard all.count > 1, all.first == Byte.dash, all[all.startIndex + 1] != Byte.dash else { return false }
        let letters = all.dropFirst()
        return letters.allSatisfy(Byte.isLetter) && letters.contains(letter)
    }

    /// curl's `-u user:password`, `-uuser:password`, `--user=…` and the proxy's `-U`.
    private func curlUserHoldsPassword(_ word: Int, _ command: Command) -> Bool {
        let all = bytes(word)
        var credentials: ArraySlice<UInt8>?
        if isOption(Byte.lowerU, word) || isOption(Byte.upperU, word)
            || all.elementsEqual(Byte.userOption) || all.elementsEqual(Byte.proxyUserOption) {
            credentials = hasArgument(word, command) ? bytes(word + 1) : nil
        } else if isAttached(Byte.lowerU, word) || isAttached(Byte.upperU, word) {
            credentials = all.dropFirst(2)
        } else if all.starts(with: Byte.userOption + [Byte.equals]) || all.starts(with: Byte.proxyUserOption + [Byte.equals]) {
            credentials = all.drop(while: { $0 != Byte.equals }).dropFirst()
        }
        guard let credentials, let colon = credentials.firstIndex(of: Byte.colon) else { return false }
        return colon + 1 < credentials.endIndex
    }
}

// MARK: - Bytes

nonisolated private enum Byte {
    static let tab: UInt8 = 0x09, newline: UInt8 = 0x0A, carriageReturn: UInt8 = 0x0D, space: UInt8 = 0x20
    static let doubleQuote = UInt8(ascii: "\""), hash = UInt8(ascii: "#"), ampersand = UInt8(ascii: "&")
    static let singleQuote = UInt8(ascii: "'"), openParen = UInt8(ascii: "("), closeParen = UInt8(ascii: ")")
    static let comma = UInt8(ascii: ","), dash = UInt8(ascii: "-"), dot = UInt8(ascii: "."), slash = UInt8(ascii: "/")
    static let colon = UInt8(ascii: ":"), semicolon = UInt8(ascii: ";"), less = UInt8(ascii: "<")
    static let equals = UInt8(ascii: "="), greater = UInt8(ascii: ">"), question = UInt8(ascii: "?")
    static let at = UInt8(ascii: "@"), openBracket = UInt8(ascii: "["), backslash = UInt8(ascii: "\\")
    static let backtick = UInt8(ascii: "`"), openBrace = UInt8(ascii: "{"), pipe = UInt8(ascii: "|")
    static let closeBrace = UInt8(ascii: "}")
    static let lowerA = UInt8(ascii: "a"), lowerB = UInt8(ascii: "b"), lowerP = UInt8(ascii: "p")
    static let lowerU = UInt8(ascii: "u"), upperN = UInt8(ascii: "N"), upperP = UInt8(ascii: "P")
    static let upperS = UInt8(ascii: "S"), upperU = UInt8(ascii: "U")

    static let doubleDash = Array("--".utf8)
    static let headerOption = Array("-H".utf8), headerAssignment = Array("--header=".utf8)
    static let userOption = Array("--user".utf8), proxyUserOption = Array("--proxy-user".utf8)
    static let stdinOption = Array("--stdin".utf8), login = Array("login".utf8)
    /// sudo's options that take a value, short and long (sudo(8)).
    static let sudoOptionsWithValue: Set<UInt8> = Set("CDghpRrTtUu".utf8)
    static let sudoLongOptionsWithValue = [
        "--close-from", "--chdir", "--group", "--host", "--prompt", "--chroot", "--role", "--type",
        "--command-timeout", "--other-user", "--user",
    ].map { Array($0.utf8) }

    static func isUpper(_ byte: UInt8) -> Bool { byte >= 0x41 && byte <= 0x5A }
    static func isLower(_ byte: UInt8) -> Bool { byte >= 0x61 && byte <= 0x7A }
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    static func isLetter(_ byte: UInt8) -> Bool { isUpper(byte) || isLower(byte) }
    static func isAlphanumeric(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) }
    static func isUpperOrDigit(_ byte: UInt8) -> Bool { isUpper(byte) || isDigit(byte) }
    static func isWordByte(_ byte: UInt8) -> Bool { isAlphanumeric(byte) || byte == 0x5F }
    static func isBase64URL(_ byte: UInt8) -> Bool { isWordByte(byte) || byte == dash }
    static func isIdentifierByte(_ byte: UInt8) -> Bool { isWordByte(byte) }
    /// What a name is made of: a variable, an option, a dotted setting, a header.
    static func isNameByte(_ byte: UInt8) -> Bool { isWordByte(byte) || byte == dash || byte == dot }
    /// What a token is made of, so a run of these is looked at whole.
    static func isTokenByte(_ byte: UInt8) -> Bool { isNameByte(byte) }
    static func upper(_ byte: UInt8) -> UInt8 { isLower(byte) ? byte - 0x20 : byte }
    static func lower(_ byte: UInt8) -> UInt8 { isUpper(byte) ? byte + 0x20 : byte }

    static func escapableInDoubleQuotes(_ byte: UInt8) -> Bool {
        byte == doubleQuote || byte == backslash || byte == UInt8(ascii: "$") || byte == backtick || byte == newline
    }
    /// The bytes that end a URL's authority as it sits in a command line.
    static func endsURL(_ byte: UInt8) -> Bool {
        byte == space || byte == tab || byte == newline || byte == doubleQuote || byte == singleQuote
            || byte == less || byte == greater || byte == pipe || byte == semicolon
    }
    /// The bytes that end a value inside a word: a query's `&`, a JSON member's quote or comma.
    static func endsValue(_ byte: UInt8) -> Bool {
        byte == ampersand || byte == space || byte == tab || byte == newline || byte == doubleQuote
            || byte == singleQuote || byte == comma || byte == semicolon || byte == closeBrace || byte == closeParen
    }
}
