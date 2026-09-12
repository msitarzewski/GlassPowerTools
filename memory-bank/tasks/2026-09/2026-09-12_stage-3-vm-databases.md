# Stage 3 — W-vm: real MySQL and PostgreSQL on the test VM

Worker `W-vm`. 2026-09-11, updated 2026-09-12. **Status: provisioning complete; both live round
trips pass against this VM** —
PostgreSQL on its first run, MySQL cold over plaintext. Two databases per engine: a write-protected
fixture and a disposable scratch. One open item, **D13**, is in our TLS API rather than on this VM
and is a Stage 3 backlog item. **One investigation is left open**: two ~10s tunnel failures that
neither tested hypothesis explains. Both engines are
installed, reachable on the LAN, seeded with one shared logical schema, and reachable as
least-privilege users whose limits were proven by denial tests. Not committed (coordinator commits).

Authorization: the user approved installing the engines with sudo
([the Stage 3 plan](2026-09-12_stage-3-database-plan.md), "Verification"). Root/superuser was used
**for provisioning only**. Nothing in the app or the test suite uses a root account.

## The host

`192.0.2.6`, Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic, aarch64, one interface
`enp0s5 192.0.2.6/24` (Parallels host-only bridge; the Mac appears to the VM as `192.0.2.2`).
Reachable from this Mac as the SSH aliases `scratch` (root, used for provisioning) and `scratch-m`
(user `michael`). `ufw status` → **inactive**, so no firewall rule was needed or added for 3306/5432;
if ufw is ever enabled, both ports must be allowed from `192.0.2.0/24`.

## What was installed

`mysql-server` on Ubuntu 26.04 is **real Oracle MySQL, not MariaDB** — worth recording because the
capability supports both and the plan left it open.

| Package | Version |
|---|---|
| `mysql-server` | `8.4.11-0ubuntu0.26.04.1` (`mysqld Ver 8.4.11 … for Linux on aarch64`) |
| `mysql-server-core` / `mysql-client` / `mysql-client-core` | `8.4.11-0ubuntu0.26.04.1` |
| `mysql-common` | `5.8+1.1.1ubuntu2` |
| `postgresql` (metapackage) | `18+290ubuntu1` |
| `postgresql-18`, `postgresql-18-jit`, `postgresql-client-18` | `18.6-0ubuntu0.26.04.1` (`psql (PostgreSQL) 18.6`) |
| `postgresql-common`, `postgresql-client-common` | `290ubuntu1` |

Install, over `ssh scratch`:

```sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install mysql-server postgresql
```

Both units came up on their own: `systemctl is-active mysql postgresql@18-main` → `active active`.

## Configuration changed

Both original files were copied to `<name>.gpt-bak` next to the original before editing.

**`/etc/mysql/mysql.conf.d/mysqld.cnf`** — one line, 31:

```diff
-bind-address		= 127.0.0.1
+bind-address		= 0.0.0.0
```

`mysqlx-bind-address` (line 32) was deliberately **left at `127.0.0.1`**: the X protocol on 33060 is
not used by the capability and should not be exposed.

**`/etc/postgresql/18/main/postgresql.conf`** — one line, 60:

```diff
-#listen_addresses = 'localhost'		# what IP address(es) to listen on;
+listen_addresses = '*'		# GPT: was localhost (commented default)
```

**`/etc/postgresql/18/main/pg_hba.conf`** — three lines appended after line 132:

```
# Glass Power Tools Stage 3 database tests: scram-sha-256 from the Parallels host subnet
host	gpt_test,gpt_scratch	gpt_test	192.0.2.0/24	scram-sha-256
```

Scoped to two named databases, one user, one subnet — `gpt_scratch` was added to the db field when
the fixture and scratch databases were split; the user and address fields were not touched.
`systemctl reload postgresql` applies it. `SHOW password_encryption` is already
`scram-sha-256` on PostgreSQL 18, so no change was needed there.

After `systemctl restart mysql postgresql`:

```
LISTEN 0 151       0.0.0.0:3306   0.0.0.0:*  users:(("mysqld",…))
LISTEN 0 200       0.0.0.0:5432   0.0.0.0:*  users:(("postgres",…))
LISTEN 0 70      127.0.0.1:33060  0.0.0.0:*  users:(("mysqld",…))   ← X protocol, still local-only
```

## Databases and users

Passwords were generated on the Mac with `openssl rand -base64 24` (32 characters after `+/` were
folded to `A/a` so the value is alphanumeric and safe to embed in SQL and connection strings), written
straight into the env file, and fed to the servers on **stdin** — so they never appeared in a shell
history, in `ps` output on the VM, or in this note. `<generated>` below stands for those values.

### MySQL

Run as root over `ssh scratch`; root on this install is `auth_socket`, so there is no MySQL root
password to leak in the first place.

```sql
CREATE DATABASE IF NOT EXISTS gpt_test    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS gpt_scratch CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'gpt_test'@'%' IDENTIFIED BY '<generated>';
ALTER USER 'gpt_test'@'%' IDENTIFIED BY '<generated>';
GRANT SELECT, INSERT, UPDATE, DELETE ON gpt_test.* TO 'gpt_test'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, REFERENCES
    ON gpt_scratch.* TO 'gpt_test'@'%';
FLUSH PRIVILEGES;
```

