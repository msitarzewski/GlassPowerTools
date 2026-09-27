# The desktop window's size, and the size after login — 2026-09-22

*"The Desktop mode doesn't have a default desktop size on Mac, so it opens in essentially a
thumbnail. Then when I resize it and log in [640 × 480, stretched] and after a 1 pixel resize
[2,660 × 1,626]."* Three screenshots of the Linux server over RDP (GNOME's login screen, then the session).

## Two defects, not one

**1. The thumbnail.** `GlassDesktopScenes` declares `.defaultSize(1280 × 800)` and the view an
ideal of 1280 × 800, and the window still opened at about 320 points. macOS gives a new window in
a `WindowGroup` the frame the last one had — `defaults find desktop-session` shows
`NSWindow Frame desktop-session-AppWindow-1` — and a desktop window that was once a thumbnail
(the 2026-09-14 failure-panel sizing, or a shrink) stays one for every desktop after it. The
floor was 320 × 240 (`sessionContent`'s frame), so the thumbnail was legal.

**2. 640 × 480 after login.** The login screen took the window's size (2,660 × 1,626 for a
1,330-point window at 2×). The session that starts after logging in comes up at 640 × 480, a
size the client never asked for. Nothing on the client changed — window the same, `isConnected`
the same — so nothing asked again; and even the view's re-ask on a capabilities change would
have been dropped by `scheduleResize`'s "already asked for this size" guard, because the model
still believed its 2,660 × 1,626 request stood. The one-pixel resize was the first request that
differed.

## What changed

| File | Change |
|---|---|
| `Sources/GlassDesktop/DesktopSessionModel.swift` | `followServerSizeChange(from:to:)` on every frame: a frame at a size other than the one requested, arriving after a frame at some other size again, is the server having changed its mind → forget the request and ask for the window once more. `serverSizeCorrections`, at most `maximumServerSizeCorrections` (3) per attempt; reset with the rest of the remote state. Nothing when Match Window Size is off |
| `Sources/GlassDesktop/DisplayGeometry.swift` | `DesktopWindowSizing`: `floor` 640 × 400 points; `contentSize(desktop:available:)` — the configured desktop at one point per pixel, held inside the screen, never below the floor; `isAtFloor` |
| `Sources/GlassDesktop/DesktopSessionView.swift` | macOS: `.frame(minWidth: 640, minHeight: 400)` and `DesktopWindowSizer`, a zero-size `NSViewRepresentable` in the shape of `GlassWindowLayerReader`: two looks (after attaching, on first becoming key); a window found at the floor gets the configured desktop within the visible screen, top-left kept, whole window on screen. A window already larger — the remembered 1,326 × 905 — is left alone, and so is one the user shrinks afterwards |
| `Tests/GlassDesktopTests/DesktopSessionResizeTests.swift` | **New.** The login case (asked again once, not per frame, not after it is honoured), the bound, Match Window off; `DesktopWindowSizing` fits, holds to the screen, floors. Deterministic: stubbed `DesktopSessionOperations`, the model's own `receive` reducers — glassDT's `SessionRegressionTests` pattern, which had not been moved in |

Why frames and not the capabilities event: the reactivation after login may resend identical
capabilities, which `Equatable` swallows before the view sees a change. The frame's size is the
one fact that cannot lie about what the server is doing.

## Validation

- The six new tests pass; with the correction disabled (`maximumServerSizeCorrections = 0`) the
  login test fails at its three expectations, so it bites.
- `swift test`: **1,713 tests, 0 failing**. Release 0.4.201 built for macOS, iOS and visionOS;
  **installed on the Mac and the phone**, versions read back.
- **Not seen on the Linux server yet**: the window opening at the configured size from a remembered
  thumbnail (the remembered frame is currently 1,326 × 905, so the sizer stands down), and the
  session following the window through GNOME's login. The user has the server.

## Not done

glassDT's session-lifecycle tests (`../glassDT/Tests/GlassDesktopCoreTests/SessionRegressionTests.swift`,
~30 tests on attempts, trust, credentials, history and resize) were never moved into this
project. This note's tests are the first on `DesktopSessionModel` here.

## Third defect, 07:35 — the scale arrives one step late

*"The default image size here is set to 1920x1080 but this is not that. The desktop settings
on the RDP connection in Ubuntu show 4k resolution until I resize."* Two screenshots: the login
screen at 3,840 × 1,968 with tiny type; after a one-pixel nudge, 3,828 × 1,956 at **200%** and
readable. Not the host's choice and not the saved 1920 × 1080: with Match Window Size on the
window decides (the saved size is the fallback for Match Window off), and 3,840 × 1,968 is the
window at two pixels per point — asked for correctly. What was missing was the **scale**: the
connect carried the size in the client core data and left desktopScaleFactor at a fixed 100
(`MCSConnectInitial.encodedClientCoreData`), so GNOME laid a 4K desktop out at 100% until the
display channel's first monitor layout carried the 200% — and a layout with the same size and a
new scale is what the nudge was.

Now the scale goes with the size from the first frame: `GlassRDPConfiguration.desktopScaleFactor`
→ `RDPConnectionConfiguration.desktopScaleFactor` → `MCSConnectInitialConfiguration` →
the core data's own field (MS-RDPBCGR 2.2.1.3.2, clamped 100–500 with the display channel's
clamp, device scale left at 100 as the display channel does). `DesktopSessionModel.establish`
passes `currentScaleFactor`; the first monitor layout still repeats it for a server that reads
only the display channel. Tests: `clientCoreDataCarriesTheDesktopScaleFactorAndClampsIt`
(RDPKit, byte offsets 226/230) and `connectCarriesTheScale` (the model asks for 2,660 × 1,626
at 200% for a 1,330-point Retina window reported before connect).

**Whether gnome-remote-desktop reads the core-data scale is the user's server to answer** —
xrdp and Windows do; if the login screen is still 100% on 0.4.205 the display channel repeat
is what fixes it a moment later, and that is the same as before.
