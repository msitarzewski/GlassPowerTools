# Plan: system integration — the Finder, App Intents and the modern surfaces, on every platform

**Owner's ask (2026-10-13, 16:10):** "Let's get a finder integration going — they should be available on all of the
platforms that support them. App intents, all of the modern stuff … Be sure visionOS is well represented!" His
screenshot: Finder ▸ Services with other apps' "New … Tab Here", "New … Window Here" and "Open in …".
**Status:** **Approved 2026-10-13 (D72)**: "Do all of the things. Wonderful ideas!" — every phase, the optional
pieces included; the questions answered as recommended (D72). Building phase 1. Absorbs backlog B-F48 (App Intents, Shortcuts, Spotlight, Handoff;
entities for hosts, connections, saved queries and tables, planned in glassdb and glassDT, never carried).
**Owner:** the agent (coordinator). **Authorization:** the plan only; building waits for the owner's go.

## What exists to build on (checked 2026-10-13)

| Piece | Where | Use |
|---|---|---|
| Three App Intents (connect a service, show a machine, show Active), hidden from Shortcuts, string parameters | `GlassWidgetData/GlassWidgetIntents.swift`; `AppIntentsPackage` in the app and the widget extension | The request path (`GlassWidgetRequests`, held until the app is ready) generalises to every intent |
| Widgets Machines and Active on iPhone, iPad, Vision Pro and Mac (D68) | `Widgets/`, snapshot in the App Group | Become configurable once entities exist |
| A text "Open With" document type (Alternate) and `.onOpenURL` → editor | `App/Info.plist`, `GlassPowerToolsApp.swift:434` | Extend: folders and projects |
| A local terminal at a folder | `MacLocalTerminalStart.intent(in:)`, `newWindowRequest` | Services, Open With a folder, the Dock |
| The editor opens a folder as a project | `GlassEditorScenes.openProject(_:)` | "Open in Glass Power Tools" on a folder |
| Verified, no-clobber upload to a machine (W14) | `TerminalRemoteDrop.swift`, the Files browser | "Send to a Machine" |
| The Mac app is not sandboxed | `Platforms/macOS/macOS.entitlements` | Services receive plain paths |

The original apps had none of this: glas.sh's only system hook was its private `glassh://` scheme, which D4 and D68 removed.

## What each platform offers (Apple's documentation data, read 2026-10-13)

