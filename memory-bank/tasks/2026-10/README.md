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
- 2026-10-13 (19:40): [Spike: machines in the Finder and Files (D72 phase 5)](2026-10-13_file-provider-spike.md) — in progress.
