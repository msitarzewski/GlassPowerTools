# 2026-11-19 — Workgroups edited in their panel, no sheet (D112); Get Info (0.4.624–0.4.625)

**Owner and authorization:** his asks, below; local edits, tests, VM and simulator runs, and installs on his Mac (his
"install it on the mac, hold the release" for 0.4.624, and the standing "install mac builds when ready"). Released in
0.4.632 at his word ("commit and release it", 2026-11-21; `9b9a30f2`, `tasks/2026-11/2026-11-20_svg-drop-crash.md`).

## Get Info (0.4.624)
- His ask, after finding a tab's tmux name for a test: "it looks like we need a right click > Get Info... on the tabs".
  Agreed contents: session with Copy, machine, when the session started, folder, what runs, open elsewhere.
- Built: `TerminalSessionInfo` / `TerminalSessionInfoView` (a popover beside a Mac tab, a sheet elsewhere); a Mac tab's
  menu has Get Info… and Copy tmux Session Name(s) (`MacWorkspaceController.sessionInfo`, `…AskingTheMachines`,
  `tmuxSessionNames`); the tab menus on iPhone, iPad and Vision Pro the same (`VisionTerminalWorkgroupView`).
- Checked: unit tests (stand-in hosts and a stand-in for this Mac's tmux), each seen failing without its piece; the VM
  (a right-click helper added to `vmtool`): the panel, the copy; the first run hid the "Open" row below the popover's
  edge (a scroll view kept its first size) — fixed with no scroll view and "Checking…" meanwhile. iPhone simulator UI
  test `TerminalGetInfoUITests` passed, screenshots looked at. Installed on his Mac as 0.4.624.

## Workgroups in the panel (0.4.625, D112)
- His ask: "remove the edit modal and put that directly into the panel itself". Asked, he chose: save as you go (⌘Z
  undoes), every device, and new Workgroups straight into the panel.
- Built: `WorkgroupPanelEditor.swift` (`WorkgroupEditorView` now the panel itself: name as the title, colour, Open in,
  Auto-focus, the tab table with + and −, each tab's fields beneath it (`WorkgroupTabFields`), databases and desktops,
  look; a save 0.4 s after the last change, only when whole; undo through the window's undo manager; a change from
  another device shown again unless it is what was saved). Both sheets deleted. +, Duplicate and "save current sessions"
  save at once and select it with the name focused (`TerminalWorkgroupsModel.focusesNameOf`); a Mac window's Save
  Workspace as Workgroup… saves at once (Replace / Keep Both asked only for a name already used) and opens the library
  on it (`requestShowWorkgroups`). `WorkgroupEditorContext.savedPreset(replacing:)` builds them.
- Checked: unit tests (`WorkgroupPanelEditorTests`, and the hosted-panel test in `MacWorkspaceTests`: shown, it saves
  nothing, past the save delay), each seen failing without its piece; in the VM: New Workgroup, typing its name (the
  list followed), a tab's fields, ⌘Z, Duplicate, the menu without Edit, both kept across a relaunch; the name first sat
  right as a form value — now the title. Return outside a text field still opens the Workgroup (its default button).
- Xcode: he moved to Xcode-beta 27.3 b2; its Metal toolchain was downloaded to build. Releases need a released Xcode.
- Installed on his Mac as 0.4.625 (detached installer), read back, no crash report.
- **Revised after he tried it (0.4.626):** "I want the edit tool to open the modal like before, but without the
  intermediary Edit > list of tabs": the panel stays the Workgroup's editor; each tab is added or edited in its own
  sheet (`WorkgroupTabEditorView`, restored from HEAD) from + and a pencil beside − (as the old sheet's controls had),
  a double-click or Edit Tab in a tab's menu, or a tap on iPhone, iPad and Vision Pro. A tab's Delete in its sheet
  removes it at once (undo brings it back).

## Next
- His word on releasing 0.4.624–0.4.625 (and on batching public releases, and Sparkle installing quietly on quit).
- His iPhone and headset: 0.4.625 device builds are in `tmp/dd-ios-dev` and `tmp/dd-vision`, for when they're reachable.
