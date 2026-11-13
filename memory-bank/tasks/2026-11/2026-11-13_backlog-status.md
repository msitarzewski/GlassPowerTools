# Backlog status — 2026-11-13

**Asked (the owner):** "What remains from the original task lists? It seems like I've just been making stuff up!"
**What this is:** every ID in the 2026-10-12 inventory (`../2026-10/2026-10-12_backlog-inventory.md`), checked
against the code on `main` (c45faa60, plus the uncommitted 0.4.617), the commits since 2026-10-12, the notes,
`site/help` and GitHub. The inventory's crossings-out stopped at 2026-10-13, and only 10 of the 299 commits since
name an ID, so each status comes from searching by topic and reading the code. Two agents each took half of the
IDs. Claude spot-checked B-Q11, B-F1, B-F2, B-F5, B-F45, B-X27, B-R8 and D94 on its own, and agreed with them on
all eight. Statuses only; the order of importance is still the inventory's section 0.

**Words used:** done; partly; open (nothing yet); **owner** (his decision, his device or his server);
superseded; deferred (by design).

## Summary

| Tier | Done since the list | Left |
|---|---|---|
| 1 Machines and data | all 7 (by 10-12) | — |
| 2 Release-gating | B-R1–B-R6: Sparkle key, Developer ID, first release (v0.4.491, 10-20), site, public repository, history rewrite and push; B-Q27, B-Q23 | B-R7 partly (TestFlight yes; App Store submission and the lawyer's licensing answers no); B-V4 two-device run (owner); B-T8 partly; B-R8, B-R9 (owner's word) |
| 3 Daily-use defects | B-X4 (control mode, 0.4.482); B-X14's real fix (0.4.516); B-X15 probably gone | B-X7, B-X12, B-X17, B-X26 (B-X11, B-X19, B-X20, B-X24 done 11-13, 0.4.618); owner: B-X6, B-X10, B-X27 |
| 4 His decisions | B-Q2, B-Q3 superseded; B-Q9, B-Q24, B-Q28 settled | about 20 questions (below) |
| 5 Device and server checks | some headset items seen | most of B-V1–B-V5 |
| 6 Features | B-F32, B-F44, B-F48; B-F40 mostly | SSH sign-in (B-F1–B-F7) untouched; databases (B-F17–B-F30) untouched since 10-12; desktops (B-F31, B-F33–B-F39) untouched; most of the editor's |
| 7 Infrastructure | B-H1–B-H4, B-H9, B-T5 | B-H5–B-H8, B-T1–B-T4 partly, B-T6, B-T7 (CI), B-T9 |

Roughly 36 of the 144 IDs are done, about 20 partly, and the rest are open; about 30 of the open ones wait on
the owner's decision, device or server.

## Decisions, release steps, defects

