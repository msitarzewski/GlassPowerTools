# 2026-10-29 — the headset's slow typing and moving tools menu (0.4.549 → 0.4.550)

**Owner, on the headset at 0.4.549:** "The settings menu is moving again, I can't choose Settings... Also typing in
here is painfully slow for some reason. It feels like something is eating CPU cycles. There's about a .5 second
delay for every keypress. Related?"

**Authorization:** fixing what he reports while testing; builds install when ready. Nothing committed.

## Evidence (the app's diagnostics file, copied off the headset at 08:08 UTC)
- `tools chose settings` last at 2026-10-28 05:54 UTC, on 0.4.544; none since. The headset wasn't used between
  0.4.544 and 0.4.549, so the change is somewhere in 0.4.545–0.4.549: Fine Position, terminal color schemes
  (Terminal Themes), the Files window fix, git.
- The tools bar was drawn about twice a second (842 draws in 454 s), the same as on 2026-10-28 04–06 UTC (5,115 in
  2,735 s), when Settings worked. Bursts of 40–145 in 2 s come with keyboard focus changes, as before. So it isn't
  the 0.4.539 redraw storm (72–96 in 2 s, all the time) back.
- `media event=hp-decoder-check ... ms=13734` at launch (07:58 UTC); 45 ms at the launch before. Something loaded
  the headset heavily as the app started.
- The Mac's own app (0.4.549) was idle (`sample`: main thread waiting); the Mac isn't the cause.
- Could not profile the headset: `xctrace` lists it offline ("Timed out waiting for device to boot"),
  `devicectl device sysdiagnose` fails (DiagnoseError 0), `devicectl device capture screenshot` isn't supported.

## Suspect and change (0.4.550)
`TerminalSchemeLibrary` (0.4.546) is started by every terminal window. Its `refresh()` listed the device's and
iCloud's Terminal Themes folders **on the main thread**, asking iCloud two questions per file
(`ubiquitousItemDownloadingStatus`, `contentModificationDate`) and making each scheme's colors again; it ran on every
`NSMetadataQuery` notice **and after each scheme read** — for the owner's 148 arriving on a new device, 148 listings
of 148 files, more as downloads finish.
- Listings now run off the main thread (`TerminalSchemeLibrary.list`, nonisolated) and are coalesced
  (`refreshSoon`: half a second's wait; requests meanwhile make one more listing after). A scheme's colors are made
  once, when it is read. Adding still lists at once (off the main thread); removing drops it at once.
- `MainThreadStalls` (visionOS, started with the diagnostics file): every 100 ms a no-op is sent to the main actor;
  waits of 150 ms or more are counted and written every 5 s ("main thread kept waiting N times in 5s, longest M ms").
  Each off-main listing is written too ("schemes listed N in M ms").
- Test: `readingManyListsAFewTimes` — 24 schemes imported and read are listed at most 4 times; with a read's
  listing put back on the old per-read path it fails ("listed 25 times for 24 schemes"); source restored from a
  saved copy, test passes. The suite: 6 of 6.

## Not known yet
Whether the library was the cause: Rain Garden (new 2026-10-28, animated) and Fine Position are also new to the
headset. The next diagnostics file says whether the main thread still stalls, and when.

## 0.4.550 on the headset (08:24 UTC): the suspect was wrong
- `schemes listed 0`: the headset has no schemes. The library wasn't the cause. The change stays (listing off the
  main thread is right anyway, and tested), but it fixed nothing he could feel.
- Main thread: kept waiting only during launch (longest 753 ms), then once for 156 ms as Settings opened. Typing
  doesn't stall it. Settings opened at 08:29 (the restart, or chance; the menu wasn't moving then).
- **The link to the headset is slow and uneven.** The headset's terminals are SSH sessions to this Mac over
  Tailscale (direct, on the LAN). Ping from the Mac, every 0.5 s: 53, 69, 92 … 400, 422, then 3, 5, 3 … and climbing
  again — a sawtooth to ~420 ms; the raw LAN address the same (avg 142 ms, max 400). The iPhone on the same Wi-Fi:
  3–80 ms. The Mac's `awdl0` was active and `avconferenced` and `VTEncoderXPCService` busy (video sent to the
  headset: Mac Virtual Display, most likely). A key's echo waits a round trip, so ~0.5 s is the network. His test:
  close Mac Virtual Display and type.
- Then his "Should we add an FPS/debug window? I can see the screen flicker. It's very obvious that something is
  refreshing the screen a LOT" — a second problem, the network doesn't explain flicker.

## 0.4.551 (headset only): refresh counts
`TerminalRefreshCounts` (GlassTerminalEmulator, visionOS): per second — terminal windows drawn
(`VisionTerminalWorkgroupView.body`), panes drawn (`TerminalWindowView.body`), bars drawn, output chunks and bytes
(`SwiftTermHostModel.ingest`), pictures taken (`drawPreview`: the orb, dock and card pictures, each a full
`layoutIfNeeded` + `displayIfNeeded` of the terminal), main-thread waits; and from each typed key to its terminal's
next output (at most the true echo time: output that comes anyway answers early). Shown over each terminal window by
Settings ▸ Terminal ▸ Diagnostics ▸ Show Refresh Counts (`TerminalRefreshCountsView`, an ornament drawn by itself);
written to the diagnostics file every 5 s that anything was counted ("refresh in 5s: …"). SwiftTerm itself draws
only on output (`queuePendingDisplay`, 60 fps cap; the Metal view paused, `enableSetNeedsDisplay`), so it isn't a
free-running display.

