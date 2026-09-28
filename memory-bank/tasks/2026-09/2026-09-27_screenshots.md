# Screenshots from a demo fixture — 2026-09-27

**State:** PLAN → BUILD. Owner: coordinating agent. Asked by the owner after seeing the site:
screenshots, perhaps from a mock engine. The owner: Vision Pro is the reason the product exists and
cannot be left out; capture it on Apple's simulators. Not committed until the owner says so.

## Approach

Real engines wherever they run locally; a mock only where a server would be needed. All of it is
DEBUG-only and runs inside the existing `--ui-testing <uuid>` isolation (own storage, no iCloud), so
nothing ships and nothing touches anyone's library. Only neutral names, addresses and data.

| Surface | Source |
|---|---|
| Library | seeded hosts, favourites, collections (extends `--ui-testing-seed-hosts`) |
| Editor | seeded project (`--ui-testing-seed-project`) with demo files |
| Database | a real SQLite file of made-up data (`Tools/Screenshots/demo-shop.sql`) — no mock |
| Terminal | a replay session: the real terminal view fed a recorded ANSI transcript |
| Desktop | a still frame in the real desktop window |

## Capture

The visionOS simulator cannot screenshot through XCUITest ("remote interface does not have this
capability", 2026-09-13), but `xcrun simctl io <udid> screenshot` works. So the app opens each surface
itself from a launch argument (`--demo-open <surface>`), and `Tools/Screenshots/capture.sh` builds,
installs, launches each scene and captures it — Vision Pro first, then iPad and iPhone — into
`site/static/shots/`. Proven for the library on the visionOS 27.2 simulator, 2026-09-27.

## Checkpoint — paused for compaction

Built and seen on the visionOS simulator, uncommitted: `App/GlassDemoMode.swift` (`--demo-open
editor|preview|terminal|database`), a DEBUG terminal replay request (no connection; typing goes
nowhere), a DEBUG database request that imports a demo SQLite file and opens its `orders` table, a
DEBUG guard that keeps the terminal from raising the keyboard in demo runs, and `Tools/Screenshots/`
(`demo-shop.sql`, `make-demo-db.py`, `shoot.sh`). Learned: visionOS restores earlier windows, so each
shot reinstalls; the database overview shows the simulator's file path, so it is not captured.
Next: the desktop still frame, nicer editor files, `capture.sh` for every platform, then the site.

## Checkpoint — committed, paused (2026-09-27)
Added since: `--demo-open desktop` (a server-less session showing a remote screen the app draws
itself, `GlassDesktop/Debug/DesktopDemo.swift`); the editor and preview surfaces open an invented
`shop` project (Swift, README with a table and Mermaid, compose.yaml) with the preview beside;
`Tools/Screenshots/capture.sh` for visionOS, iPad and iPhone; `--demo-keyboard` keeps the keyboard
up. All six surfaces seen on the Vision Pro simulator; iPad and iPhone captured, not yet reviewed.
**Paused by the owner**, who wants to judge the app on the headset before any screenshots are
chosen. Not on the site.