`SHOW GRANTS FOR 'gpt_test'@'%'`, verbatim:

```
GRANT USAGE ON *.* TO `gpt_test`@`%`
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, REFERENCES, INDEX ON `gpt_scratch`.* TO `gpt_test`@`%`
GRANT SELECT, INSERT, UPDATE, DELETE ON `gpt_test`.* TO `gpt_test`@`%`
```

Authentication plugin: `caching_sha2_password` (the 8.4 default; `mysql_native_password` is
`DISABLED` on this server and was **not** enabled — see the cold-cache measurements below).

`information_schema` needs no grant: MySQL exposes it to every user, filtered to objects the user has
privileges on, which is exactly the schema browser's view.

### PostgreSQL

```sql
CREATE ROLE gpt_test LOGIN;
ALTER ROLE gpt_test WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
    PASSWORD '<generated>';
CREATE DATABASE gpt_test OWNER postgres;
-- then, connected to gpt_test:
REVOKE ALL ON DATABASE gpt_test FROM PUBLIC;
GRANT CONNECT ON DATABASE gpt_test TO gpt_test;
GRANT USAGE ON SCHEMA public TO gpt_test;    -- USAGE only: no CREATE in the fixture database
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO gpt_test;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gpt_test;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gpt_test;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO gpt_test;

-- and the scratch database, where the live test creates and drops its own tables:
CREATE DATABASE gpt_scratch OWNER postgres;
-- connected to gpt_scratch:
REVOKE ALL ON DATABASE gpt_scratch FROM PUBLIC;
GRANT CONNECT ON DATABASE gpt_scratch TO gpt_test;
GRANT USAGE, CREATE ON SCHEMA public TO gpt_test;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gpt_test;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO gpt_test;
```

The seeded tables stay owned by `postgres` and `gpt_test` holds DML on them and nothing more —
`USAGE` on the schema, no `CREATE`. Its ability to make tables lives entirely in `gpt_scratch`.
Resulting privileges:

```
pg_database.datacl, gpt_test    : {postgres=CTc/postgres,gpt_test=c/postgres}   (c = CONNECT only)
pg_database.datacl, gpt_scratch : {postgres=CTc/postgres,gpt_test=c/postgres}
pg_namespace.nspacl, gpt_test/public    : {…, gpt_test=U/pg_database_owner}    (USAGE only)
pg_namespace.nspacl, gpt_scratch/public : {…, gpt_test=UC/pg_database_owner}   (USAGE + CREATE)
information_schema.table_privileges in gpt_test, grantee gpt_test:
    members  DELETE,INSERT,SELECT,UPDATE
    teams    DELETE,INSERT,SELECT,UPDATE
```

**In `gpt_scratch` it is `CREATE` on `public`, not a schema of its own.** An owned schema would be
tighter still, but `postgres17LiveRoundTrip` creates its table unqualified and then asserts
`tables(in: "public").contains(table)` (`Tests/GlassDBKitTests/GlassDBKitTests.swift:670`). A schema
named `gpt_test` would win the default `search_path` (`"$user", public`), silently divert the
`CREATE TABLE`, and break that assertion.

`pg_catalog` needs no grant — it is world-readable except for the protected tables, and
`pg_authid` is correctly denied (below). The sequence grants are the one thing granted beyond plain
DML; they exist so an `INSERT` that omits the identity column works, and they confer nothing outside
the two fixture sequences.

**How these grants got to their final shape.** Three passes, recorded because the middle one is the
reason the topology looks the way it does. (1) DML only on a single `gpt_test`. (2) `CREATE`, `DROP`,
`INDEX`, `REFERENCES` added to `gpt_test` so the live round-trip tests could create and drop a table —
which, on MySQL, also handed the user `DROP DATABASE` over the fixture. (3) The split above: the
fixture reverted to DML only, and the create/drop privileges moved to `gpt_scratch`.

Nothing was ever widened for the schema browser or the record editor. Those metadata reads worked
under the original DML-only grants and were verified as the test user before any widening, and they
still work now that the fixture database is back to DML only.

## The seeded schema

One logical schema on both engines, deterministic (fixed ids, fixed timestamps), kept reproducible at
`memory-bank/tasks/2026-09/fixtures/gpt_test_schema-mysql.sql` and
`…-postgres.sql`. Two files rather than one because the identity-column syntax is not portable
(`AUTO_INCREMENT` vs `GENERATED BY DEFAULT AS IDENTITY`); everything else is line-for-line the same,
including the data. **The fixtures contain DDL and rows only — no credentials.**

`teams` (10 rows) — `id` PK identity, `name` varchar(64) NOT NULL UNIQUE, `active` boolean,
`budget` numeric(12,2), `created_at` timestamp, `notes` text **nullable** (3 rows are NULL).

`members` (10 rows) — `id` PK identity, `team_id` integer NOT NULL
**FK → `teams(id)`** (`members_team_id_fkey`, indexed), `full_name` varchar(128),
`email` varchar(128) **nullable** (3 NULL), `is_lead` boolean, `hourly_rate` numeric(8,2)
**nullable** (1 NULL), `joined_at` timestamp.

