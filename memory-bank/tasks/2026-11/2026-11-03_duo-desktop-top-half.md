# iPhone Duo stood like a laptop: the remote desktop has the whole top half (2026-11-03)

**Ask (the owner),** showing a photo of another app's Mac desktop filling a Duo's top half with keys below: "How are
they getting a full screen on the top for the desktop?" After the answer, his choice: "yes, do the bars first".
**Status:** built 2026-11-03 (0.4.591), committed and pushed 2026-11-03 at his "updated and pushed". Earlier Duo work:
`../2026-10/2026-10-31_duo-deck-plan.md` (D93; step 3 is the desktop's deck).

## How the others do it (researched)
- **What the photo shows:** no status bar and no navigation bar; the app's controls float as capsules over the
  picture's top edge; one Mac window (no Mac menu bar) fills the half. The app wasn't identified: it isn't Sill
  (no "Focus", "100%" stepper or display picker in Sill's released code). The widely shared reel of a Duo as a tiny
  MacBook never named its app; Headroom and Sill are the two shipping apps that do this
  (pasqualepillitteri.it, 2026-10-24).
- **Sill** (open source, Apache-2.0; read at commit 41e8cb88, not built or run): hides the status bar on its
  stream screen only (`.statusBarHidden(true)`), splits at `reservedRegions(kind: .division)`, picture pane 0–455
  pt with an 8 pt inset. The phone sends the pane's size; a Mac helper moves and resizes the window through
  Accessibility (`kAXPositionAttribute`, `kAXSizeAttribute`) to the pane's shape and restores it after, captures it
  with ScreenCaptureKit, streams HEVC over its own TCP protocol (not VNC). By default it also puts the window on a
  private `CGVirtualDisplay`, which is why it ships outside the Mac App Store. Its whole-desktop mode is letterboxed.
  Its own key row: esc, tab, ctrl, opt, cmd, shift, arrows (latching modifiers).
- **Headroom** (MusicFlow): uses macOS's built-in Screen Sharing; Mac on top, keyboard below, half open.

## Where we stood
Stood like a laptop, the status bar and our bar (back, name, ⚡, Settings, Clipboard) took 82 of the 456 pt above
the fold; the picture had the 375 under them. RDP already resizes to the picture's area (Match Window Size). A Mac
over Standard Screen Sharing can't: Apple's server never offers ExtendedDesktopSize (`VNCStreaming.swift`,
`RFBServerDialect`). High Performance (D65) asks for a virtual display the window's size, but only at connect, and
is unverified on a real Mac.

## Built
- `DesktopSessionView`: stood like a laptop, `.statusBarHidden` and `.toolbarVisibility(.hidden, for:
  .navigationBar)`. The strip under the fold now has the desktop's name over its state, Keys, the arrow pad, then a
  glass capsule with Settings, Clipboard and the ⚡ (`sessionActions`, the same controls as the bar).
- `GlassFoldDeck` takes `back:`, drawn first in the strip as a glass circle like the deck's switch
  (`glass-fold-deck-back`). The desktop passes its `onClose` (the cover's chevron does the same:
  `activeDesktop = nil`); the DEBUG demo cover now passes it too.
- The ⚡'s action (open Connections or leave the screen, then Active; held, All Windows) is one view now,
  `GlassActiveConnectionsBolt` (`GlassActiveConnections.swift`), used by the toolbar's ⚡ and by the strip. The
  desktop's cover hands the route down (`\.glassActiveConnectionsRoute`), as the database already does.
- A first try handed Back down as an environment closure; the compiler warned that a closure in `@Entry` invalidates
  its readers on every update, so Back is `onClose` instead.
- Help: `site/help/desktop-input.md` (the half, the strip's contents, which desktops resize). Release notes 0.4.591.

## Validation (Duo simulator, iOS 27.2, stood like a laptop)
- `DuoDeckUITests.testTheRemoteScreenHasTheWholeTopHalf` (new): the remote screen's top at the window's top; no
  bar with Back; Back, Settings, Clipboard and the ⚡ only under the fold; Back leaves the desktop. Passes. Seen
  failing with `.toolbarVisibility` removed and, separately, with `.statusBarHidden` removed (the screen at y 82
  each time); the file restored and compared byte for byte.
- `DuoDeckUITests` otherwise: trackpad, shortcut recording, the editor's and database's strips pass.
  `testTheSwitchTradesTheTrackpadForTheKeyboard` and `testATerminalsFoldBringsUpTheKeyboard` fail, and fail the same
  way on the code before this change (the four files put back to HEAD, built, run, restored). Cause, measured: after
  the switch is tapped the on-screen keyboard sits below the window (y 956 in a 951-pt window), as iOS does with a
  hardware keyboard connected, so the deck rightly keeps the trackpad. The simulator was booted fresh today; Device
  Hub's "Simulate Hardware Keyboard" (which the 2026-10-31 runs had off) isn't reachable by AppleScript, and Device ▸
  Keyboard ▸ Toggle Software Keyboard didn't change it (toggled back). These two need that switch turned off.
- Builds (Debug): the iOS simulator (Duo), the Mac and the visionOS simulator all succeed, with no warnings in the
  touched files.
- Pictures: `~/Software/glass/tmp/duo/bars/before-after.png` (before: 0.4.590's capture; after: this build). The demo
  desktop is a fixed 1920 × 1080 image, so in the 669 × 456 half it shows black above and below, as a Mac would; a
  real RDP server resizes to fill.

## Found, not changed
- **The library kept under a desktop shown in a page is in the accessibility tree** (its bar, "Your Library", its
  segmented "Connections") although `glassSessionCover` marks it `accessibilityHidden`. XCUITest sees it; whether
  VoiceOver can reach it there isn't checked. Its own task.

## Open (the owner's)
- A Mac's shape in the half: High Performance's virtual display re-sized when the fold changes (now: at connect
  only, unverified on a Mac), or a one-window mode like Sill's (a Mac-side helper: ScreenCaptureKit and
  Accessibility; our Mac app could be it, a new transport).
- Whether the demo desktop should follow the requested size, as RDP does, for pictures of the Duo.

## Site pictures, and the carousel on the site (2026-11-03, his "Let's get the site screen shots and all updated and pushed. The new coverflow view for terminals too!")
- **The Duo's laptop picture** taken again on the Duo simulator and put in Apple's partly open Duo bezel with
  PhotoCraft's CLI, as on 2026-10-31: `site/static/shots/duo-laptop-desktop-full-top.webp` (a new name, so browsers
  holding the old picture for a week fetch it; the old file removed). The demo desktop was a fixed 1920 × 1080 picture
  and showed black above and below in the half; with `--demo-desktop-resizes` (DEBUG) its made-up server reports that
  it can change size and answers each Match Window Size request with the same screen drawn in that shape
  (`requestDemoDesktop(redraw:)`, `DemoRemoteScreen.picture(width:height:)`), as an RDP server does. Off by default,
  so the Mac and Vision Pro desktop pictures (and their "1920 × 1080" words) are unchanged.
- **The carousel:** `macbook-carousel-dark/light.webp` from the macOS VM (`site_shots.sh carousel`: the
  `terminal-carousel` surface, btop and four coding agents, each tab shown with ⌘2…⌘5, ⌘3 chosen, ⌥⌘G) and
  `vision-carousel.webp` from the visionOS simulator (`device_shots.sh vision-carousel`, with `--demo-carousel` and
  `--demo-visit-tabs`: off the Mac a tab has a picture once shown, so the window shows each tab in turn, chooses the
  middle one and opens the overview). The Vision Pro window is clear above its tiles, so its crop finds it at a
  smaller difference (12) and frames it closer (1.12). The throwaway VM copy had a 1920 × 1200 display; set to
  1512 × 982 as the base VM (`tart set`).
- **Pages:** a "A window's tabs, side by side" band on the home page (after the orb dock) and the terminal page (after
  Show All Windows), with a status note: in the Mac's release 0.4.589, not yet in the iPhone and iPad beta, Vision
  Pro to follow. The Duo band's words and the picture's description follow the full top half. Checked in the built
  site at 1280 wide (dark) and 390 wide (light): pictures load, no sideways scroll.
- **Seen, not changed:** on Vision Pro the carousel's front tile is lighter and clearer than the site's terminal
  window at the same glass (the room's TV shows through it); for his headset check of D99.
