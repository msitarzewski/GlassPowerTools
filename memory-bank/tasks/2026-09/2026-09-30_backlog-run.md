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
