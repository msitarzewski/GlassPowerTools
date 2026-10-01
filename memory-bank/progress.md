# Progress

Current state, by area: what is verified and how, what is not, and what is known to be open.
Rewritten 2026-09-27 from the session-by-session log, which remains in git history; the monthly
task notes under `tasks/` carry each piece of work's evidence. Verification levels used below:
**unit** (package tests), **UI** (XCUITest on a simulator or the Mac), **device** (driven on real
hardware), **server** (against a real SSH, database or desktop server — always the disposable test
VM for SSH and databases).

## Built

All four capabilities and the shell are built and in daily use on the owner's Mac and iPhone:

| Area | State | Strongest evidence |
|---|---|---|
| Shell: library, hosts, services, one setup sheet, favorites, collections, tags, search, Active and the session switcher, settings, layers | built | unit, UI on Mac and iPhone simulator, device (Mac, iPhone) |
| Host library sync through CloudKit; credentials and host-key pins through iCloud Keychain (D18, D19, D21, D23) | built | unit; device (CloudKit delivering between Mac and iPhone). The two-device acceptance run of D26 has not been done |
| Terminal: SSH, host trust, keys (file and Secure Enclave), tabs, themes, workgroups, local shell on Mac, SFTP browser, port forwarding | built | unit, UI, server (OpenSSH 10.2: shell, SFTP, RSA and Ed25519 sign-in), device |
| Databases: MySQL, PostgreSQL, SQLite; TLS modes; host tunnel; browser, grid, record editor, query editor, Explain, history, read-only services | built | unit, server (MySQL 8, PostgreSQL: 21 live integration tests plus the engine's own), device |
| Remote desktops: RDP (RDPKit) and VNC (VNCKit), certificate policy, resize following the window, audio, clipboard | built | unit (RDPKit 1,015 tests), server (Windows 11 with NLA — 2026-09-14 and again 2026-09-27; a GNOME RDP server), device (Mac, iPhone) |
| Editor: documents, projects on this device and over SFTP, New File, first save into a project, viewers, Markdown preview with Mermaid, 16 grammars, TextKit 1 on the Mac (D36) | built | unit, UI on iPhone simulator, server (7 live remote-editing tests), device (Mac) |
| Acknowledgements and licence notices (generated, guarded by tests) | built | unit |

Package suite: about **1,790 tests**. The last full run with the screen unlocked passed (1,777, early
2026-09-27); the night's later runs were under a locked screen, where file-protected stores cannot be
read — they fail the same 137 tests before and after the night's changes, and every new test passes.
Vendored suites: swift-nio-ssh 363, Citadel 58, RDPKit 1,015. Release builds succeed for macOS, iOS
and visionOS.

## Release preparation (2026-09-26 → 27)

Done: privacy cleanup (rule 61); SSH stack re-vendored at upstream commits with documented patches;
licences and acknowledgements; dependency refresh (see `techContext.md`); the public-release audit's
fixes — a new built-in theme identifier with migration, the widget's dead links removed, one
`Config/Identity.xcconfig` for signing, a warning for unencrypted database connections, query
history redacted by default, MySQL metadata lookups bound rather than escaped (a real defect under
`NO_BACKSLASH_ESCAPES`, proven against a live server), editor UI tests isolated from the real
project list, RDP trust evaluated over the whole certificate chain, and VNC's lack of session
encryption stated in the setup form. Details in `tasks/2026-09/`.

Also done: README, SECURITY, CONTRIBUTING and a building guide; 35 help pages audited from the code,
the site and its generator (not deployed); Sparkle for the Mac with a release script (never run); and
the defects the help audit found (`tasks/2026-09/2026-09-27_help-site-and-updates.md`).

Remaining before a first public release: the owner's release steps (Sparkle key, Developer ID
profile, notarization, deploying the site), the behaviour findings listed in `activeContext.md`, and
— only on the owner's word — the history rewrite and the first push.

## Not verified

- **Vision Pro:** the headset runs 0.4.123; nothing since has been seen on it, including Settings as
  an ornament tab view. Its pairing with the Mac needs to be restored.
- **The D26 two-device acceptance run:** add a host with a key on one device, connect from another
  without re-approving trust.
- **UI tests cannot reach a database or desktop surface:** both need live fixtures that a simulator
  runner does not receive. A seeded configuration is the fix.
- **SwiftTerm 1.18** has not been looked at on screen.
- **RDP with a certificate from an intermediate authority** has not been tried against a real server.
- **The grid's timing harness** has not been re-run since the grid changes; the target is unmeasured.

## Known and open

- A database workspace's tabs do not survive leaving and returning on a phone; its session and SQL
  drafts do.
- Desktops are listed in Active (`GlassDesktopCapability.openSessions`); the D31 line saying they
  contribute none is superseded.
- `configurations(ofKind:)` skips undecodable records without logging.
- VNC sessions are unencrypted after sign-in (no VeNCrypt, no tunnel); the setup form says so.
- tree-sitter 0.27 and swift-crypto 5 wait on upstream releases (`techContext.md`).
- The legacy `SFTPRemoteEditorView` sheet remains as a fallback; the owner has been asked whether to
  delete it.
- **Backlog (owner, 2026-09-27):** let Glass Power Tools be set as the Mac's default text editor
  (declare editable document types so Finder's "Open With ▸ Change All" and `open` reach the editor).
- glassDT parity audit findings: `tasks/2026-09/2026-09-27_glassdt-parity-audit.md`.
- Library sync (2026-09-28): whole-account fetch, deletions dated by statement, no set-up service can
  vanish through a merge, per-record apply with visible failures, dry-run mode. Proven on the Mac
  against the real account (0/0 after repair); the phone and headset received 0.4.249.
- visionOS: lists unwound to the platform's own (2026-09-28). D40 narrowed (2026-09-29): all window
  transparency stays; only list formats and non-Glass chrome change. The database results bar is
  done (icons + More); verified on the Mac, not yet on the headset.
- Two terminal tests fail intermittently in full-suite runs only (see `activeContext.md`).
- Schema diagram (D43, 2026-09-30): built; unit + live MySQL/PostgreSQL tests pass; in use on the
  Mac; seen in the visionOS and iPad simulators; not yet on the physical headset or the iPhone.
- Backlog run (2026-09-30): typed passwords on trial; startup tickets by the clock; imported desktop
  mobility; Rows per page and Settings ▸ Databases; RDP autodetect timed and answered in session; VNC
  pipelining and Tight+JPEG with adaptive quality; RDP clipboard chunking and rich content; Files ⌘C/⌘V
  with the Finder; library overview and availability dots; default text editor; trusted host keys;
  editor Find/close off the Mac. Unit-tested; VNC and RDP clipboard checked live against the Docker
  fixtures; Windows, the Finder's Open With and the headset not yet.
- Desktop glass on the Mac (2026-09-30): Opacity and Background Frost as on the headset; seen by the
  owner on 0.4.266. Settings on the Mac sizes itself to its ten tabs.
