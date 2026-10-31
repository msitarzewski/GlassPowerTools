# The iPhone Duo half open: the work above the fold, a deck below (2026-10-31)

**Ask (the owner):** "we also have no images for the iPhone Duo. I'd like for the folded (in half) versions of our
tools to leverage the two screens to perfection … the top screen a remote desktop, then the bottom a keyboard and a
toggleable trackpad … A terminal gets the keyboard on the bottom … The database with a keyboard on the bottom … take a
look at some of the really cool implementations for iPhone Duo, and let's create a plan".
**Status:** Approved 2026-10-31 ("go with your recommendations", D93); nothing built. The plan is the owner's doc "Glass Power Tools on the iPhone Duo" (a private
Claude Docs link, not recorded here). Earlier Duo work: `tasks/2026-09/2026-09-20_iphone-duo.md`,
`2026-10-18_duo-day-one.md` (every page folded and flat), `2026-10-21_looks-duo-keys.md` (the terminal half open).

## Today
- Only the terminal reads the fold (`GlassDeviceFold`, `TerminalWindowView.laptopBar`). The desktop, database and
  editor draw across it.
- Laptop pose, measured 2026-10-21 (Xcode 27.1): window 669×951 pt, fold y456–496, keys from about y556 with the
  keyboard up, leaving a 60 pt strip that is ours when there is no prediction row.
- Reusable: the desktop's `TrackpadPointerController` (relative pointer, tap, tap-drag, two-finger right click),
  `DesktopAccessoryKeys`, the remote size following the window; the SQL editor's `SQLEditorCompletionProvider`; the
  record editor; the editor's preview modes and diff viewer; Show All Windows' cards; Watch Log File. The terminal's
  file preview is visionOS-only (`VisionTerminalPathPreviewer`).

## Research (a research agent's report, checked against its sources)
- Apple: content above the fold, controls below; no pose-only features; lay out from reserved regions, not the hinge
  (tech talks 111462–111466, HIG "Designing for iPhone Duo"). The SDK has no keyboard docking and no system trackpad.
- UTM 5.0.7: half open, the bottom half is a keyboard or a touchpad with a switch; keyboard only on a fresh fold;
  re-reads the fold 0, 0.5, 1.5, 3 s after a hinge change. Secure ShellFish, Working Copy, rootshell, Conduit (RDP
  resizes to the screen), Samsung Flex Mode's touchpad, Surface Duo's companion pane and dual view.
- Known limits: keyboard extensions get no reserved regions (forum thread 847963); Split View is a fixed 50/50.

## The plan (proposed)
One shared deck in `GlassConnectionUI`: a strip under the fold (the tool's keys and a keyboard-or-panel switch), then
the system keyboard or the tool's panel. Desktop: screen above, trackpad panel. Terminal: tabs as chips and cards, or
a second tab live. Database: query or results above, completions in the strip, the selected row below. Editor: key
strip, preview or diff below. Book pose: nothing on the fold, two pages. Steps 0–7: check Device Hub on Xcode 27.2;
the deck; desktop; terminal; editor; database; book pose; help, site pictures and App Store Duo screenshots.

## Two services side by side (the owner, same day)
"I'd argue that we should allow two of any of our services in fold like a book mode. A terminal the left, a database
on the right (or whatever)." Added to the plan as step 2, right after the deck:
- Held like a book or open flat on its side, the shell shows any two sessions as two pages (about 455 pt each, near
  the outer display's 466, where every tool was checked on 2026-10-18).
- **Inside one window**, so the 2026-10-13 rule (a phone presents sessions in place, `GlassWindowPresentation`)
  still holds; the system's Split View of two Glass windows may already work (`UIApplicationSupportsMultipleScenes`
  is on, the app just never opens a window itself on a phone) and is checked in step 0.
- New: the shell's page pair, and each tool handing over its session view by id instead of swapping the whole root
  (the terminal's iPhone root, `GlassTerminalBootstrap.platformRoot`, swaps the library for its workgroup today).
- Open on the Other Page, Swap Pages, Close Page; the focused page takes the keyboard; folded, the focused page
  alone; laptop pose, the focused page above its deck. The Mac's crossings (SQL from a terminal, Open in Editor for a
  printed path) land on the other page; on iPhone they are new work.

## Open (the owner's)
The desktop's size half open (follow the top half, recommended); what comes up on a fresh fold; the terminal's
panel; the half-open picture (Apple's image or a Blender render); two terminal tabs side by side later; whether a
physical Duo is available to test on.