That covers integer, varchar, text, boolean, timestamp, numeric and nullability, plus the one
foreign key Stage 3's FK navigation needs. Both identity counters were reset to hand out **11** next,
so the two engines stay in step after the round-trip tests below.

## Where the credentials live

`~/.config/gpt-db-test.env` on the **Mac**, `-rw-------` (0600), outside the repository, alongside
`~/.config/gpt-db-test-mysql-ca.pem` (also 0600). Keys:

| Variable | Value |
|---|---|
| `GPT_DB_TEST_HOST` | `192.0.2.6` |
| `GPT_DB_TEST_MYSQL_PORT` / `_DB` / `_USER` / `_PASSWORD` | `3306` / `gpt_test` / `gpt_test` / withheld |
| `GPT_DB_TEST_MYSQL_SCRATCH_DB` | `gpt_scratch` |
| `GPT_DB_TEST_MYSQL_CA_PATH` | `~/.config/gpt-db-test-mysql-ca.pem` (absolute in the file) |
| `GPT_DB_TEST_MYSQL_TLS_SERVER_NAME` | `MySQL_Server_8.4.11_Auto_Generated_Server_Certificate` |
| `GPT_DB_TEST_PG_PORT` / `_DB` / `_USER` / `_PASSWORD` | `5432` / `gpt_test` / `gpt_test` / withheld |
| `GPT_DB_TEST_PG_SCRATCH_DB` | `gpt_scratch` |

`GPT_DB_TEST_MYSQL_CA_PATH` is the name the test's TLS block reads. A test run sources the file
with:

```sh
set -a; . ~/.config/gpt-db-test.env; set +a
```

## Why there are two databases per engine

The first cut gave the test user `DROP` on `gpt_test` so the live round-trip tests could drop their
own table. In MySQL, `GRANT DROP ON gpt_test.*` **also permits `DROP DATABASE gpt_test`** —
database-scoped `DROP` has no finer grain, and the tests use random table names so per-table grants
are not an option. That is not theoretical: the denial run issued `DROP DATABASE gpt_test` expecting
a refusal and **the database was dropped.** It was recreated and reseeded on the spot, the grants
survived (they are recorded against the name and reattach), and the seed verified back at 10 + 10.

The coordinator's fix, applied here: **split the fixture from the scratch space.**

| Database | Contents | MySQL privileges | PostgreSQL privileges |
|---|---|---|---|
| `gpt_test` | the seeded `teams`/`members` fixture | `SELECT, INSERT, UPDATE, DELETE` | DML on the seeded tables; `USAGE` on `public`, **no `CREATE`** |
| `gpt_scratch` | empty; the tests' `gpt_live_*` tables | `SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, REFERENCES` | DML plus `USAGE, CREATE` on `public` |

`DROP DATABASE gpt_scratch` is still possible and is accepted: everything in it is ephemeral and
nothing recreates from a fixture. `DROP DATABASE gpt_test` is now refused, and so is dropping or
creating any table in it. PostgreSQL never had the exposure — dropping requires ownership there and
the seed is owned by `postgres` — but its privileges were split the same way so the two engines
behave alike.

Reseed of `gpt_test`, should it ever be needed, on `ssh scratch`:

```sh
mysql --batch -e "DROP DATABASE IF EXISTS gpt_test; CREATE DATABASE gpt_test \
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
mysql --batch gpt_test < /root/gpt_test_schema-mysql.sql
mysql --batch -e "ALTER TABLE gpt_test.teams AUTO_INCREMENT = 11; \
                  ALTER TABLE gpt_test.members AUTO_INCREMENT = 11;"
```

(The same fixture is in the repo at `fixtures/gpt_test_schema-mysql.sql`; `/root/` holds the copy that
was loaded. DDL and rows only.)

## MySQL TLS: the pinned-CA path, measured

`/var/lib/mysql/ca.pem` was copied to `~/.config/gpt-db-test-mysql-ca.pem` on the Mac (0600) and is
pointed at by `GPT_DB_TEST_MYSQL_CA_PATH`. Both auto-generated certificates are valid
`Sep 12 2026 – Sep 9 2036`, and **neither carries a `subjectAltName` at all** (`openssl x509 -noout
-ext subjectAltName` → `No extensions in certificate`, for the CA and the server cert alike):

| Certificate | Subject |
|---|---|
| CA | `CN=MySQL_Server_8.4.11_Auto_Generated_CA_Certificate` |
| server | `CN=MySQL_Server_8.4.11_Auto_Generated_Server_Certificate` |

So the only name that can verify is the server certificate's CN, and
`GPT_DB_TEST_MYSQL_TLS_SERVER_NAME` is set to it verbatim:
`MySQL_Server_8.4.11_Auto_Generated_Server_Certificate`. Measured against the running server, each on
a **cold** `caching_sha2_password` cache (`FLUSH PRIVILEGES` first):

