# 2026-10-16: a terminal window's sidebar adds to the window (D77)

**State:** built on the Mac (2026-10-16, evening). Tried by the owner on 0.4.464 and 0.4.465 — both snapped on reopen;
rebuilt a second time (below, "On 0.4.465"), for 0.4.466.

## What the owner asked

> "I'd like to see if there's a way to make the left (and eventually right) sidebars additive and not resize my
> terminal window to make room."

Today, opening the Mac terminal window's sidebar (its tabs) takes its width from the terminal: the grid loses columns
and the program redraws (or, under Scale, D75, the text shrinks). Additive: the window grows by the sidebar and the
terminal keeps its size and place.

Same message, on D75 for iPad: "Sure. I think we can let users let us know if that doesn't work." That is, keep Scale
on iPad and try sizing the window there (`UIWindowScene.sizeRestrictions`) and sharper scaled text, verified as far as
the simulator goes. That work runs separately; its outcome is recorded in the D75 note.

## Where sidebars are

Only the Mac terminal window has one: `MacWorkspaceView`'s `NavigationSplitView` (the tabs). The iPad, iPhone and
Vision Pro terminal windows have none, and the terminal has no right-hand sidebar yet.

## How (AppKit's own behaviour, asked for)

`NSSplitViewItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings`: "The item prefers to keep the other
panes at their current size and position on screen, potentially growing or shrinking the window in the direction to
best preserve that. But it will break that preference in order to keep the window fully on screen or when in full
screen" (macOS 27.2 SDK, `NSSplitViewItem.h`). SwiftUI's split view on the Mac is an `NSSplitViewController`; it exposes
neither the item nor the behaviour, so the items are found in the window's views, as the reader already finds the
sidebar to open it.

**Measured** (an unseen window ordered on screen, `GlassAdditiveSidebarsTests`): opened, the window grew 240 points to
the left and the detail kept its size and place; off screen, AppKit grew it to the right instead (it keeps a window on
screen as it grows it and picks the direction from where it is). On macOS 26+ the detail's view runs under the
sidebar, so its frame is not the terminal's: the tests measure where SwiftUI lays the detail out.

**Where the window keeps its size** (`MacTerminalWindowReader.Coordinator.keepSidebarsAdditive`):
- the sidebar a window opens with — its saved frame already holds it; the behaviour is set only after the reader's
  `configureInitialSidebar` has put it in (proven: set first, the window opened 240 wider);
- the overview (grid/carousel), which hides the sidebar to give the terminals the whole window, until the sidebar is
  back as the window shows it. `MacWorkspaceView.openOverview` sets it before SwiftUI hides the sidebar, because the
  reader hears only after SwiftUI's update (proven: without it, the overview shrank the window to 660).
- full screen, and wherever growing would leave the screen: AppKit's own exception.

## Code

- `Sources/GlassShell/GlassAdditiveSidebars.swift` — finds a window's sidebar and inspector items; sets additive
  (fixed siblings) or not (fixed split view). Shared, for other windows if the owner wants them.
- `Sources/GlassTerminal/macOS/MacTerminalWindowPolicy.swift` — the reader takes `sidebarShown`; its coordinator keeps
  the sidebars additive except as above.
- `Sources/GlassTerminal/macOS/MacWorkspaceView.swift` — passes `sidebarShown`; `openOverview` turns additive off first.

## Tests (each fails without its change)

- `GlassAdditiveSidebarsTests` 2: additive, the window grows and the detail keeps its size and place (fails with the
  setter doing nothing); not additive after being so, the detail gives way (fails with both values additive).
