# Vision Pro input, the Active Connections bolt, and the database scroll edge (2026-10-05 → 07)

## The bolt on the right (Mac) — done, confirmed by the owner
- `.primaryAction` is the leading edge on macOS. A first fix (placement `.automatic`) changed nothing
  in the database window: each pane ends its toolbar with a flexible spacer and its buttons, and items
  the window adds land before that spacer. Measured with an off-screen toolbar layout (a transparent
  window, AppKit item positions): an inner modifier's items come after the view's own.
- Now: `glassActiveConnectionsRoute` (environment) from the database window on the Mac;
  `glassActiveConnectionsLastInToolbar(isActive:)` in each pane, from the shown pane only.
  `GlassActiveConnectionsPlacementTests` fails on the window-level approach.

## Database scroll edge (Mac) — built, not yet seen
- The window hides SwiftUI's toolbar background for its own title material, which sits behind the
  content; content scrolled up printed through the toolbar title. `databaseScrollBehavior()` (was
  `databaseLookScrollEnabled`) adds `scrollEdgeEffectStyle(.hard, for: .top)` on the Mac to all ten
  database scroll views. A capture test was not possible: `CGWindowListCreateImage` is unavailable and
  ScreenCaptureKit needs screen-recording permission.

## Trackpad scrolling on Vision Pro — done, confirmed by the owner
- A Mac's trackpad driving the headset sends scroll events with no touches; the desktop's recognizer
  required two touches. Added a scroll-events-only `UIPanGestureRecognizer` (`allowedTouchTypes = []`).

## Pinch pose (for D46, proposed)
- `SpatialEventCollection.Event` gives `chirality` and `inputDevicePose.pose3D` (rotation), no mouse
  buttons (read from the visionOS SDK's swiftinterface). `DesktopPinchProbe` shows them when the app is
  launched with `GLASS_PINCH_PROBE=1`; attached, the gesture takes all input (no clicks pass).
- Readings (owner, 2026-10-06), z toward the viewer:
  right hand — palm away `up` z −0.82, palm toward +0.68; left hand — away +0.77, toward −0.40
  (mirrored: palm normal is `−up`). Threshold +0.2 on the palm normal's z.
- Open: whether trackpad hover reaches UIKit while the gesture is attached (the mode switch depends
  on it).

## Headset connection
- Unreachable for days: A full-tunnel VPN on the Mac blocked local discovery. Installing over a
  running app does not restart it; relaunch with `devicectl device process launch --terminate-existing`.