| Attempt from the Mac | Result |
|---|---|
| `--ssl-mode=VERIFY_CA --ssl-ca=<CA>` (chain verified, hostname not checked) | **succeeded** |
| `--ssl-mode=VERIFY_IDENTITY --ssl-ca=<CA>` against `192.0.2.6` | **failed** — `ERROR 2026: certificate verify failed`. Expected: no SAN, and the CN is not the address |
| `openssl s_client … -verify_hostname MySQL_Server_8.4.11_Auto_Generated_Server_Certificate` | **`Verification: OK`, return code 0** — hostname verification falls back to the CN when the cert carries no SAN |
| `openssl s_client … -verify_hostname 192.0.2.6` | **failed** — `verify error:num=62:hostname mismatch` |

That last pair matters for reading the failure below correctly: at the protocol level, CN fallback
**works** — OpenSSL matches that CN against a cert with no SAN and returns `Verification: OK`. The
name is not the problem.

### What NIOSSL does with it — the real gap (D13, a defect)

The coordinator then ran the pinned-CA path with this CA and this exact CN. **NIOSSL refuses before
it ever contacts the server:**

```
NIOSSLExtraError.serverHostnameImpossibleToMatch: The server hostname
MySQL_Server_8.4.11_Auto_Generated_Server_Certificate cannot be matched
due to containing non-DNS characters
```

So the gap is *not* "the CN cannot match" — the OpenSSL result above disproves that. It is that
NIOSSL rejects the **string** as a hostname, because it contains characters that cannot appear in a
DNS name, and so never reaches a comparison. A stricter rule than OpenSSL's, applied earlier. Same
size of gap, different gap, and a different fix.

Compounding it: `.requiredCertificates(_, serverName:)` always sets
`certificateVerification = .fullVerification`, so **pinning a CA while skipping the hostname check —
MySQL's own `VERIFY_CA`, as opposed to `VERIFY_IDENTITY` — is not expressible in our API.** A stock
MySQL install, whose auto-generated certificate has no SAN and a non-DNS CN, is exactly the case that
needs it.

**The connection fails loudly. There is no silent fallback** — an earlier revision of this note
claimed there was, and that was wrong. `DatabaseSessionManager.swift:238-243` selects the policy once
from `config.useTLS` and there is no retry path anywhere; a TLS failure throws and reaches the user as
a failure. (The two `.disabled` sites at `:106` and `:234` are SQLite, a local file with no transport
to secure — not a downgrade.) So the honest-status rule is not at stake here.

**The deeper gap is that there is no way to supply a CA at all.** `grep -rn requiredCertificates
../glassdb/glassdb/` returns **nothing**: the app only ever constructs `.requiredSystemTrust` or
`.requiredSystemTrustForHost` (`DatabaseSessionManager.swift:238-243`), and the connection form offers
a "Use TLS" toggle (`ConnectionFormView.swift:613`, `:964`) but no certificate import. The pinned-CA
path exists in the engine — `DatabaseProtocol.swift:85`, handled in `MySQLAdapter.swift:112` and
`PostgreSQLAdapter.swift:76` — and is reachable **only from tests**. Verified against the current
checkout by this worker after the coordinator raised it.

Since a default MySQL **and** a default PostgreSQL both generate self-signed certificates, the
practical position is that a user who ticks "Use TLS" against a stock server gets a hard failure with
no remedy inside the app. The engine has had the capability all along; the app never exposed it.

**Severity: a defect, not a blocker** — plaintext authentication is safe here (the RSA result below),
so nothing is stopped. But closing D13 needs **both** a CA-only verification mode and a way to import
or point at a certificate, which makes it a parity-plus item for Stage 3's own backlog beside the D9
closures, not merely a note for the wave-4 reviewer. Recorded by the coordinator in
`memory-bank/decisions.md`.

**The VM keeps the default certificate on purpose.** No regeneration, no added DNS name, no SAN — it
is the awkward, real-world certificate our users will meet, and working around it here would hide
the defect rather than close it.

## `caching_sha2_password`: what the server offers, cold

Re-measured after `FLUSH PRIVILEGES` each time, because the RSA result in this note's first revision
was taken on a warm cache and proved nothing.

| Path | Cold-cache result |
|---|---|
| plaintext, no server public key | **refused** — `ERROR 2061: … Authentication requires secure connection.` |
| plaintext **with `--get-server-public-key`** (RSA key exchange) | **succeeded** |
| TLS (`--ssl-mode=REQUIRED`, and `VERIFY_CA` with the pinned CA) | **succeeded** |

So the server **does** offer the RSA key exchange. `mysql_native_password` remains `DISABLED` and was
deliberately not enabled — that would be a security downgrade to work around a client limitation.

**And our client uses it. Measured, cold, by the coordinator: `mysql8LiveRoundTrip` passed over
plaintext with no TLS, in 0.091s, on the first `gpt_test` connection after a `FLUSH PRIVILEGES` that
this worker performed as `root@localhost` and then did not follow with any connection of its own.**
mysql-nio implements `caching_sha2_password` full authentication over the RSA public-key exchange —
it requests the server's key and encrypts with `_RSA.Encryption.PublicKey(pemRepresentation:)` at
`MySQLConnectionHandler.swift:326-351`.

