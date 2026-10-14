# Tier 3, the evening of 2026-10-13 (the owner away)

**Authorization:** "go with your recommendations, commit each piece as it lands"; Mac builds installed when ready.
The owner was out ("I'll test when get back"); phase 5's spike stopped where it needed him
(`2026-10-13_file-provider-spike.md`), so the agent queue in `activeContext.md` came next.
**Owner:** the agent. **State:** done; on the Mac as 0.4.412. The iPhone and Vision Pro were unreachable
(CoreDevice 4016) and are still on 0.4.409.

| Item | Commit | What changed | Evidence |
|---|---|---|---|
| B-X2 | 7a47183 | The editor checks for an outside change as its window comes forward (the Mac's key window; the scene becoming active elsewhere) and as a tab is chosen, not only at save. A copy without edits is offered Reload and Keep Editing, never Save Anyway. A touch, a machine that does not answer, or an unchanged file raises nothing. One question per change. A check that overlaps the editor's own save stands down | `GlassEditorOutsideChangeTests`: 6 tests; the overlap and once-per-change guards each fail without them |
| (found on the way) | 7a47183 | The local-read tests timed a read from its request, so six more main-actor tests queued them past their 3 s deadline. They now time from the read's start | A 5 s read still fails them; the full editor target passes twice |
| B-X22, second half | 9f2532a | A project on a saved machine that is this Mac by its pinned host key opens from the disk (Projects panel, Files ▸ Open in Editor), not over SSH to itself | Fingerprint test fails on raw key blobs. Not yet seen with the owner's own library |
| `databaseSidebarChrome()` | 9f2532a (notes) | Looked at again under D24's amendment. There is no dead end: on a regular width the database places the editor's `GlassSidebarToggle` (W32), a compact width is a stack, and the headset has its own toggle | No change |
| B-F32 | 3ca4660 | Settings ▸ a Desktop service ▸ **Graphics**: Automatic, H.264 (4:2:0) or Without H.264, saved per service. It maps to RDPKit's capability profiles (`.automatic`, `.avc420` = RDPGFX 8.1, `.legacy` = 8.0). A record from before reads as Automatic, and so does an unknown value. Screen Sharing carries none. The session logs the version the server chose (`event=graphics`) | 3 tests, each failing without its piece. **Live, Windows 11 VM:** see below |

| B-F48's tail: saved queries | 0.4.413 | Saved queries as Siri and Shortcuts entities: "Open the ‹query› query in Glass Power Tools" opens it in a new SQL tab on its database, titled with its name, unrun. A live workspace comes forward; otherwise the shell connects as the library does and the query waits for the workspace (two minutes at most). Only queries whose database is still saved are offered, by name and "‹service› on ‹machine›", never their SQL. Tables are not entities (schema names would go into the App Group) | 5 database tests and 2 widget-data tests; each database test fails without its piece. Siri and Shortcuts not tried: the owner's |

| Black backgrounds show the glass (the owner, back, 23:10: "btop's black is black and not transparent … the other colors are fine at 100%") | 0.4.414 | SwiftTerm leaves a cell clear only when its background is the default one; btop paints `48;2;0;0;0`, so its cells were solid black over the glass. `TerminalClearBlacks` (GlassTerminalEmulator) rewrites an SGR background that resolves to pure black (under a dark theme) or to the theme's own background colour into `49` before SwiftTerm reads it, on all four ways output arrives (SSH on iPhone and Vision Pro, SSH and local on the Mac). Foregrounds, other colours and other sequences are untouched; a sequence split between reads is held. Under a light theme black stays black, or btop's light text would sit on light glass | 6 tests, one through a real SwiftTerm terminal; the split, light-theme and extended-colour rules each fail without their code; all 798 terminal tests pass, unlocked, tmux unchanged. Not yet seen on screen by the owner |

| Favorites beyond machines (D73; the owner: "machines OR services OR projects OR Workgroups OR SFTP (at the current folder depth)", sections by kind) | ff190a4 (model), then 0.4.415 | `GlassFavorite` (service, project, workgroup, folder) synced under its own key by D49's rule; Favorites draws a section per kind under its machines (`GlassLibraryExtraSections`, counted in the sidebar, searched); stars in a service's menu, a project's and a saved workgroup's, and Files' toolbar; a folder opens Files there (`requestFiles`) or as a project. No terminal-in-folder yet | 7 shell tests (merge rule and folder validation each fail without their code); shell, library, editor, terminal and widget-data targets pass; not yet seen on screen |

| Desktop clipboard (the owner, 2026-10-14: "Clipboard sharing is disabled or was not negotiated", RDP and VNC?) | 0.4.417 | An RDP server opens its clipboard with Monitor Ready, not with the desktop; the Mac sent its clipboard as the window came forward, so the first copy failed into that banner. Now a copy waits (the latest only) and goes when the clipboard opens (`.clipboardReady`); after 20 s still closed, the desktop says why once. VNC is open on connect. Logs: `event=clipboard-ready`, and at the end `event=clipboard channel=… ready=… messages=…` | 4 tests (fail without the hold). **Windows 11 VM:** channel 1005 assigned, no clipboard messages, because the RDP session sits at the sign-in screen (the console user is signed in; Windows offers to sign them out), so no rdpclip — not representative. **The owner's GNOME host:** to be read from the new log lines |

## B-F32 against the Windows 11 VM

Run through a loopback tunnel via the scratch VM, because this shell has no Local Network access ("No route to host").
NLA, with the certificate pinned.

| Mode | Server's confirm | First frame | Decode |
|---|---|---|---|
| Automatic | 10.7, flags 0x42 (AVC thin client, small cache) | 1280×800, 0.62 s | hardware (H.264) |
| H.264 (4:2:0) | 8.1, flags 0x02: **AVC420 not enabled by Windows** | 1280×800, 0.62 s | not H.264 |
| Without H.264 | 8.0, flags 0x02 | 1280×800, 0.41 s | not H.264 |

- Windows 11 declines H.264 at 8.1, so on Windows, "H.264 (4:2:0)" means the server's other codecs. The help says
  a computer that does not offer it sends its other pictures.
- **B-X6 itself was reported on a GNOME host and is not reproduced here.** The owner tries H.264 (4:2:0) there.

## Still open from the queue

- B-X6: needs the owner's GNOME host. Glassdt's plan was expected-pixel tests.
- B-X7: Vision Pro asks for twice the pixels; whole-frame copies. Needs the headset to measure and to judge.
- B-Q11: delete the legacy sheet. The owner's call, now unblocked by B-X2.