| ID | Status | Evidence | Left |
|---|---|---|---|
| B-Q1 | owner | D46 still Proposed; only `DesktopPinchProbe.swift` (19e95b76) | his yes, then build |
| B-Q2 | superseded (mostly) | D86 (71e296ec) and D91 (0440f3f0) open a Mac's terminals over SSH from other devices | D50 still says Proposed; the app never adds the key itself |
| B-Q3 | superseded | D83 control mode, one tmux session per tab (485f608c) | D53 still says Proposed |
| B-Q4 | owner | D63 Proposed; D71 left Vision Pro out; Canvas Material shown everywhere (`SettingsView.swift:1098`) | his choice |
| B-Q5 | owner | no `_rfb._tcp` | his call |
| B-Q6 | owner | the W37 folder rule is local only (`MacLocalTerminalStart.swift:101-103`) | his yes |
| B-Q7 | owner | nothing since 10-11 | judge on the headset |
| B-Q8 | owner | desktop Glass default 0.25 (`DesktopWindowSettings.swift:198`); corners rounded | his two choices |
| B-Q9 | done | 55b13f46 (10-10, before the list) | — |
| B-Q10 | partly | ⌘S off the Mac (e3ee5d7e); 13 pt default unchanged | size on the headset; colour at Opacity 0 |
| B-Q11 | owner | `SFTPRemoteEditorView.swift` still present | his word to delete |
| B-Q12 | owner | projects kept, Open disabled where unreachable | hide or keep |
| B-Q13 | owner | table sub-tabs still a system TabView on visionOS | segmented control; the Feedback |
| B-Q14 | owner | nothing since 09-29; desktops and Active reworked since | describe or close |
| B-Q15 | owner | never reproduced; 0.4.516's whole-list fix may explain it | answers or close |
| B-Q16 | owner | no restored-draft notice; audit log keeps the WHERE shape by design | his two answers |
| B-Q17 | owner | Save still in the New group (`GlassShellFileCommands.swift:109-114`) | his call |
| B-Q18 | open | display windows placed on visionOS (2b4f75f0); VNC still shows a size; collisions and ⌘K/⌘O/⌘T unchecked | four checks |
| B-Q19 | owner | no Paste Text item; D103 is a different thing | what he meant |
| B-Q20 | owner | D29 Proposed | approve or drop |
| B-Q21 | owner | `HostServiceKind` rdp/ssh/database; schema in production since 10-18 | now a production schema change |
| B-Q22 | owner | `.rdp` import refuses a gateway | his call |
| B-Q23 | done | downloads on GitHub Releases (`site/static/appcast.xml`) | — |
| B-Q24 | done | site pictures (10-17), store screenshots (10-18, 10-31) | — |
| B-Q25 | owner | never written down | his ideas |
| B-Q26 | owner | the three package repositories unarchived, READMEs unchanged | with B-R8 |
| B-Q27 | done | history rewritten and pushed 10-18 at his word | — |
| B-Q28 | done | D101: SwiftTerm 1.20 vendored with patches (6c7a03aa) | revisit at SwiftTerm 2.0 |
| B-R1 | done | `Config/Identity.xcconfig:52` | — |
| B-R2 | done | Developer ID profiles; nine notarized releases | sync on a notarized copy not separately recorded |
| B-R3 | done | v0.4.491 (10-20) through v0.4.616 (11-11) | — |
| B-R4 | done | site live since 10-18; feed uncached | — |
| B-R5 | done | public; private vulnerability reporting on | — |
| B-R6 | done | 10-18 | — |
| B-R7 | partly | TestFlight external (616 approved, iOS and visionOS); privacy manifest; encryption key; listing text | App Store submission; the lawyer's licensing answers |
| B-R8 | owner | glas.sh, glassdb.app and the three package repositories not archived; glas.sh PR #36 open (checked 11-13) | his word |
| B-R9 | owner | nothing sent upstream | his word |
| B-X1 | done | e56a57f3 | — |
| B-X2 | done | 7a47183d | — |
| B-X3 | done | 9d4fc68d; 0440f3f0 | — |
| B-X4 | done | D83 control mode (485f608c, 0.4.482) | his confirmation not recorded |
| B-X5 | done | 9ee28f3a; cf5c64ed by design | — |
| B-X6 | owner | the Graphics choice exists (3ca46603); the colour defect is unfixed | his try of H.264 (4:2:0) on the GNOME host |
| B-X7 | open | Automatic still uses the display scale (`DisplayGeometry.swift:105`) | fix, check on the headset |
| B-X8 | done | aaf37994 | — |
| B-X9 | done | b90327f9 | — |
| B-X10 | owner | breadcrumb still from `tabState.displayed` (`DatabaseWorkspaceView.swift:1144-1146`) | his design call |
| B-X11 | done (0.4.618) | Format, History, Saved Queries on a table tab; the menu scoped to its window (`2026-11-13_small-defects.md`) | Explain stays a SQL document's |
| B-X12 | open | never rechecked | look at a grid |
| B-X13 | done | 461dc598, b1e9e3c1 | — |
| B-X14 | done | the real fix is 03a86e9c (0.4.516) | builds before 0.4.516 still save whole lists |
| B-X15 | probably gone | no such warning in the Mac's log for 7 days; a different onChange one on 11-10 | look at the onChange warning |
| B-X16 | stale | no recurrence recorded | close unless it recurs |
| B-X17 | open | cause unknown | investigate |
| B-X18 | done | 44f6b2aa | — |
| B-X19 | done (0.4.618) | library search (55b13f46); schema rows are buttons, the click their default action | — |
| B-X20 | done (0.4.618) | `DatabaseWorkspaceNotFoundView` keeps a window's size | — |
| B-X21 | done | f2c19508 | S6, S7 need a Citadel change, or accept |
| B-X22 | done | be02fe54, 9f2532ad | — |
| B-X23 | standing rule | every device on 0.4.617 (11-12) | keep them on one build |
| B-X24 | partly (0.4.618) | Insert Path brings its Mac terminal forward, pane focused | two never-reproduced reports |
| B-X25 | done | fd729b14 | — |
| B-X26 | open | never rechecked | look on the headset |
| B-X27 | owner | finished downloads, recordings and captures still `complete` (`SessionRecorder.swift:505`, `SFTPBrowserView.swift:4531`); newer writers too (`TerminalCommandHistory.swift:235`). Downloads in progress have used complete-unless-open since 09-10 | his protection-class decision |