- `MacTerminalSidebarTests` 3, with the real reader in a SwiftUI split view: the button grows and shrinks the window
  and the terminal stays (fails without the reader's call); a window opening with its sidebar keeps its frame (fails
  with the behaviour set before the reader opens it); the overview keeps the window and gives it back (fails without
  the overview's exception, and without the up-front call).
- Mac suites: terminal 865, shell 304; tmux unchanged.
- Not covered: the call in `MacWorkspaceView.openOverview` itself (the test makes the same call); the toolbar button
  in the running app (no Mac UI tests while the owner works) — his to try.

## Not done / known

- Dragging the divider still resizes the terminal (a person's own resize of the split, not a toggle).
- Database and editor windows keep today's behaviour; `GlassAdditiveSidebars` would serve them.
- A right-hand sidebar: whether SwiftUI's `.inspector` is an AppKit inspector item is to be measured when the terminal
  has one.

## On 0.4.464: closing fine, reopening snapped (fixed)

The owner: "It hides correctly but pops back to the original size violently. lol"

**Found with a standalone probe** (`~/Software/glass/tmp/sidebar-probe/main.swift`: an `NSHostingView` split view in a
window, frames sampled every 4 ms through AppKit's animated toggle; animations don't run inside `swift test`):
- a bare split view grows and shrinks smoothly both ways, the detail fixed on screen;
- with the terminal window's `.frame(minWidth: 720, minHeight: 460)` on the whole split view, reopening never grew
  the window: the sidebar squeezed the detail (1060 → 820) and snapped in at the end; with a 900-wide window,
  closing also stopped at the 720 minimum and widened the detail;
- AppKit grows the window by raising `NSWindow.minSize` step by step through the animation (sampled 1060 → 1275);
  a minimum SwiftUI holds on the whole content put it back each step. The toolbar was not the cause.
- With the minimum on the detail column instead, AppKit owns the window's minimum (detail + sidebar while open, the
  detail alone while closed) and both directions animate.

**Fix:** `MacWorkspaceView` gives the 720 × 460 minimum to the terminal's column (`MacWorkspaceTabContent`), not the
whole window (from glas.sh, no reason recorded). With the sidebar open the window's smallest is now 720 plus the
sidebar's width (was 720 whatever the sidebar).

**Test:** `MacTerminalSidebarTests` "the terminal window itself" hosts the real `MacWorkspaceSceneRoot` (an empty
tab) and toggles its sidebar: the window grows by the sidebar's width toward it and shrinks back. With the minimum
back on the whole window it fails as he saw it: 1000 → 1000 opened, 760 closed.

## On 0.4.465: "still fails the same way" — AppKit doesn't move a SwiftUI scene's window (rebuilt)

The owner, with tmux sessions in several tabs: "hmm. still fails the same way." The tests and the first probe put the
split view in a plain `NSWindow`; his windows are a `WindowGroup`'s (`AppKitWindow`, content an
`AppKitWindowHostingController`). A probe built as an app with a window scene (`SceneProbe.app`, `LSUIElement`, run with
`open -g`, in `~/Software/glass/tmp/sidebar-probe/scene.swift`; variants through `options.txt`) showed:
- with `.preferResizingSplitViewWithFixedSiblings`, closing never shrank the window (the detail widened) and opening
  grew it to the right only — no minimum, the column's minimum, the whole window's minimum and a full toolbar alike.
  AppKit grows such a window by raising its minimum width; nothing shrinks it, and SwiftUI's window controller holds
  its size against the split view's constraints (a detail holding priority of 510, or `.useConstraints`, moved
  nothing at all);