The care over the cold cache was the point: every verification run, including this worker's own,
re-warms the cache and would have reproduced the fast-path illusion. It also mattered more than the
question looked. `_RSA.Encryption` comes from `_CryptoExtras` in swift-crypto, and dropping Citadel
from the engine moved the graph from glassdb's swift-crypto 3.15.1 to this repo's 4.5.2 — so this was
**the first time mysql-nio's RSA path had ever run against swift-crypto 4.5.2**, a combination the
port created and glassdb never had. It compiled from the start; compiling was never the question.

**Consequence: TLS is not mandatory for MySQL.** That is what keeps the certificate gap below small.

## Coexistence and naming

The fixture and the tests' temporary tables now live in **different databases**, so they cannot
collide. The naming rule still holds and is worth keeping: the tests name their table
`gpt_live_<uuid without dashes>` (`GlassDBKitTests.swift:549` and `:638`), while the seed uses only
`teams` and `members`. **Any future fixture must stay clear of the `gpt_live_*` prefix**, and any
future test table must stay clear of `teams` and `members` — the separation should survive someone
later pointing both at one database.

## Three things found in the live tests, and where each landed

Found while reading `Tests/GlassDBKitTests/GlassDBKitTests.swift` to match the grants to real usage.
The coordinator owns that file; all three are resolved. **None was worked around by loosening the
server.**

1. **`mysql8LiveRoundTrip` hardcoded the database name `"glassdb_test"`** in four assertions —
   `rowCount(table:database:)` (`:580`), `tables(in:)` (`:581`), `columns(in:database:)` (`:582`) and
   `showCreateTable(_:database:)` (`:583`) — while the connection opened
   `LiveDatabaseEnvironment.mysqlDatabase`. No such database exists and the user has no privileges on
   it, so it would have failed against any server. Fixed by the coordinator. The PostgreSQL test
   never had this problem: it passes `"public"`, a schema, which is correct there.
2. **The MySQL connection opens with `tlsPolicy: .disabled`** (`:547`). Flagged here as a cold-cache
   hazard — **and the measurement cleared it**: mysql-nio authenticates over plaintext via the RSA
   key exchange on a cold cache, so this is correct as written. See the RSA result below.
3. ~~The optional TLS block connects to a hardcoded `127.0.0.1:33306` as `glassdb_test`.~~
   **Struck — this worker read a stale copy of the test and reported an already-fixed defect as
   open.** The coordinator had rewired the block before that report: it reads
   `LiveDatabaseEnvironment.mysqlCAPath` (`GPT_DB_TEST_MYSQL_CA_PATH`, the name published here) and
   targets this host and `gpt_scratch`. That block being **live** is how the NIOSSL failure above
   surfaced at all.

## Open: two ~10s tunnel failures, unexplained

**Status: open.** Not resolved, and deliberately not closed as "it passes now" — it passed before, too.

The coordinator saw `MySQL over a real SSH forward` fail twice at almost exactly 10s with
`Server error: Got timeout reading communication packets`, then pass afterwards. Two hypotheses were
tested against this VM and **both were refuted**; the failure remains unexplained.

### Read this before grepping the error log

**At `log_error_verbosity=2` — the Ubuntu default this server shipped with — MySQL does not write the
`MY-010914` aborted-connection notes at all.** So the phrase never appeared in
`/var/log/mysql/error.log`, the whole file was 27 lines ending at `03:17:11Z`, and **zero** lines fell
in the failure window. That absence is an artefact of verbosity, **not** evidence that nothing
happened. Anyone who greps this log for a past failure and finds nothing should stop there and check
the verbosity first.

The client saw it because the server still sends the reason in an `ERR` packet even when it logs
nothing: mysql-nio formats `MySQLError.server(ERR_Packet)` as `"Server error: …"`
(`MySQLError.swift:40`). Absence in the log and presence on the wire are **the same event seen from
two places.**

`log_error_verbosity` is now **3**, set with `SET GLOBAL` + `SET PERSIST` so it survives restart:

```sql
SET GLOBAL log_error_verbosity = 3; SET PERSIST log_error_verbosity = 3;
-- revert: SET GLOBAL log_error_verbosity = 2; RESET PERSIST log_error_verbosity;
```

It works — within a minute of the change, four notes landed at `05:43:44Z`: three
`Got an error reading communication packets` and one **`Bad handshake`**.

### Those notes are ours, expected, and benign — do not chase them

They are our own TLS capability probe. `MySQLAdapter.serverAdvertisesTLS` opens a raw TCP connection,
reads **only the unauthenticated greeting** to see whether the server advertises `CLIENT_SSL`, and
closes without ever authenticating — so that mysql-nio's opportunistic TLS can never send an auth
response to a server that does not offer encryption. A deliberate fail-closed design. Verified in the
current checkout at `Packages/GlassDBKit/Sources/GlassDBKit/MySQLAdapter.swift:77-93`, called from
`:45`. From MySQL's side it is indistinguishable from a client that connected and gave up, which is
exactly `Bad handshake` / `Got an error reading communication packets`.