## 0.4.551 counts on the headset (08:46 UTC, his typing): not SwiftUI — SwiftTerm's Core Graphics repaint
- Typing 4–43 keys per 5 s: windows 0–1, panes and bars 1–2 per 5 s, waits none; pictures 0. Output about 38 chunks
  a second all the time (2–4 KB/s). Key to next output 23–44 ms (longest 93): the network is fine once the video
  stream stopped.
- SwiftTerm 1.20's `updateDisplay` on iOS/visionOS: `setNeedsDisplay(bounds)` for every update ("TODO iOS" in the
  source; the Mac invalidates only the changed rows). Vision Pro drew with Core Graphics
  (`SwiftTermRendererPreference.platformDefault`, a glas.sh-era hold until Metal presentation was proven), so every
  echo and every output chunk repainted the whole terminal. The owner: it happens in a plain shell too, and
  "Might we rather spend the time on something other than Core Graphics? … Not other editors... fixing upstream!"

## 0.4.552 (headset only): Vision Pro draws with Metal
- `platformDefault` on visionOS reads `terminal.drawsWithMetal` (default true). SwiftTerm 1.20 tracks Metal on
  visionOS itself: `metalRendererStatus` (presented frames, `.healthy`/`.recovering`/`.fellBackToCoreGraphics`), and
  falls back to Core Graphics when frames stop — the glas.sh-era worry (1.13 reporting Metal active without
  presenting) is what that recovery handles.
- Settings ▸ Terminal ▸ Diagnostics ▸ Draw with Metal switches open terminals at once
  (`SwiftTermRendererPreference.changedNotification` → `SwiftTermEngine.rendererPreferenceChanged`).
- Refresh counts gain Metal frames (from `.terminalViewMetalRendererStatusDidChange`); the diagnostics file gets
  "renderer <backend>" when a terminal's backend changes and "renderer metal <state> after N frames" when Metal's
  state does.
- `glas_shTests` renderer test: visionOS now expects `.metal` like iOS (not yet run on a visionOS simulator).

## Upstream SwiftTerm (cloned to `~/Software/glass/tmp/SwiftTerm-upstream`, main at 9eccf35, 2026-10-28)
- We pin 1.20.0 (2026-10-08 bump); upstream has v1.99.0 (Oct 8) and v1.99.1 (Oct 21), 299 commits since 1.20: a
  rebuilt frame path (`TerminalRenderOwner`, frame driver, terminal lock, render loop on macOS), "fewer main-thread
  hops, a row cache by line, plain-cell glyphs, read coalescing" (#766), iOS scrollback refresh (#764).
- **The iOS/visionOS full repaint is still there** in main: `TerminalRenderOwner.prepareFrame`, `#else region =
  request.viewState.viewBounds` (the Mac computes the dirty rows). An upstream fix is iOS dirty regions in UIKit's
  coordinates (top-down, a scroll view's content offset). Any upstream fix reaches us only after moving 1.20 → 1.99.x,
  a large step for `SwiftTermHostView.swift` (6,000+ lines on SwiftTerm's API). Opening a PR upstream needs his word
  on the prepared change.

## Metal on the headset (0.4.552): rejected by his eye
"Oooh intereresting. The text is far less legible and the refreshes more obvious! Its like a jpg vs png". Core
Graphics stays Vision Pro's default (0.4.553: `terminal.drawsWithMetal` defaults false; the switch stays in
Diagnostics). The reason is not measured; my reading is that Metal hands visionOS a fixed picture while Core
Graphics text can be redrawn by the system at the size seen.

## 0.4.553 (headset only, installed and read back): Core Graphics repaints the changed rows
- `ReviewingTerminalView.setNeedsDisplay(_:)` (visionOS): when SwiftTerm asks for the whole bounds right after
  reporting changed rows (`rangeChanged`, recorded only while its update range is uncleared), and the view is at the
  bottom of its scrollback, it asks for `TerminalRepaintBand.rect` instead — the rows, one each way, to the foot
  from the last two. Anything else repaints whole. `clearsContextBeforeDrawing` true on visionOS (a band starts from
  clear; false came from glas.sh with no reason given).
- Settings ▸ Terminal ▸ Diagnostics ▸ Repaint Changed Lines Only (default on); counts gain whole and changed-line
  repaints. `TerminalRepaintBandTests` 4 of 4 (band in the scroll view's space, top row, foot, outside → nil).
- Not yet: his look; whether partial repaints remove the visible refresh. SwiftTerm's iOS draw still draws every
  visible row (clipped to the band by UIKit).

## His question: "Why aren't we building our own terminal emulator without all of the shared baggage?"
Recommended (not yet approved): our own renderer, Vision Pro first — a layer per screen row drawn with Core Text,
only changed rows redrawn, scrolling by moving layers, cursor and selection as layers — as a second implementation
of the host's `TerminalEngine` protocol, on SwiftTerm's headless `Terminal` core (kept: the sequences, buffer,
Unicode widths and our tmux control mode are where the correctness lives). Switchable per window. Costs: selection,
keyboard/IME input, VoiceOver, links, search highlights, images, hold-to-select and diagram marks move to the new
view; days to a couple of weeks. Waiting on his word.