- setting the window's frame does work there. Driven by our own animation beside AppKit's sidebar animation, the
  detail drifted ≤7 points (≤2 started from the sidebar's change); with the detail's width held, 0.

**Now:** `GlassAdditiveSidebars` sets every sidebar and inspector to `.preferResizingSiblingsWithFixedSplitView`
(AppKit leaves the window alone), watches `isCollapsed` (KVO), and moves the window itself, animated 0.25 s ease in/out,
by the sidebar's width toward its side (`windowFrame`: a sidebar the left, an inspector the right; opening kept on
screen, nil when it can't be that wide). Measured on the way:
- one toolbar click flips `isCollapsed` three times (AppKit opens it, SwiftUI puts its own state back and forth), so
  changes are gathered and the window follows the net state, from where it is already heading;
- resizing the window inside the KVO change left the sidebar unfinished (open, laid out at no width) in tests: the
  window moves from the main queue's next turn;
- a change while not additive (overview, the sidebar it gives back) is recorded as it happens, so it never moves the
  window later;
- the view holds the terminal's column at its width for the animation (`willResizeWindow`), in a frame that fills the
  column whatever it holds: a plain `.frame(width:)` raised the window's minimum and grew it to the right.
A collapsed sidebar's view still reports the width it opens to (240), measured, so opening knows the width.

**Tests:** `GlassAdditiveSidebarsTests` 5 (window-frame rules 3; hosted additive and not); `MacTerminalSidebarTests` 4,
the real window among them. Every hosted one fails with the follower off; the real window's fails with the held
width allowed to raise the minimum. Both suites `.serialized`: run in parallel, their windows interleaved and a test
failed on another's account. Sidebar animations don't run inside `swift test` (no running app); tests set
`animationDuration` to 0. Not covered: the animation itself, which the probe measures.

Mac suites (screen unlocked): terminal 866, shell 307; tmux unchanged. Locked, the same run failed the
file-protection tests and these window tests — rerun unlocked before trusting a red suite. 0.4.466 on the Mac and
iPhone for the owner to try.

**Known:** collapsing the sidebar by dragging its divider shrinks the window by the sidebar's width at that moment.


## 2026-10-17: "+" and the title held; the opening's see-through frame

The owner's screen recording of 0.4.467 (in the working files, `shift-video`), typed answer to yesterday's offer:
"keep the + and title fixed". Frame by frame:
- **The shift.** Opening, "+" and the title rode the window's leading edge as it grew, then stopped at the sidebar's
  edge: 132 pt left in all (closing, the reverse). With the sidebar closed the window's buttons and the sidebar's
  button come first, over the terminal; open, they move over the sidebar.
- **A see-through frame on every opening** (both openings in the recording, no closing): the toolbar from the
  window's edge to the title showed the window behind.

**Measured in a scene probe** (the working files' `toolbar-probe`: a `WindowGroup` app with the real
`GlassAdditiveSidebars.swift` and `GlassWindowChrome.swift` compiled in; positions sampled every 4 ms; and, because the
shell can't capture the screen, the probe photographing its own window through `CGWindowListCreateImage` reached by
`dlsym`, see-through pixels counted in the toolbar band):
- the toolbar puts "+" at max(the room the buttons take, the sidebar's edge + 8): the title sat at the window's edge
  + 223 until 132 pt of sidebar showed, then at the sidebar's edge + 91;
- an empty item before "+" as wide as the sidebar shows, up to that room, keeps them within 1 pt — but a toolbar item
  is never narrower than 36 pt, so it appears at 36: "+" dips up to ~30 pt for two frames as the sidebar starts to open
  and as it finishes closing. Leading padding inside the "+" item did nothing;
- the room is where the sidebar's button ends, from the window's edge, with the sidebar closed (796 + 36 − 700 = 132).
- **The flash:** opening, AppKit lays the sidebar out at its full width *inside* the call that opens it — `isCollapsed`
  already reads false, the KVO not yet sent — and the window is drawn then; only after does it move the sidebar out of
  sight to slide it in and announce the change. The titlebar material, following `!isCollapsed`, stood at 240 over
  nothing. Reading where the sidebar actually is fixed closing but not this; following the sidebar exactly while it
  closes opened see-through slivers (the material is drawn a step behind the panel), so the material keeps covering
  the band from the window's edge once collapsed, as before. Filmed: the original flashed 3 runs of 3; holding the
  edge from KVO's `.prior` notice to its last, 0 of 5.

**Now:**
- `GlassTitlebarMaterialView` (GlassConnectionUI) observes `isCollapsed` with `.prior` and holds its edge while a
  change is under way (a count, in case AppKit nests them); otherwise as before.
- `MacWorkspaceToolbarHold` + `MacWorkspaceView`: the terminal column's leading edge in the window
  (`sidebarShowing`), the room read from the toolbar while it is laid out for a closed sidebar (at rest and the first
  frames of every opening; 132 until read), and a `ToolbarItem("new-terminal-tab-hold")` before "+" of
  min(showing, room) once that reaches 36, no shared background, hidden from accessibility, kept visible when compact.

**Tests:** `WindowChromeTests.materialWaitsForTheSidebarToOpen` — the material's edge at each split-view layout while
the toggle opens the sidebar, before it's announced, stays 0 (the original read 240), and follows the sidebar after;
`MacTerminalSidebarTests.toolbarStays` — the real terminal window in a hosting controller: "+" and the title on screen
within 1 pt closed, open, closed (without the hold: open moved). Not covered by tests: the two-frame dip, which the
probe measures.

## 2026-10-17: no line at the sidebar's edge in the terminal window

The owner, after 0.4.468: "What is that gray line that shows on the left side of the terminal window? That's what we
need to eliminate" (a screenshot, an arrow at the sidebar's edge; then "Looks like a left scroll bar?!"). Three
things stand on that edge (the scene probe listed the views there):
- AppKit's split-view divider, `NSSplitDividerView`, 0.5 pt, painting `_showBordersAwareDividerColor` — the bright
  line (+27 over its surroundings in the probe's pictures);
- `_NSSplitViewShadowView`, 12 pt over the content beside the sidebar — drew nothing measurable;
- the chrome's own hairline (`glass.sidebar.separator`, added 2026-09-11 when the divider painted nothing and the
  desktop showed through) — 4 pt inside the sidebar, barely visible.
Hiding the hairline left the line; hiding the divider view too removed it with nothing showing through (alpha 255 up
to the terminal). A hidden divider is shown again by AppKit as the sidebar reopens; a transparent one stays so (two
probe runs). Swapping the split view's class to clear `dividerColor` broke it (KVO had subclassed it). Dragging the
edge still sizes the sidebar: hit-tests there land on the split view itself, divider or not.

**Now:** `GlassTitlebarMaterialView.showsSidebarEdge` (default on, as the database and desktop windows keep it): off,
the hairline is hidden and AppKit's divider made transparent (a subview of the split view beside its panes, no wider
than its divider), again for each new split view. `MacTerminalWindowPolicy.apply` turns it off.

**Tests:** `WindowChromeTests.sidebarEdgeDrawsNoLine` — divider transparent and hairline hidden, after the sidebar
closes and reopens too, the edge still hit-testing to the split view, and back on; fails with the divider left alone.
Probe: no line at rest open, reopened, or in any frame of the animations; no see-through pixels.

## 2026-10-17: the held space closed again

On 0.4.469, with a screenshot: "LOVE this... there's a little new space next to the side panel in the toolbar (before
the +)" — 140 pt measured on it, the hold exactly. Asked, keep it (nothing moves) or close it ("+" slides with the
sidebar, as on 0.4.467): "It moves anyway... let's close the space. Is this an Apple defined pattern or is it custom
at this point?" Reverted 46cf403 (1534ece: `MacWorkspaceToolbarHold`, the view's hold, `toolbarStays`). Answered:
the toolbar is AppKit's arrangement again; the window growing by the sidebar (D77) and the edge without a line are
ours. Terminal suite 873. 0.4.470.