| Surface | Mac | iPhone, iPad | Vision Pro | API, availability |
|---|---|---|---|---|
| App Intents, entities, App Shortcuts (Siri, Shortcuts, Spotlight actions) | ✓ (Spotlight runs actions in 26) | ✓ (+ Action button) | ✓ | `AppEntity`, `OpenIntent`, `AppShortcutsProvider`: macOS 13, iOS 16, visionOS 1 |
| Indexed entities (system search, Siri's knowledge) | ✓ | ✓ | ✓ | `IndexedEntity`: macOS 15, iOS 18, visionOS 2 |
| Files as intent parameters | ✓ | ✓ | ✓ | `IntentFile` everywhere; `FileEntity`: macOS 15, iOS 18, visionOS 2 |
| Interactive snippets | ✓ | ✓ | ✓ | `SnippetIntent`: 26 everywhere |
| Controls (Control Center, menu bar, Lock Screen, Action button) | ✓ 26 | ✓ 18 | — | `ControlWidgetButton`: iOS 18, macOS 26; not visionOS |
| Services menu (the screenshot) | ✓ | — | — | `NSServices`, `NSApp.servicesProvider` |
| Finder Quick Actions and preview pane | ✓ | — | — | action extension, `NSExtensionServiceAllowsFinderPreviewItem`: macOS 10.14 |
| Finder toolbar button and badges | ✓ | — | — | Finder Sync: macOS 10.10 |
| Share sheet extension | ✓ | ✓ | **verify** | a developer reports Xcode calls it unavailable on visionOS yet it ran on a device as an iPhone-compatible extension ([forums 804224](https://developer.apple.com/forums/thread/804224)) |
| Handoff, user activities | ✓ | ✓ | **verify Handoff** | `NSUserActivity`: visionOS 1 |
| Machines as locations in Finder and Files | ✓ | ✓ | **verify** | `NSFileProviderReplicatedExtension`: macOS 11, iOS 16, visionOS 1; App Store upload of a visionOS File Provider UI extension reported blocked ([forums 802442](https://developer.apple.com/forums/thread/802442)) |
| Drag an item out to make a window | ✓ (drag to a new window) | iPad | ✓ (into the room) | `Transferable`: everywhere; `WindowGroup(for:)` |

Sources: Apple's documentation for each symbol (developer.apple.com/documentation/…); WWDC25 sessions 260 and 244
on Shortcuts and Spotlight; Apple's [What's new in Shortcuts … visionOS 26](https://support.apple.com/en-gb/125148).

## Phase 1 — one set of entities and intents, every platform (the base for everything after)

- **Entities:**
  - `MachineEntity`: a library host, by its name and the symbols of its services.
  - `ServiceEntity`: a terminal, database or desktop service.
  - `WorkgroupEntity`.
  - Later, B-F48's saved queries and tables.
  - Queries answer from the shell's library in the app, and from the widget snapshot in extensions. Metadata only:
    no secrets, no credentials (D18).
- **Intents.** Each opens what it names the way the library's Connect does, so host trust is asked as usual and
  never skipped:
  - Open Terminal on ‹machine›, Open Database ‹service›, Open Desktop ‹machine›, Connect to ‹service›.
  - Show ‹machine›, Show Active, Open Workgroup ‹workgroup›.
  - New Terminal at ‹folder› (Mac); Open in Editor ‹file or folder› (`OpenIntent`, `IntentFile`).
  - Send Files to ‹machine› ‹folder›, through W14's verified upload.
  - A failure says the fix in plain words ("Errors say the fix"): an untrusted host cannot be asked about from
    the background.
- **App Shortcuts** with phrases, for Siri, Spotlight (including Mac Spotlight actions in 26), the Shortcuts app
  and the iPhone's Action button: "Open a terminal on ‹machine› in Glass Power Tools", "Show my active
  connections", "New Glass Power Tools window".
- **Widgets:**
  - The three hidden string-parameter intents give way to the entity ones; the widgets keep working.
  - Machines gains a configuration: choose the machine.
- **On Vision Pro**, an intent that opens a session opens a **new window in the room** (`openWindow`), not in
  place. Phones stay in place, as they do now.
- **Tests:**
  - Entity queries against a fixture library.
  - Each intent posts the request it should.
  - The App Intents metadata builds for all three platforms. The toolchain already handles intents defined in a
    package (techContext, 2026-10-12).

## Phase 2 — the Finder (Mac)

- **Services**, as in the screenshot:
  - **New Glass Power Tools Tab Here**, **New Glass Power Tools Window Here**: a folder, or the folder holding a
    file. A local terminal in tmux as the Mac's setting says.
  - **Open in Glass Power Tools**: a file opens in the editor; a folder opens as an editor project.
  - Names carry the app's, as Ghostty's and iTerm2's do, because Services lists titles alone.
  - **To verify:** that they show without being switched on in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸
    Services (`NSRequiredContext`).
- **Open With on a folder**, and a folder **dropped on the Dock icon**: a terminal there.
- **A Dock menu:** New Terminal Window, New Basic Terminal, recent machines.
- **Finder Quick Actions** (an action extension, in the right-click Quick Actions menu and the preview pane): New
  Terminal Here, Send to a Machine…. *Owner's decision (Q2).*
- **A Finder toolbar button** (Finder Sync): "Terminal here" in every Finder window. It must be switched on in
  System Settings. *Owner's decision (Q3).*
- **`ssh://` links:** opening one connects (a saved host when one matches, otherwise a one-off connection with
  the usual host-key prompt). D4 removed the app's private schemes; `ssh://` is the standard one other apps link
  to. *Owner's decision (Q1).*
- **Shell scripts** (`.command`, `.sh`) opened with Glass Power Tools run in a new tab, as Terminal runs them. A
  trust boundary. *Owner's decision (Q5).*

## Phase 3 — sharing, Files and dragging (every platform)

- **Share sheet: "Send to a Machine"** (iPhone, iPad, Mac; Vision Pro once verified). The extension only stages
  the files and the request in the App Group; the app does the upload. No credentials in the extension, and host
  trust is asked in the app. The folder is chosen, or the machine's last one. If the share extension fails the
  visionOS check, the headset keeps Send Files through Shortcuts (phase 1) and its existing drop onto a terminal
  (W14).
- **Drag a machine or service out of the library to make its window:**
  - On Vision Pro, the window lands where you drop it in the room. This is the product's differentiator (a
    machine's terminal, database and desktop side by side).
  - On iPad, a new window; on the Mac, a new window.
- **Handoff:** an open terminal or desktop is offered on your other devices ("Continue on …"). Vision Pro's
  Handoff support needs verifying.
- **Open In from Files** on iPhone, iPad and Vision Pro: text already opens in the editor. Verify it on the headset
  (the Finder's Open With is owed too, B-V3).

## Phase 4 — the system's own surfaces

- **Controls** (Mac 26 Control Center and menu bar; iPhone and iPad Control Center, Lock Screen, Action button):
  New Terminal (Mac), Connect to ‹a chosen machine›, Show Active. Vision Pro has none.
- **Search** (B-F48 said opt-in): machines and workgroups as indexed entities. A Settings ▸ Privacy switch, off by
  default, because it puts machine names in the system's index. *Owner's decision (Q4).*
- **Snippets (26):** Active as an interactive snippet with Disconnect buttons; a machine's status. These work in
  Siri and Spotlight, on Vision Pro too.
- *Optional:* a Focus filter (show only a chosen workgroup's machines during a Focus).

## Phase 5 — machines as locations in Finder and Files (a spike first)

A File Provider extension presenting each machine's SFTP folders in the Finder's sidebar and the Files app (Mac,
iPhone, iPad; Vision Pro after the reported App Store block is checked). The largest item:
- **Sync semantics:** conflicts, offline changes, eviction.
- **Credentials:** the extension needs Keychain access, and host trust cannot be asked inside it.
- **A trust model of its own.**

Proposed as its own decision after phases 1–4, with a spike measuring a read-only browse first.

## Vision Pro, phase by phase

| Phase | On the headset |
|---|---|
| 1 | Siri and the Shortcuts app: "Open a terminal on ‹machine›" opens its window in the room; entities in Siri's knowledge (visionOS 2+); a configurable Machine widget placed in the room |
| 3 | Drag a machine out of the library and drop it where its window should stand (the spatial workspace); share photos or files to a machine (once verified; Shortcuts otherwise); Handoff from the Mac (once verified); Open In from Files |
| 4 | Interactive snippets in Siri (visionOS 26); no Controls (none on visionOS) |
| 5 | Machines in the Files app (after the App Store check) |
| Not on the headset | Services, Quick Actions and Finder Sync (Mac only); Controls |

## Decisions for the owner

1. **Q1** Become a handler for `ssh://` links?
2. **Q2** Finder Quick Actions too, or Services only (as Ghostty and iTerm2 do)?
3. **Q3** A Finder toolbar button (Finder Sync), which the user switches on in System Settings?
4. **Q4** System search of machine names: opt-in (B-F48), or on by default?
5. **Q5** Run `.command` and `.sh` files opened with the app, as Terminal does, or open them in the editor?
6. **Q6** Phase order. Recommended: 1, then 2 (the screenshot), then 3 (Vision Pro's drag-out is the
   differentiator), then 4, then 5's spike.

## Verification, honestly scoped

- **Unit:** entity queries, intents' requests, the Services handler (paths to a terminal or editor request),
  share staging.
- **Release builds:** for all three platforms on every phase, and the App Intents metadata in the app and each
  extension.
- **Simulator:** the Shortcuts app and Siri where the simulators offer them; UI tests for drag-out on iPad and
  Vision Pro.
- **The owner's devices:**
  - Services and Quick Actions in his Finder; Siri and Spotlight on the Mac and iPhone; Controls.
  - On the headset: drag-out into the room, Siri, widgets, sharing and Handoff.
  - Nothing above is claimed working until seen there.
- **Signing:** every new extension needs its App ID and profiles. The Mac widget's wildcard-profile App Group
  limit applies to each (techContext, 2026-10-12), and the release script must sign each with Developer ID (B-R2).

## Rough size (an estimate, not a commitment)

Phase 1 medium; phase 2 small to medium; phase 3 medium (share extension and drag-out); phase 4 small to medium;
phase 5 large (spike first).