It runs only when `tlsPolicy.isRequired` — in a full-suite run, the `.requiredSystemTrust` negative
tests (`GlassDBKitTests.swift:467`, `:615`) and the pinned-CA case (`:641`) — three or four probes in
quick succession, which matches four notes inside 12ms.

**Consequence for the counters: a meaningful slice of `Aborted_connects` is this probe, by design.**
The baseline diff will drift upward on every suite run that exercises a TLS-required policy, with no
fault behind it. Do not read counter growth alone as evidence of a problem.

### The reason string is the discriminator — this is how to find the real failure

| Reason string | Source |
|---|---|
| `Got an error reading communication packets`, `Bad handshake` | **the TLS capability probe.** Expected, benign, frequent |
| **`Got timeout reading communication packets`** | **the failure under investigation.** This is the one to look for |

The two are different reason paths, so probe noise **will not mask a recurrence**. Anyone grepping
this log later will see a pile of aborted-connection notes: match the reason string before concluding
anything, rather than assuming the pile is the bug.

### Three distinct things on this path fail at ten seconds

Told apart only by their strings, which is why this table exists at all:

| Signature | Source |
|---|---|
| `Got timeout reading communication packets` — server `ERR` packet, surfaced by the client as `Server error: …` | **the open bug** |
| `Got an error reading communication packets` / `Bad handshake` — server log only | our fail-closed TLS probe. Expected, benign |
| `Timed out waiting for the MySQL server greeting.` — client-side string, no server `ERR` | the probe's **own** 10s timers: `connectTimeout(.seconds(10))` and a scheduled greeting timeout (`MySQLAdapter.swift:80`, `:86`) |

The third is not a candidate for the open bug — that one's text arrived over the wire from MySQL, so
it cannot have come from a client-side timer. It is recorded so that a future 10s failure is matched
to the right one of three rather than the nearest one.

### Probe plus tunnel: a cost, not a defect

When TLS is required over a tunnel, **two forwarded connections open in sequence — probe, then the
real one.** Both are correctly targeted, and the arrangement was checked rather than assumed
(`Sources/GlassDatabase/DatabaseSessionManager.swift:216-236`):

- The transport plan sets `databaseHost = "127.0.0.1"` and `databasePort = tunnelLocalPort`, and the
  probe is called with exactly those — so it goes **through the forward** and tests the socket the
  session will actually use. The failure mode worth checking for — a probe testing the real host
  directly while the session connects through the tunnel, answering a question about the wrong
  socket — does not occur.
- The policy over a tunnel is `.requiredSystemTrustForHost(config.host)`, so the certificate is
  verified against **the machine's real name, not loopback** — the thing a tunnel implementation
  usually gets wrong, already right here, and commented as such in the source.

So: an extra forwarded connection per TLS-required tunnel session. A cost, not a defect, and not
implicated in the open failure.

Counter baseline for diffing, `2026-09-12T05:43:08Z`: `Aborted_connects 55`, `Aborted_clients 0`,
`Connections 210`, `Max_used_connections 4`, `Uptime 8920`. **Only the forward diff is meaningful** —
the cumulative `Aborted_connects` is mostly this worker's own denial tests and cold-auth refusals and
cannot isolate anything retrospectively.

### Hypothesis 1 — cold `caching_sha2_password` full auth fails over our SSH forward: **refuted**

Tested as a controlled A/B. This worker ran `FLUSH PRIVILEGES` as `root@localhost` at
`2026-09-12T05:39:28Z` and made no connection as `gpt_test` afterwards, so the coordinator's Swift
test was genuinely the first. **`MySQL over a real SSH forward` passed in 0.072s, cold, over
plaintext.** The OpenSSH control arm was therefore not run — with the experimental arm succeeding it
had nothing to prove.

A mechanism offered for this hypothesis was that a forwarded connection, arriving from `127.0.0.1`,
would occupy a *different* cache entry from the direct path. **That is wrong**, and it was corrected
before the experiment ran: only one account exists, `gpt_test@%`, and MySQL keys the cache by
**matched account**, not client address. A forwarded connection matches the same account and shares
one entry, so cold means cold for both paths.

### Hypothesis 2 — contention between concurrent live suites: **proposed, unsupported**

Plausible in shape: W-capability's three tunnel tests each open a fresh `SSHTransport`, connect,
forward and tear down, and were running against this VM alongside the coordinator's runs while
W-local built. The bursts are visible in the journal. But the server's own counters do not support
it:

| Evidence, window `05:15Z–05:25Z` | Reading |
|---|---|
| `Max_used_connections = 4`, at `05:23:57Z` (inside the window) | peak **4** concurrent, against `max_connections = 151` |
| `Connection_errors_max_connections` / `_accept` / `_internal` | all **0** |
| sshd messages matching `maxstartups|throttl|refused|too many|drop|fatal|error:` | **0**, in the window and across the whole day |
| sshd accepts in the window | 50 total; busiest seconds **7** (`00:15:52` local) and **6** (`00:23:56`), against `MaxStartups 10:30:100` |
| `performance_schema.host_cache` for `192.0.2.2` | `SUM_CONNECT_ERRORS = 0`, `HOST_VALIDATED = YES` |

