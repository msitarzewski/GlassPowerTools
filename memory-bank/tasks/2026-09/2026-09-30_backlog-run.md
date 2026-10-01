# The backlog run — 2026-09-30

**State:** BUILD. Owner: coordinating agent. Authorized by the owner (2026-09-30): "create a plan and
build your list in the order you see fit. DRY and KISS, reuse code." Local commits per item; nothing
pushed. Each item: find the owner of the behaviour first, extend it, prove it with a test that fails
without the fix, build all three platforms, commit.

## Order, and why

| # | Item | Why here |
|---|---|---|
| 1 | Terminal password saved only after sign-in succeeds | A real defect; a typo overwrites a working password |
| 2 | Startup-command ticket expires by the clock; the two flaky terminal tests | A small real defect, and a clean full suite before release |
| 3 | Imported desktops default to iCloud Keychain like every other credential | Inconsistent default (D21) |
| 4 | Database "Rows per page" setting does what it says | A setting that does nothing |
| 5 | Slow desktop on the headset: adapt to a poor link | Owner: "a flaky connection not scaling to a streaming mode" |
| 6 | D42a — RDP clipboard: rich text and images, both ways | The owner's first clipboard priority |
| 7 | D42c — Files ⌘C/⌘V and drag with Finder | The most-used file path |
| 8 | D41 — library overview (counts, timeline; availability dots off by default) | Approved |
| 9 | Glass Power Tools as the Mac's default text editor | Small; owner's backlog |
| 10 | View and forget trusted host keys | Security hygiene gap from the help audit |
| 11 | Editor off the Mac: Find, closing a lone document, a blank document | Help-audit gaps |

Deferred, each large and none regressions: drive/printer redirection, RD Gateway, VeNCrypt, drag
onto a desktop, VNC Extended Clipboard, RDP file clipboard (D42b).

## Progress

(Appended per item: what the owner of the behaviour was, the change, the test, the commit.)

**1. Typed passwords on trial** — `f21766d`. Owner: `ServerManager` (password store + its rollback);
`tryPassword` / `settlePasswordTrial`, settled at `SessionManager`'s success and failure points; the
three prompts use it. Tests: `PasswordTrialTests` (3).

**2. Startup ticket by the clock; two flaky tests** — `fc5af66`. Test holds the main thread past the
deadline; fails on the old code. Theme-sync test waits up to 30 s.

**3. Imported desktops sync their password** — `7f45904`. `DesktopConnection` defaults to iCloud
Keychain (D21); help corrected.

**4. Rows per page; Settings ▸ Databases** — `22ebdc4`. The service's page size seeds a table's first
grid; the database's settings view is a shell page (`isShellPage`). Test: the page is registered.

**5. Slow desktop on a poor link** — survey by an Explore agent, then:
- RDP `8a1f376`: autodetect reported every bandwidth test as 1 ms (the server saw an infinitely fast
  link); `RDPAutoDetectMeter` times it, and in-session probes are answered. Unit-tested; **not yet
  checked against Windows** (the test account's password was session-scoped).
- VNC `0d600f4`: the next update is requested before decoding (pipelining). Fails-on-old test; live
  TigerVNC probe passes.
- VNC `22a1153`: Tight + JPEG with `RFBLinkQualityGovernor` (lossless / 8 / 6 / 4 by measured rate).
  10 unit tests; live TigerVNC probe passes.
- Found, not fixed: MockKRDP early-authorization tests fail 3 in 4 runs on unchanged code; RDP on
  Vision Pro requests about 2× pixels ("Automatic" scale uses displayScale); every frame is copied
  whole and uploaded whole to Metal.

**6. D42a — RDP clipboard** — `b2cccec` long messages travel as chunks and are reassembled (sends over
one chunk were refused; receives were parsed chunk by chunk); `be08840` rich content: text, HTML
("HTML Format"), RTF and images (CF_DIB/DIBV5/PNG ↔ PNG) both ways, fetched one format at a time;
`GlassClipboardContent` in the transport; remote copies land on the clipboard; the Mac sends local
copies on activation and change; "Share clipboard". Live: xrdp probe clipboard both ways passes; the
probe's resize step flakes ~1 in 3 on the previous commit too.

**7. D42c — Files with the Finder** — `55bea2c`. ⌘C: sftp:// links at once, then the files downloaded
(existing promise routine) and put on the clipboard for the Finder; ⌘V: Finder copies uploaded via
`SFTPIncomingDrop` on the general pasteboard. Mac only.

**8. D41 — library overview** — `a0b8ee1` counts + 30-day timeline + most used, from on-device
`connectionHistory` in the shell preferences (90 days, 2,000 max); `6106f22` availability dots
(Settings ▸ General, off by default; TCP only, 8 at a time, once a minute, while the library is shown;
`knownPort` hook per capability; none for SQLite, tunnelled databases or the local shell).

**9. Default text editor** — `28a0b6e`. Alternate editor for text/source/JSON/XML/Markdown/YAML in both
Info.plists; `onOpenURL` → editor open + present. Not yet opened from the Finder (needs install).

**10. Trusted host keys** — `ba35cf8`, help `d137b9e`. Settings ▸ Connections lists and forgets.

**11. Editor off the Mac** — `c4970fc`. Find and Close Document in the toolbar; New Document existed.

**State:** all eleven built and committed; nothing pushed. Mac build 0.4.263 contains items 1–10 (not
installed: the owner was using the Mac); item 11 is after it. Live checks still owed: RDP autodetect
against Windows; the default-editor Open With from the Finder; the headset for everything since 0.4.254.

**After the run, with the owner on the Mac:** `5512901` Settings' width follows its tab count (ten pages
overflowed the fixed 640 pt and Editor was unreachable); `ef1765e` desktop glass on the Mac — the same
Opacity and Frost as the headset, saved on the device, the frosted backdrop behind a see-through
desktop, black kept for an opaque one (glassDT had none on the Mac). Owner: "Oh, wow, that's nice."
