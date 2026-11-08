import Foundation
import Testing
@testable import GlassTerminal

/// D102 (2026-11-06): commands that carry a secret are never kept in type-ahead's history or
/// offered back, and ordinary commands that only mention one are. Every secret here is fake and
/// built at run time, so no scanner reads a real-looking token in this file.
/// Off the main actor (the test target's default): the filter is `nonisolated`, and its speed test held the main
/// thread for seconds at a stretch, which every test that draws a terminal waits on (sampled 2026-11-06).
@Suite("Commands that carry a secret are kept out of history and suggestions")
nonisolated struct TerminalCommandSecretsTests {
    private typealias Secrets = TerminalCommandSecrets

    nonisolated private enum Fake {
        static let github = "ghp_" + String(repeating: "x", count: 36)
        static let githubFineGrained = "github_pat_" + String(repeating: "x0", count: 20)
        static let gitlab = "glpat-" + String(repeating: "x", count: 20)
        static let aws = "AKIA" + String(repeating: "0", count: 16)
        static let awsSession = "ASIA" + String(repeating: "X", count: 16)
        static let slack = "xoxb-" + "not-a-real-token"
        static let apiKey = "sk-" + String(repeating: "x", count: 24)
        static let stripe = "sk_" + "live_" + String(repeating: "x", count: 24)
        static let npm = "npm_" + String(repeating: "x", count: 36)
        static let huggingFace = "hf_" + String(repeating: "x", count: 34)
        static let google = "AI" + "za" + String(repeating: "x", count: 35)
        static let jwt = "eyJ" + String(repeating: "x", count: 12) + "." + String(repeating: "y", count: 12)
            + "." + String(repeating: "z", count: 12)
        static let privateKey = "-----BEGIN OPENSSH " + "PRIVATE KEY-----"
        static let pgpPrivateKey = "-----BEGIN PGP " + "PRIVATE KEY BLOCK-----"
    }

    @Test("a command typed with a space first, zsh's and bash's sign for \"don't remember this\"",
          arguments: [" ls -la", " git status", "  export X=1"])
    func spaceFirst(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("a value given to a name that holds a secret", arguments: [
        "export GITHUB_TOKEN=abc123",
        "API_KEY=abc123 ./deploy.sh",
        "export aws_secret_access_key=abc123",
        "DB_PASSWORD=hunter2 make migrate",
        "export MY_PASS=hunter2",
        "export PASSWD=hunter2",
        "APIKEY=abc123 node app.js",
        "export AWS_ACCESS_KEY=abc123",
        "PRIVATE_KEY=abc123 ./sign",
        "export GOOGLE_CREDENTIAL=abc123",
        "AUTH=abc123 ./run",
        "export githubToken=abc123",
        "PGPASSWORD=hunter2 psql -h db.example.com -U ann shop",
        "MYSQL_PWD=hunter2 mysql -u ann shop",
        "docker run -e POSTGRES_PASSWORD=hunter2 postgres",
        "kubectl create secret generic db --from-literal=password=hunter2",
        "mvn deploy -Dpassword=hunter2",
        "curl 'https://example.com/api?user=ann&api_key=abc123'",
        "curl -d '{\"username\":\"ann\",\"password\":\"hunter2\"}' https://example.com/login",
        "set -gx GITHUB_TOKEN abc123",
        "setenv TOKEN abc123",
        "aws configure set aws_secret_access_key abc123",
        "npm config set //registry.npmjs.org/:_authToken abc123",
    ])
    func secretNames(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("an option that takes a secret, given one", arguments: [
        "app --password=hunter2",
        "app --password hunter2",
        "app --passwd hunter2",
        "app --pass hunter2",
        "app --token abc123",
        "app --secret abc123",
        "app --api-key abc123",
        "app --apikey abc123",
        "app --auth ann:hunter2",
        "app --client-secret abc123",
        "gpg --passphrase hunter2 -d notes.gpg",
        "keytool -list -keystore store.jks -storepass changeit",
        "openssl enc -aes-256-cbc -pass pass:hunter2 -in notes.txt",
    ])
    func secretOptions(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("each tool's own way of taking a password on the command line", arguments: [
        "mysql -u ann -phunter2 shop",
        "mysqldump -phunter2 shop",
        "/usr/local/bin/mariadb -u ann -phunter2",
        "ssh alpha mysql -u ann -phunter2",
        "sshpass -p hunter2 ssh ann@alpha",
        "sshpass -phunter2 ssh alpha",
        "htpasswd -b .htpasswd ann hunter2",
        "htpasswd -cb .htpasswd ann hunter2",
        "curl -u ann:hunter2 https://example.com",
        "curl --user=ann:hunter2 https://example.com",
        "redis-cli -a hunter2 ping",
        "mongosh -u ann -p hunter2",
        "zip -P hunter2 out.zip notes.txt",
        "7z a -phunter2 out.7z notes.txt",
        "ssh-keygen -t ed25519 -N hunter2 -f key",
        "docker login -u ann -p hunter2 registry.example.com",
        "http -a ann:hunter2 GET example.com",
    ])
    func toolPasswords(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("a credential header", arguments: [
        "curl -H 'Authorization: Bearer abc123' https://example.com",
        "curl -H \"X-Api-Key: abc123\" https://example.com",
        "curl --header 'authorization: token abc123' https://example.com",
        "curl --header='Authorization: Basic abc123' https://example.com",
        "curl -H 'PRIVATE-TOKEN: abc123' https://gitlab.example.com/api/v4/projects",
        "curl -HAuthorization:abc123 https://example.com",
        "curl -H Authorization: Bearer abc123 https://example.com",
        "curl -H 'Cookie: session=abc123' https://example.com",
        "http GET example.com Authorization:'Bearer abc123'",
    ])
    func headers(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("a password in a URL", arguments: [
        "git clone https://ann:hunter2@example.com/repo.git",
        "psql postgres://ann:hunter2@db.example.com/shop",
        "psql \"postgresql://ann:hunter2@db.example.com:5432/shop?sslmode=require\"",
        "redis-cli -u redis://:hunter2@192.0.2.10:6379",
    ])
    func urlPasswords(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("a token recognisable by its form, wherever it stands", arguments: [
        Fake.github, Fake.githubFineGrained, Fake.gitlab, Fake.aws, Fake.awsSession, Fake.slack, Fake.apiKey,
        Fake.stripe, Fake.npm, Fake.huggingFace, Fake.google, Fake.jwt,
    ])
    func tokens(_ token: String) {
        #expect(Secrets.mayHoldSecret("echo \(token)"))
        #expect(Secrets.mayHoldSecret("git remote set-url origin https://\(token)@example.com/ann/repo.git"))
        #expect(Secrets.mayHoldSecret("export X=\"\(token)\""))
        #expect(Secrets.mayHoldSecret("curl -H \"Authorization:\(token)\" https://example.com"))
    }

    @Test("a private key block, and a password piped or written into a tool that reads it", arguments: [
        "echo '\(Fake.privateKey)' > key",
        "echo '\(Fake.pgpPrivateKey)' | gpg --import",
        "echo hunter2 | sudo -S apt update",
        "printf '%s\\n' hunter2 | sudo -S -u ann true",
        "echo hunter2 | sudo -kS true",
        "echo hunter2 | passwd --stdin ann",
        "echo 'ann:hunter2' | chpasswd",
        "sudo -S true <<< hunter2",
    ])
    func keysAndInput(_ command: String) {
        #expect(Secrets.mayHoldSecret(command))
    }

    @Test("ordinary commands, including ones that only mention a secret, stay", arguments: [
        // The coordinating session's list.
        "git push origin main",
        "ssh ann@alpha",
        "ssh -p 2222 alpha",
        "scp file alpha:/tmp/",
        "docker run -p 8080:80 nginx",
        "psql -h db.example.com -U ann -d shop",
        "mysql -u ann -p",
        "mysql -P 3306 -h db",
        "curl -H 'Accept: application/json' https://example.com",
        "export PATH=$PATH:/opt/bin",
        "export EDITOR=vim",
        "PASSWORD_STORE_DIR=~/x pass show",
        "git commit -m \"fix token parsing\"",
        "kubectl get secrets",
        "cat ~/.ssh/id_ed25519.pub",
        // Prompting forms, empty values, and switches.
        "mysql -u ann -p shop",
        "sudo -S apt update",
        "export TOKEN=",
        "TOKEN=\"\" ./run",
        "htpasswd -c .htpasswd ann",
        "ssh-keygen -t ed25519 -N '' -f key",
        "ssh -o PasswordAuthentication=no alpha",
        "TOKENIZERS_PARALLELISM=false python train.py",
        "ansible-playbook site.yml --ask-pass",
        "ansible-playbook --ask-become-pass site.yml",
        "gh auth login --with-token < token.txt",
        "docker login --username ann --password-stdin registry.example.com",
        "echo y | sudo pacman -S vim",
        // Where a secret is, or what it is called: not the secret.
        "export SSH_AUTH_SOCK=~/.ssh/agent.sock",
        "export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials",
        "MYSQL_ROOT_PASSWORD_FILE=/run/secrets/db docker compose up",
        "export PASSWORD_STORE_CLIP_TIME=45",
        "aws secretsmanager get-secret-value --secret-id prod/db",
        "git config --global credential.helper osxkeychain",
        "openssl enc -d -in notes.enc -pass env:PASSPHRASE",
        // The words alone.
        "git commit -m \"auth: fix the login\"",
        "kubectl describe secret db-password",
        "unset GITHUB_TOKEN",
        "echo $GITHUB_TOKEN",
        "export GIT_AUTHOR_NAME=ann",
        "grep -r 'password=' .",
        "git clone https://ann@example.com/repo.git",
        "scp notes.txt auth.example.com:/tmp/",
        "",
    ])
    func ordinary(_ command: String) {
        #expect(!Secrets.mayHoldSecret(command))
    }

    /// An optimised build checks 60,000 of these in about 55 ms, under a microsecond each
    /// (2026-11-06, this Mac). A debug build under test is ten times slower, and slower again with
    /// other builds running, so a fixed time measures the machine, not the filter. It is measured
    /// instead against the least any filter must do with the same commands at the same moment,
    /// reading each one's bytes into words, best of three each: a regular expression built per
    /// call or a quadratic step fails it, a busy machine does not.
    @Test("costs a small multiple of reading each command's words, for every command and every imported line")
    func speed() {
        let sample = [
            "git status", "git commit -m \"change the café's menu\" && make test", "ls -la ~/src/shop",
            "docker run --rm -p 8080:80 -e EDITOR=vim nginx:latest", "ssh -p 2222 ann@alpha.example.com",
            "export GITHUB_TOKEN=abc123", "curl -H 'Accept: application/json' https://example.com/api?q=1",
            "kubectl get pods -n shop -o wide | grep -v Running", "cd ~/src/shop && npm run build",
        ]
        let commands = (0 ..< 30_000).map { sample[$0 % sample.count] + " \($0)" }
        let clock = ContinuousClock()
        var flagged = 0
        var words = 0
        var filtering = Duration.seconds(1_000), reading = Duration.seconds(1_000)
        for _ in 0 ..< 3 {
            filtering = min(filtering, clock.measure { flagged = commands.count(where: Secrets.mayHoldSecret) })
            reading = min(reading, clock.measure { words = wordsCounted(commands) })
        }
        #expect(flagged == (0 ..< 30_000).count(where: { $0 % sample.count == 5 }), "only the token export")
        #expect(words > commands.count)
        #expect(filtering < reading * Self.filteringAllowance, "filtered in \(filtering), read into words in \(reading)")
    }

    /// How many times the cost of reading the commands into words the filter may take: one and a
    /// half times the most measured in a debug build (59–65, steady within 5% at load averages of
    /// 60 to 110, 2026-11-06). A regular expression compiled for each rule on each call measures
    /// well over it; one alone, about 80, does not, so this guards against a several-fold slowdown,
    /// and the optimised timing above is the measure of the filter's speed.
    private static let filteringAllowance = 100
}

/// The least a filter reads: each command's bytes, split into words at spaces. Counts the words.
nonisolated private func wordsCounted(_ commands: [String]) -> Int {
    var words = 0
    for var command in commands {
        command.withUTF8 { bytes in
            var inWord = false
            var index = 0
            while index < bytes.count {
                if bytes[index] == 0x20 {
                    inWord = false
                } else if !inWord {
                    inWord = true
                    words += 1
                }
                index += 1
            }
        }
    }
    return words
}