Concurrency happened — the `05:23:56–57Z` burst lines up exactly with `Max_used_connections_time` —
but it stayed inside every limit and neither daemon complained once. **Recorded as proposed and
unsupported by the server's own counters**, with the caveat that a *client-side* stall would leave no
server trace at verbosity 2 either, so this is "not supported", not "disproved".

### Ruled out: reverse-DNS resolver timeout

A strong-looking candidate, because `skip_name_resolve = 0` and the log shows
`IP address '192.0.2.2' could not be resolved` (`error.log:27`) — a 2×5s resolver timeout lands on
almost exactly 10s. **It is not this.** The reverse lookup fails in **6ms** (`getent hosts
192.0.2.2`, exit 2), and `performance_schema.host_cache` holds a validated entry for that IP, so
there is no per-connection resolver stall.

### What is actually established

`connect_timeout = 10` (`net_read_timeout = 30`), which is why the failures landed on ~10s: a round
trip that never completed, with the server giving up on schedule. The failure is real and came from
this VM's MySQL — the coordinator confirmed nothing listens on 3306 or 33306 on the Mac, so no local
server could have produced it, and the tunnel test connects to `forward.localPort` whose far end is
this VM. **Which side stalled is not established.** Verbosity 3 is armed to catch a recurrence.

## Verification

Every row below was run **from the Mac** as the least-privilege `gpt_test` user over the LAN, using
`/opt/homebrew/bin/mysql` (8.4 client) and `/opt/homebrew/opt/libpq/bin/psql` (18) — not on the VM.
The only commands run on the VM were provisioning and the seed load.

| Check | Engine | Result |
|---|---|---|
| TCP reachability, `nc -vz 192.0.2.6 <port>` | both | **succeeded** on 3306 and 5432 |
| Connect as `gpt_test`, `SELECT VERSION()` / `version()` | both | **passed** — MySQL `8.4.11-0ubuntu0.26.04.1`, PostgreSQL `18.6` |
| Identity is the test user, not a superuser | both | `CURRENT_USER()` → `gpt_test@%`; `current_user/current_database` → `gpt_test/gpt_test` |
| Connection is encrypted | both | MySQL `TLS_AES_128_GCM_SHA256`; PostgreSQL `TLSv1.3 / TLS_AES_256_GCM_SHA384` |
| `SELECT` joining `members` → `teams` across the FK | both | **passed**, identical 4-row result on both engines |
| Column metadata for the schema browser (`information_schema.columns`) | both | **passed**, 13 columns with types and nullability |
| FK metadata (`information_schema.KEY_COLUMN_USAGE` / `pg_catalog.pg_constraint`) | both | **passed**, `members_team_id_fkey → teams` on both |
| Record-editor round trip: INSERT → SELECT → UPDATE → DELETE, count back to 10 | both | **passed** |
| **Denial:** read another database (`mysql.user`) | MySQL | **denied** — `ERROR 1142: SELECT command denied to user 'gpt_test'@'192.0.2.2' for table 'user'` |
| **Denial:** `CREATE USER` | MySQL | **denied** — `ERROR 1227: … you need (at least one of) the CREATE USER privilege(s)` |
| **Denial:** `CREATE TABLE` in **another** database (`mysql.…`) | MySQL | **denied** — `ERROR 1142: CREATE command denied … for table 'should_not_exist'` |
| **Denial:** `GRANT ALL ON *.*` | MySQL | **denied** — `ERROR 1045: Access denied for user 'gpt_test'@'%'` |
| **Denial:** `CREATE TABLE` in the **fixture** database, after the split | MySQL | **denied** — `ERROR 1142: CREATE command denied … for table 'should_not_exist'` |
| **Denial:** `DROP TABLE members` in the fixture database, after the split | MySQL | **denied** — `ERROR 1142: DROP command denied … for table 'members'` |
| **Denial:** `DROP DATABASE gpt_test`, after the split | MySQL | **denied** — `ERROR 1044: Access denied for user 'gpt_test'@'%' to database 'gpt_test'`. (Before the split this **succeeded** — that is what prompted it) |
| Fixture DML still works after the split: INSERT → UPDATE → DELETE, count back to 10 | MySQL | **passed** |
| Visible databases | MySQL | only `gpt_scratch`, `gpt_test`, `information_schema`, `performance_schema` — no `mysql`, no `sys` |
| Live-test shape in **`gpt_scratch`**: `CREATE TABLE gpt_live_<uuid>` with `BIGINT PRIMARY KEY AUTO_INCREMENT`, `DECIMAL(40,18)`, `BLOB`, `BOOLEAN`; INSERT; `information_schema` lookup; `SHOW CREATE TABLE`; `DROP TABLE` | MySQL | **passed** as the `gpt_test` user |
| **Denial:** connect to the `postgres` database | PostgreSQL | **denied at pg_hba** — `FATAL: no pg_hba.conf entry for host "192.0.2.2", user "gpt_test", database "postgres"` |
| **Denial:** `CREATE ROLE` | PostgreSQL | **denied** — `ERROR: permission denied to create role` |
| **Denial:** `CREATE DATABASE` | PostgreSQL | **denied** — `ERROR: permission denied to create database` |
| **Denial:** `DROP TABLE members` (a seeded table it does not own) | PostgreSQL | **denied** — `ERROR: must be owner of table members` |
| **Denial:** `DROP DATABASE gpt_test` | PostgreSQL | **denied** — `ERROR: must be owner of database gpt_test` |
| **Denial:** `CREATE TABLE` in the **fixture** database, after the split | PostgreSQL | **denied** — `ERROR: permission denied for schema public` |
| **Denial:** read `pg_authid` (password hashes) | PostgreSQL | **denied** — `ERROR: permission denied for table pg_authid` |
| Fixture DML still works after the split: INSERT → UPDATE → DELETE, count back to 10 | PostgreSQL | **passed** |
| Live-test shape in **`gpt_scratch`**: `CREATE TABLE gpt_live_<uuid>` with `BIGSERIAL PRIMARY KEY`, `NUMERIC(40,18)`, `BYTEA`, `JSONB`, `BOOLEAN`; INSERT; `information_schema` lookup; `DROP TABLE` | PostgreSQL | **passed** as the `gpt_test` user |
| Connect to `gpt_scratch` through the widened `pg_hba` line | PostgreSQL | **passed**, same user and subnet |
| Seed still intact after every denial, split and round-trip run | both | **passed** — 10 + 10 on both engines, FK join unchanged |
| `FLUSH PRIVILEGES` as `root@localhost`, with **no** following connection from this worker, so the coordinator's next connection was genuinely the first | MySQL | **done** `2026-09-12T03:36:20Z`, rc=0 |

