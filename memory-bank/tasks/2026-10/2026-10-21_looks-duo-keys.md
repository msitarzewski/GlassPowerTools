# More looks, the Duo half open, and Keys on Vision Pro (2026-10-21)

**His words:**
- Looks: "have we built additional looks yet? Let's add a few more. Maybe cue off the the running coding agent like we
  do in expose mode? :)". He chose Agent, Aurora, Starfield and Blueprint, the agent's own colour, and: "look at the
  animation that happens with autopaper's generating image in the now view! (it's one of my projects)".
- Duo: "please verify the iPhone Duo preparation! … do we have the half-open keyboard on the bottom and terminal on
  the top plan in place so it can be used like a mini computer? :D Use the web for research." Then, with a picture of
  the half-open terminal: "move these to the lower part?"
- Vision Pro: "the full key menu on terminal mode in visionPro (so we can do those with no physical keyboard paired)".

**Authorization:** build it. Commits, releases and App Store Connect writes on his word.
**Where:** a worktree in the working-files folder (branch `looks-agent-aurora`), while a background agent
built the main tree for the Duo simulator. Its local key folder is a link to the main tree's; delete it
before bringing the work back (git doesn't ignore a link there).

## Looks (D84)

- **Coding Agent** (`TerminalBackdropStyle.agent`, `TerminalAgentBackdrop`): the agent each terminal runs, as Show All
  Windows tells it (`GlassTerminalCapability.agent(of:)`, `MacWorkspaceController.agent(for:)`), drawn large and faint
  in its colour.
  - **While it works**, the terminal printing (`SwiftTermOutputActivity`), a smoke of its colour drifts and the
    mark breathes and ripples. That is AutoPaper's `WorkingEffect`/`Working.metal` (his project, MIT): the 3 × 3 mesh
    whose inner points wander, and `glassWorkingRipple`.
  - **When it waits** the smoke thins and stops, and the mark holds still and glows; the timeline is paused, so
    nothing is drawn again.
  - **No agent**, nothing (`drawsBackdrop(agent:)`).
  - **The agent is asked inside the backdrop** (`findAgent`), so it is asked again whenever output starts or stops.
    A title, which names Claude Code outside tmux, redraws nothing by itself (it is deliberately not published).
  - **Colours** (`TerminalAgent.accent`): his Agency Agents app's `tools.json` accents. Black marks (Cursor, Kimi) and
    agents it doesn't list use the text's colour. `TerminalGlowColor.agent` glows the text in it.
- **Aurora**, **Starfield** (`glassAurora`, `glassStarfield`) quicken with output (`quickensWithOutput`); the stars
  streak by the clock's eased speed. **Blueprint** (`glassBlueprint`, still) with the `blueprint` palette, monochrome
  pale blue.
- Starting points: `agent`, `aurora`, `starfield`, `blueprint`. The settings' Quicken with Output row shows for every
  backdrop that quickens.
- Demo surface `agent` (a made-up agent session in the shop, titled as Claude Code titles itself), and
  `site_shots.sh looks` takes agent, aurora, starfield and blueprint.

## Vision Pro: Keys

- Apple: `inputAccessoryView` "isn't available" to an app built for visionOS; use a bottom ornament. So the Terminal
  Keys menu, which lives in the keyboard accessory, never showed on the headset.
- `TerminalKeysMenu` in the terminal's bar on visionOS: Escape, Tab, Control for Next Key, Navigation (arrows),
  F1–F12. It calls `SwiftTermHostModel.press(_:)`, which reaches the accessory object (installed on every UIKit
  platform, shown on none there) and sends what its menu sends.
- `help/terminal-sessions.md` said the keyboard bar was on Vision Pro, and listed Navigation on iPhone and iPad, where
  the menu has none; both corrected.

## The Duo half open (measured by a background agent, simulator iOS 27.1)

| Pose | Window | Fold (division region) | Keyboard |
|---|---|---|---|
| Laptop (fold across) | 669×951 | y456–496, active | 669×496 from y455: the lower half; keys from about y553 |
| Book (fold down) | 951×669 | x456–496, active | full width, keys split around the fold |
| Open, flat | 669×951 | same, inactive | 350 tall |

- **Today, laptop pose:** with the keyboard up, the terminal ends at about y373 and the accessory bar sits above the
  fold; the strip between the fold and the keys is empty. Without the software keyboard, the rows run across the fold.
  In the book pose, Tools sits on the fold.
- **APIs (iOS 27.1 SDK):** `onHingeChange` / `UIHingeInteraction` (status, angle); `GeometryProxy.reservedRegions(kind:
  .division)`; `ArrangementView` (split, overlay).
- `GlassDeviceFold` (GlassConnectionUI): the active fold crossing a view, re-read on every hinge update.
  `GlassDeviceFoldTests` uses the measured frames.

## The Duo half open: built (his "move these to the lower part?")

- **The strip below the fold** (the background agent, a probe app): in the laptop pose, with no prediction row (a
  terminal has none), the keyboard frame starts at the fold but the keys only at y556. The app's own pixels show in
  the 60 pt between, and taps reach it. iOS puts an `inputAccessoryView` (y412–456) and SwiftUI's `.keyboard` toolbar
  above the fold. The book and flat poses have no strip.
- **Laptop pose:**
  - `TerminalWindowView` (iOS) lays the terminal in the top half and `laptopBar` below the fold: keyboard, Tools with
    `TerminalArrowPad`, Keys. It ignores the keyboard's safe area there.
  - `SwiftTermHostModel.setKeyboardAccessoryWithheld` withholds the accessory. A keyboard that is up is put away and
    asked for again, as UTM does.
- **Book pose:** the bottom Tools sits in the trailing half, and the accessory keeps its middle clear
  (`keepsOffMiddle`, `setKeyboardAccessoryKeepsOffMiddle`).
- **Checked on the simulator** (XCUITest taps, no mouse):
  - Laptop, keyboard up: the terminal fills y38–429, the bar y500–544, keys from y560. The pad, Keys ▸ Escape and
    the keyboard button work.
  - Laptop, keyboard down, the book pose and flat: pass.
  - **Two defects found and fixed:**
    - Flat → half open with the keyboard up kept the flat layout. A hinge update came before the region read active,
      and nothing read it again. Now it is read again after 250 ms and 1 s, and a sized region counts while the hinge
      says partly open (`GlassDeviceFoldTests.hingeFirst`).
    - The iPhone tabs container's `terminal-workgroup-tabs` was every control's identifier inside it. It is now an
      element of its own (`.accessibilityElement(children: .contain)`).

## The Coding Agent look: the first pictures had no mark

- **Too faint:** under light text the readability ceiling holds a backdrop to about 0.08 luminance, and the scrim
  goes over that. A mark at 18% opacity started below it and vanished. Now the mark is 70% idle and 35–50% working,
  and the smoke 85% working and 30% idle, enough to reach the ceiling. `TerminalAgentBackdropRenderTests` renders it
  offscreen (red over 0.2 in the middle; the faint one measured 0.08).
- **Not redrawn:** a backdrop that first found no agent (the title not yet set) read nothing observable and was given
  a closure SwiftUI doesn't compare, so it never drew again. It now takes the window's agent as a value as well, and
  reads the output's activity first, so it is drawn again as output starts and stops. Seen on the Duo simulator and
  the VM: the Claude mark behind the text.
- Aurora's curtains and Starfield's stars were strengthened for the same ceiling.

## Pictures (the VM)

`site/static/shots/mac-look-{agent,aurora,starfield,blueprint}.webp`, from `site_shots.sh looks`. The agent shot finds
its window by the title the agent sets ("✳ Claude Code"). README: a row with Coding Agent and Blueprint.

## Tests

- **Suites:** terminal 964, with six live-tmux, PTY and timing tests failing under the load of the VM and simulator
  runs. All 12 tests in their suites pass alone. GlassConnectionUI 59 (+5 fold).
- **Builds:** Mac, iOS and visionOS.
- **Looks** (`TerminalLooksTests` +4): the new starting points, the agent look and its colour, the accents, and the
  smoke's frame. The shader list grew by four. Seen failing with the agent rules broken.
- **Headset** (`GlassTerminalOrnamentUITests.testKeysAreInTheBar`): first found Keys twice. `.help` before the
  accessibility modifiers gave a wrapper the same name; the order now matches the font-size menu's.
  - With a temporary log in `press` and the accessory's `send` (removed after), the simulator showed Escape sent as
    `1b` and Up as `1b 5b 41`, each to the terminal's delegate, where typed keys go.
  - A demo terminal's "Ignoring terminal input" debug line never appeared in `log stream`, so it isn't the evidence.
