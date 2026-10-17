# October 2026

- 2026-10-01: [tmux sessions and Active across devices (D44)](2026-10-01_tmux-sessions.md) — stage 1
  built: per-server tmux, reattach, Active's running sessions, availability check and one-time offer,
  Detach wording, tmux-aware closing, directory from tmux. Desktop passwords lost through a merged
  duplicate: fixed (same commits' notes in `activeContext.md`).
- 2026-10-04: [iPhone landscape terminal and AI fixes that are advice](2026-10-04_iphone-landscape-and-ai-fixes.md);
  menu icons; tests that waited on time made to wait for events.
- 2026-10-05: [RDP in-session bandwidth](2026-10-05_rdp-session-bandwidth.md) — 0 bytes reported to
  Windows; fixed and verified live.
- 2026-10-05: [A database through another machine (D45)](2026-10-05_db-through-another-machine.md),
  and a Database address through the database's own machine.
- 2026-10-05 → 07: [Vision Pro input, the bolt, and the scroll edge](2026-10-06_visionos-input-and-scroll-edge.md)
  — trackpad scrolling, the Active Connections bolt on the right, pinch-pose measurements for D46.
- 2026-10-07 → 08: [Terminal tabs, local tmux and sync](2026-10-07_terminal-tabs-and-local-tmux.md) —
  one row height across library lists; tab names, rename, activity wave, Finder drop, dragging tabs
  between windows; local terminals in tmux (D47) that survive installs and reattach; SwiftTerm 1.20 and
  a weekly dependency check (D48); scrolling in tmux everywhere; favourites (D49) and workgroups (D51)
  sync; the headset's Connections-window lockout; D50 proposed. Committed, installed.

- 2026-10-08: [Plan: terminal find, new tabs, tmux names, workgroups, editor windows](2026-10-08_find-tabs-tmux-workgroups-editor-plan.md)
  — eight owner reports researched by five read-only agents. Root causes: find (output erases the hit;
  only tmux's visible screen), "+" opens an empty chooser tab, a twin window controller behind the
  drag "copy", `-A` joining a session by name, workgroups without tmux names, `modifiedAt` never
  saved (D51 defect), editor projects piling into the front window. Five workstreams; awaiting go.
- 2026-10-12: [This Mac's tmux server under launchd (D66)](2026-10-12_tmux-under-launchd.md) — a Force Quit of an app
  run from a pane ended every local terminal; the resource coalition, reproduced with a probe; launchd's server survives
  the same Force Quit. Installed 0.4.373 (Mac).
- 2026-10-12: background-mode tmux host (D66 revised, 0.4.374) and terminals without tmux (D67, 130c879): New Basic
  Terminal Tab, Basic Terminal per host, tmux settings in Settings ▸ Terminal. Same task note.
- 2026-10-12: Wrap Long Lines off ignored on iPhone (8b444a9): reproduced on the simulator (wrapped at open; unwrapped
  lines unreachable), fixed in `GlassTextViewIOS`; new `GlassEditorUIKitTests` (procedure in `techContext.md`).
  Also "+" ▸ New Terminal on lists machine names (47b7df8, 107f1be).
- 2026-10-12: editor projects on another machine reconnect when their SFTP connection has gone (fc7653e): the
  iPhone's "NIOCore.ChannelError error 5" (outputClosed) on default.profraw; empty files read fine (live test).
  `GlassTerminalReconnectingLister`; live editor suite 9/9 on scratch via a loopback tunnel. 0.4.380 on all three.
- 2026-10-12: [Widgets: Machines and Active (D68)](2026-10-12_widgets-machines-and-active.md) — the dead "Recent
  Servers" replaced; snapshot + App Intents; iPhone/iPad, Vision Pro and now the Mac. 0.4.382 on all three. Also
  iPhone workgroup tap fixed (276117e).
- 2026-10-12 (after the compaction): the VNC setup sheet's warning follows the user name — a Mac account is encrypted
  since e7463ce, a password alone is not (new draft test; help page matched).
- 2026-10-12: [Backlog inventory](2026-10-12_backlog-inventory.md) — everything open across this project, glas.sh,
  glassdb, glassDT and the absorbed packages, checked against the code; IDs B-Q/R/X/F/T/H. Found on the way and
  fixed: SECURITY.md's VNC paragraph; a real database name in a test (rule 61).
- 2026-10-12: backlog tier 1 done, each fix shown failing without it: local editor reads bounded and off the main
  actor (B-X1), saves relative to the folder held open (B-X9, pen M-2), Citadel C12 (B-X21), SSH keys not on this
  device kept (B-X3), stale lists cannot delete synced records (B-X14), regex find stopped at one second (B-X8, pen
  H-3). 0.4.390 on Mac, iPhone and Vision Pro.
- 2026-10-12: [Backlog tier 2](2026-10-12_backlog-tier-2.md) — CVE-2026-43798 (swift-nio-ssh, critical) fixed first;
  sleep/wake liveness, iPhone Duo, docs, DOMPurify record, swift-log/nio, full suite green; licensing research,
  two-device checklist and the owner's decisions recorded. iPhone and Vision Pro on 0.4.391.
- 2026-10-12 (late): the iPhone Duo on its simulator (iOS 27.1 runtime): fold-aware window gate (fac5ead), titles on
  the large-title line in two-column layouts (132007c, detail-column modifier), scratch and Windows 11 in the
  simulator's library; owner's next asks recorded in `activeContext.md` (Active by service, four Duo defects).
- 2026-10-12 (late, after the compaction): Active with nothing open offers the library's machines by service
  (Terminal, Database, Desktop) — the detail page beside the list, or the list itself on a compact stack; seen on the
  folded Duo and an iPad in landscape. Details in `activeContext.md`.
- 2026-10-13 (overnight): tier 3 begun — tree-sitter's match limit instead of vendoring (0b5d421); every terminal on a
  lost shared connection says so (B-X5); Local Network guidance only for "No route to host" (B-X13); B-X18; B-X22's
  first half. Found: B-X27, complete file protection on a locked Mac (the owner's call). All three on 0.4.392.
- 2026-10-13: [The owner testing: Duo, headset, desktops, Show All Windows, terminal windows, database errors](2026-10-13_owner-testing-day.md)
  — the folded Duo's corners and sidebar toggle (D24 amended); held keys and selection on the headset; desktops'
  unavailable view and a way back on phones; Show All Windows across every kind of window, Blur previews; one Command
  Palette; a Quick Look crash; SSH panes in terminal windows (D70: a connection belongs to its controller); the
  database's Local Network rule and PostgreSQL's connect errors; tunnels keep their own connections (D69). 0.4.400
  on all three; the owner confirmed the last fix.
- 2026-10-13 (16:10): [Plan: system integration](2026-10-13_system-integration-plan.md) — the owner: "Let's get a
  finder integration going … App intents, all of the modern stuff … Be sure visionOS is well represented!" Five
  phases (entities and intents; the Finder; sharing and drag-out; Controls, search and snippets; File Provider spike),
  a platform table from Apple's documentation, Vision Pro phase by phase, six decisions for the owner. Proposed.
- 2026-10-13 (19:40): [Spike: machines in the Finder and Files (D72 phase 5)](2026-10-13_file-provider-spike.md) — done
  as far as it goes unattended; registering a domain waits for the owner.
- 2026-10-13 (22:30): [Tier 3, the evening](2026-10-13_tier-3-evening.md) — B-X2 (the editor looks again when its
  window comes forward), B-X22's second half (this Mac's projects from the disk), B-F32 (a Graphics choice per
  Desktop service, live on the Windows 11 VM). 0.4.412 on the Mac; devices unreachable.
- 2026-10-14 (22:15): [The owner testing: All Windows everywhere, agents, clipboard, the palette](2026-10-14_all-windows-agents-clipboard.md)
  — All Windows on iPhone, iPad and Vision Pro (pull down, hold ⚡, Siri), 28 AI agents marked, the desktop clipboard
  both ways with GNOME and Sync Automatically, the Command Palette's services and lists, the terminal's link and path
  menu. 0.4.444 on the Mac and iPhone; the headset locked since 0.4.423.
- 2026-10-14 (23:55): [All Windows as the Mac lays it out; the headset's window](2026-10-14_all-windows-mac-layout-headset.md)
  — a card per tab grouped by machine with the Mac's layout and live pictures; All Windows a window of its own on Vision
  Pro; Connections 1180 wide there; the editor's square corners. 0.4.445.
- 2026-10-15 (overnight, to ~05:00): [the same note, continued](2026-10-14_all-windows-mac-layout-headset.md) — a new
  file's save to a project on a server (live on scratch), ⌘S off the Mac, Active's Open as Tab In and Open N as Tabs
  In, the + of a terminal window held and the Mac's + listing running terminals; on Vision Pro, selection and a held
  link's or path's actions, one Tabs/Grid/Carousel toggle, Auto-focus on activity, and session windows that shrink
  into an orb (D74) with the window's tabs on a ring and names that stay while read. 0.4.453.
- 2026-10-15 (~06:50): [the same note, continued](2026-10-14_all-windows-mac-layout-headset.md) — selection with
  tmux's mouse on and on-device selection diagnostics, orb names against their dots, database and editor orbs showing
  their window, a desktop's shape held again after its orb, the Files window's corners. 0.4.454.
- 2026-10-15 (afternoon) to 2026-10-16 (~10:25): [the same note, continued](2026-10-14_all-windows-mac-layout-headset.md)
  — tmux 3.8's mouse (the yellow selection, no scroll), selection as Apple's text does, iPhone tabs and All Windows,
  the iPhone desktop's bars and title, file previews over a Mac terminal (D76), the Mac install that waited on the tmux
  host. 0.4.462 on all three.
- 2026-10-16 (~10:30 to afternoon): [A terminal window that resizes, and one that scales](2026-10-16_terminal-resize-and-scale.md)
  — D75 built: When Resized (setting, This Window, Scale Text in the bar); the grid kept and the drawing scaled; the
  window held to its shape (the desktop's lock, now GlassShell's); ⌘+/⌘−/⌘0 size the window. Vision Pro, Mac, iPad.
  394fb47, 3feb28a, 2914f3f; 0.4.463. For the owner to try.
- 2026-10-16 (evening): [A terminal window's sidebar adds to the window (D77)](2026-10-16_additive-sidebars.md)
  — opening or closing the Mac terminal window's sidebar grows or shrinks the window; the terminal keeps its size
  and place (AppKit's collapse behaviour on SwiftUI's split items). Not for the sidebar a window opens with, the
  overview, full screen.
  On 0.4.464 reopening snapped: the window's minimum fought AppKit's growing; now the terminal column's. Same evening,
  D75 on iPad: ⌘+ grows a scaled window, sharp scaled text (simulator). 0.4.465.
- 2026-10-16 (evening): [3D models (D78)](2026-10-16_3d-models.md) — USDZ/USD/Reality everywhere files open:
  RealityKit on Mac/iPhone/iPad (AR Quick Look on touch), Quick Look volume on Vision Pro; model links open in 3D.
- 2026-10-16 (evening): [A dropped screenshot that "just disappears"](2026-10-16_drop-typing.md) — the file
  arrived, nothing was typed, silently; a waiting paste review no longer turns drops away; every step logged.
- 2026-10-17 (morning): [the D77 note, continued](2026-10-16_additive-sidebars.md) — from the owner's recording:
  "+" and the title stay put as the sidebar opens and closes ("keep the + and title fixed"; a held room before "+"),
  and the frame on every opening where the toolbar showed the window behind is gone (the titlebar material waits out
  AppKit's mid-opening layout). W19's SSH naming test waits for the note it counts. 0.4.468.
- 2026-10-17 (late morning): [the D77 note, continued](2026-10-16_additive-sidebars.md) — the gray line at the
  sidebar's edge ("That's what we need to eliminate"): AppKit's split divider and our hairline, gone from the terminal
  window (the divider made transparent, still draggable). 0.4.469.
- 2026-10-17 (noon): [the same note](2026-10-16_additive-sidebars.md) — the space held before "+" closed again at his
  word ("It moves anyway... let's close the space"); "+" slides with the sidebar, as AppKit arranges it. 0.4.470.