### Runs by the coordinator against this server

Recorded here because they are the proof the provisioning existed for. Measured by the coordinator,
not by this worker.

| Test | Result |
|---|---|
| `postgres17LiveRoundTrip` | **passed** on the first run |
| `mysql8LiveRoundTrip`, **cold cache, plaintext, no TLS** | **passed in 0.091s** — mysql-nio does implement `caching_sha2_password` full auth over the RSA key exchange |
| `mysql8LiveRoundTrip` pinned-CA TLS block | **failed** — `NIOSSLExtraError.serverHostnameImpossibleToMatch`. D13; a defect, not a blocker |

## Note on the Stage 2 Local Network finding

[The Stage 2 transport note](2026-09-10_stage-2-transport.md) recorded that an ad-hoc-signed Swift
binary could not reach `192.0.2.6` (`errno 65`) while Apple-signed tools could, and attributed it to
macOS Local Network privacy. The Homebrew `mysql` and `psql` binaries used above are **not**
Apple-signed and reached the VM without a prompt, so the restriction is not blanket. That is an
observation about these two clients, **not** evidence that a Swift test binary will connect — W-kit
should expect to confirm that for itself and treat a repeat of `errno 65` as the known Stage 2 issue
rather than a database misconfiguration.

## Not done / limits

- No firewall rules were added, because `ufw` is inactive. If it is ever enabled, 3306 and 5432 must
  be opened to `192.0.2.0/24`.
- SQLite, the capability's third engine, needs nothing on the VM and was out of scope here.
- The MySQL X protocol (33060) stays bound to localhost.
- No `gpt_test` data is backed up; the fixture files reseed both engines from scratch. The test user
  can no longer destroy it, but keep the reseed command to hand anyway.
- `gpt_scratch` is expendable by design and is **not** reseeded or cleaned up: a test that dies
  between `CREATE TABLE` and `DROP TABLE` leaves a `gpt_live_*` table behind. Harmless, but it will
  accumulate; `DROP DATABASE gpt_scratch` and recreate it if it ever gets untidy.
- The CA is published as `GPT_DB_TEST_MYSQL_CA_PATH`, which is the name the test reads. The
  certificates expire `Sep 9 2036`; they are deliberately left as MySQL generated them.
- **`log_error_verbosity` is now 3, not the Ubuntu default of 2.** Deliberate, persisted, and the
  reason the log is noisier than a stock install. Revert instructions are in the open-investigation
  section. Do not lower it while that investigation is open.
- The pinned-CA TLS path does not work against this server (D13, above) and is not expected to until
  the API can express `VERIFY_CA` **and** the app can import a CA at all. Plaintext with RSA
  authentication is the working path meanwhile, and it fails loudly rather than downgrading.
- Neither server was tuned; both run at their package defaults.

## Next action

Nothing blocking. The server side is provisioned, split and verified, and both live round trips pass
against it — PostgreSQL on its first run, MySQL cold over plaintext. The MySQL auth cache is warm
again and nothing further depends on it staying cold.

Two items outlive this note:

1. **D13** — the pinned-CA TLS gap — is in our API and the app's missing CA import, not on this VM.
   Stage 3 backlog.
2. **The two ~10s tunnel failures are open and unexplained.** Verbosity 3 is armed and the counter
   baseline is recorded. If it recurs, read the `MY-010914` note that will now be written and
   **match the reason string**: `Got timeout …` is the bug, `Got an error …` / `Bad handshake` is our
   own TLS probe. Check which side stalled before reaching for contention again, since the counters
   did not support it the first time.