## Features, checks, housekeeping, tests

| ID | Status | Evidence | Left |
|---|---|---|---|
| B-F1 | open | `SSHCredentials.swift:96` throws; the form refuses SSH Agent (`ServerFormViews.swift:232`) | agent sign-in and forwarding |
| B-F2 | open | no keyboard-interactive or certificate code | MFA and certificates |
| B-F3 | open | message fix only (44f6b2aa) | ECDSA keys from a file |
| B-F4 | open | — | all |
| B-F5 | open | help `terminal-files.md:35,42` | folder upload, download, drop; non-empty delete |
| B-F6 | open | `SSHConfigParser.swift:28,87` refuses Include and Match | saved forwards; config import |
| B-F7 | open | recorder lists and deletes only | player, export, retention |
| B-F8 | partly | OSC 133/633 parsed (D102), used by type-ahead; path menus and previews (D76) | command blocks shown; exit-status marks |
| B-F9 | open | terminal AI unchanged apart from a pause switch | all |
| B-F10 | partly | Vision Pro on Metal (0.4.606); changed rows only (0.4.566) | ring storage, disk history, benchmarks |
| B-F11 | open | — | all |
| B-F12 | partly | SwiftTerm 1.99 tested (11-05); D101 | libghostty never evaluated |
| B-F13 | partly | Handoff, Open N as Tabs In, synced workgroups (D91, D94); D44 stage 2 never approved | "open the same set here" |
| B-F14 | open | Tailscale still a toolbar window | a library panel |
| B-F15 | partly | Tabs, Grid, Carousel on iPhone and iPad (D99) | a workgroup switcher; Zellij |
| B-F16 | partly | Auto-focus on activity; bell glow | last display and frame; idle policy |
| B-F17–B-F26 | open | no database feature work since 10-12 | all |
| B-F27 | open | saved queries device-local; Siri entities only (662cf122) | folders, tags, sync |
| B-F28 | open | — | SQL from the editor; the Cancel warning |
| B-F29 | open | iPad crash fix only (7493831c) | all |
| B-F30 | open | — | all |
| B-F31 | open | — | all |
| B-F32 | done | 3ca46603 | — |
| B-F33–B-F39 | open | desktop windows not restored (`GlassDesktopScenes.swift:49,75`) | all |
| B-F40 | mostly done | D94 (e139efc0, 0.4.574) | a desktop in the terminal window's grid; a real-server try |
| B-F41 | partly | git over the project's SSH (0.4.519–0.4.558) | `rg`, server LSP, the consent design |
| B-F42 | open | 16 grammars, no injections | all |
| B-F43 | open | 0b5d4210 only | all |
| B-F44 | done | aa06f515, D93 | no physical Duo tried |
| B-F45 | open | one shared Mac editor frame since 09-17 | per window; iPad and Vision Pro |
| B-F46 | open | no Close Project command; ignore list fixed | all |
| B-F47 | partly | tab names for VoiceOver; Speech and Spelling (0.4.595) | device checks; M-8 gutter; ambient light |
| B-F48 | done | D72 phases 1–4; saved queries (662cf122); tables declined on purpose | his try of Siri and Shortcuts |
| B-F49 | open | palette Mac-only (`GlassCommandPalette.swift:22`); contents grew | other platforms, typo tolerance |
| B-F50 | open | fixed widths (`GlassSpatialColumns.swift:52,237`) | resizable, remembered |
| B-F51 | open | Rename, Copy, Export, Delete only | detach; type to delete |
| B-F52 | partly | This Mac knows its library machine (D86) | Files on This Mac, tags, export |
| B-F53 | open | `GlassSpatialMetrics` 34 references (was 24) | the unwind |
| B-F54 | open | accent asset still empty | six ideas |
| B-F55 | deferred | prototype has no caller | — |
| B-F56 | partly | keys not on this device; removals that stay (D79); iCloud signed out said plainly | rotation, revocation, recovery, account switch |
| B-F57 | deferred | — | — |
| B-V1 | partly | orbs, dock, Files window, hp-decoder-check, Metal terminal seen on the headset | widgets, Reduce Transparency, tilt, schema volume, remote project, W15/W21/W26 |
| B-V2 | mostly open | VoiceOver in the simulator only | the list |
| B-V3 | partly | ran on macOS 26.6 (VM, 11-06) | widget taps, High Performance with a real Mac, Open With, 26.0 exactly |
| B-V4 | owner | never run | all |
| B-V5 | mostly open | Windows 11 graphics modes, GNOME clipboard, tmux 3.6 control mode done (not on the list) | every listed check |
| B-H1–B-H4 | done | 2aed1f7e | notes drifted since (techContext:388 says the first release is still to come) |
| B-H5 | open | `ConnectionEditor.swift`, `createSFTPSession(sharing:)`, `HostCatalogDeletionOutbox.swift`, `glassdb.` keys and loggers | all |
| B-H6 | partly | overview cards use Show All Windows' tile (D96, D99) | RDPKit README; `ConnectionPreflight.swift` (7,092 lines) |
| B-H7 | open | — | test leftovers |
| B-H8 | blocked upstream | tree-sitter 0.27, swift-crypto 5, mysql-nio fork | upstream |
| B-H9 | done | 10-12; v1.99 went to B-Q28 | — |
| B-T1 | partly | demo-open for databases and desktops; iOS database UI tests on the VM | glassDT's 14 tests; parity sweep |
| B-T2 | partly | visionOS service-address test fixed (11-05) | search test still skipped; no full visionOS run |
| B-T3 | partly | live database reconnect tests on (10-24) | Mac UI tests never run |
| B-T4 | mostly done | test audit (03a86e9c) | MockKRDP and xrdp flakes not recorded as settled |
| B-T5 | done | 3,368 tests on 11-05 | — |
| B-T6 | open | — | the security pass |
| B-T7 | open | `.github/` holds only FUNDING.yml | CI |
| B-T8 | partly | advisory scan, accessibility audit, large text, Local Network denial | Instruments, IME, layouts, devices |
| B-T9 | open | — | the grammar review |

## Not settled

- B-X12, B-X17, B-X26, B-Q7, B-Q14 need a device, a host or his eyes.
- B-Q15 and B-X16 were never reproduced.
- The B-V items count as done only where a note records them. He uses the iPhone and headset daily, so some may
  have been seen without being written down.
- B-F13 and B-F15: whether what was built answers the original ask is his call.

## What the month went to instead

Of the 299 commits since 10-13, most went to work the list doesn't hold. Some was asked for in his daily use:
Show All Windows, the orbs and their dock, Focus Mode rooms, agent marks, Scale Text, previews, type-ahead,
the Duo pages and Git in the editor. The rest was release work: the site, TestFlight and nine Mac releases. From
the list, the release path (tier 2), B-F40, B-F44, B-F48 and B-X4 landed. Tiers 3, 5 and 6 were barely touched.
