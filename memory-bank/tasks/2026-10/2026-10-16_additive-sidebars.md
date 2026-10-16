# 2026-10-16: a terminal window's sidebar adds to the window (D77)

**State:** built on the Mac (2026-10-16, evening). For the owner to try on the next build.

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
