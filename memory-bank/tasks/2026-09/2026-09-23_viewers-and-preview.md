# Viewers and Preview in the editor — plan, 2026-09-23

**State BUILD → QA (2026-09-23).** Approved by the user: *"This plan is approved!"*, with Mermaid on the condition that updating it is part of the build. Stages 1–4 built; see *Built* at the end. The user asked: *"How difficult would it be to show images and
media in the Editor view? So when I click a png I get the image, not the binary?"*, then *"The
things that are text and visual (markdown) should have a preview button like VSCode and its
offspring"*, then *"Go ahead with these now, too: CSV as a table, and Mermaid diagrams. Please
create a plan to address the image and preview tasks."* Authorization: this plan. Building starts
on the user's word.

## Task contract

- **Objective.** A file that is only visual opens in a viewer, not as decoded bytes. A file that is
  text with a visual form keeps its text editor and gains a **Preview** button.
- **Scope.** Images, PDF, video, audio, other binaries (viewers). Markdown with Mermaid, HTML, SVG,
  CSV (Preview). Local files and files on another machine, through the same path. Mac, iPhone/iPad,
  Vision Pro.
- **Owner.** Coordinator. Files: `Sources/GlassEditorCore/Document/`, `Sources/GlassEditor/`,
  `Package.swift`, `THIRD-PARTY-NOTICES.md`, tests under `Tests/GlassEditor*`.
- **Out of scope.** Editing media. Rendering Office documents, fonts or archives (they land on the
  "not text" screen). A live-server preview of HTML with its own scripts.

## What exists (reuse check)

| Need | Existing | Use |
|---|---|---|
| One read for local and remote bytes | `GlassEditorFileAccess.read(_:)`, local and `GlassEditorRemoteFileAccess` (`GlassEditorFileAccess.swift:72`, `:145`) | Classify right after this read |
| Where bytes become text | `GlassEditorDocument.open(path:through:machine:)` (`GlassEditorDocument.swift:68`) → `EncodingDetector.decode`, whose **Latin-1 fallback is total** — which is why a PNG becomes garbage rather than an error | The branch point |
| Tabs, preview tab, close, dirty, Active row | `GlassEditorWorkspace.documents`, `open(path:through:machine:asPreview:)` (`GlassEditorWorkspace.swift:204`), `GlassWorkspaceTabBar` | Unchanged, if a viewer is a kind of document |
| The detail surface | `GlassEditorWorkspaceView.detail` → `GlassEditorView(model:)` (`GlassEditorWorkspaceView.swift:500`) | A switch beside it |
| Editor toolbar | `toolbarContent(includingDismissal:)` (`GlassEditorWorkspaceView.swift:665-700`) | The Preview button |
| Languages | `LanguageID.markdown`, `.html`, `.xml` (`LanguageID.swift`) | Which documents offer Preview; SVG and CSV are recognised by extension |
| Web rendering | SwiftUI `WebView`/`WebPage` in the terminal's debug-only `HTMLPreviewWindow.swift` | Proves the API on all three platforms; not reusable itself (it loads a live URL, DEBUG only) |
| A Markdown parser | **none** | New dependency, see D35 |

A text document's model is read in 25 places, all in `GlassEditorWorkspace.swift` and
`GlassEditorWorkspaceView.swift`, so changing its shape is contained.

## Decision needed first — D35 (Proposed)

1. **swift-markdown** (Apple, Apache-2.0, cmark-gfm underneath: tables, task lists,
   strikethrough, autolinks), pinned `exact:` like SwiftTerm, noticed in
   `THIRD-PARTY-NOTICES.md` under resolved dependencies. Foundation's `AttributedString(markdown:)`
   was rejected: no tables, no block styling.
2. **Mermaid is vendored**, not fetched: `mermaid.min.js` (MIT) copied into `GlassEditor`'s
   resources at a pinned version, noticed under "Vendored in this repository".
3. **The preview's safety rule**, which Mermaid forces into the open: a preview page runs **no
   script except the bundled Mermaid**, loads **nothing from the network**, and gets every
   resource through one custom URL scheme the app answers itself. A relative image in a Markdown
   file on the Linux server is fetched through that file's own `GlassEditorFileAccess` — the same SFTP
   connection — never by the web view. HTML files are previewed with scripts off entirely.

The user approved swift-markdown in spirit ("go ahead"); the Mermaid script exception is new and
is recorded as Proposed until built.

## Stages

### 1. Know what the file is — `GlassEditorCore`
- `GlassEditorFileKind`: `.text`, `.image`, `.pdf`, `.video`, `.audio`, `.binary`.
- Decided by extension through `UTType`, then confirmed or overridden by the first bytes (PNG,
  JPEG, GIF, WebP, HEIC/`ftyp`, PDF `%PDF`, MP4/MOV `ftyp`, MP3/ID3, WAV `RIFF`, a NUL in the
  first 8 KB for other binaries). Content wins over a misleading name: a PNG saved as `.txt` is
  an image; a `.svg` stays text.
- Pure and unit-tested with byte fixtures, no files.

### 2. A document that is not text — `GlassEditor`
- `GlassEditorDocument` gains `content: .text(GlassEditorModel) | .viewer(GlassEditorViewer)`;
  `model` becomes the text case's accessor and the 25 call sites take the optional. A viewer is
  never dirty, has no find, no save, no encoding.
- `GlassEditorViewer` holds the kind, the bytes' size, and a **local file URL** — the file itself
  when local, a temporary copy when remote (players need a URL). Temporary copies live in the
  caches directory under the document's id and are removed on close.
- `open(path:through:machine:)` reads, classifies, and builds one or the other. Duplicate-open,
  preview tabs, recents and Active behave exactly as for text.
- **Size guard for remote media**: reads are whole-file into memory today. Above a limit (proposed
  64 MB) a remote media file asks before downloading, showing the size. Local files have no limit
  (they are memory-mapped by the players).

### 3. Draw the viewers
- **Mac: Quick Look's `QLPreviewView`** for image, PDF, video and audio in one control — it also
  handles zoom, paging, playback and scrubbing, and costs little.
- **iPhone, iPad, Vision Pro**: dedicated SwiftUI viewers — images with fit/actual size and pinch
  zoom, `PDFKit` in a representable, `AVKit`'s `VideoPlayer` for video and audio. Quick Look there
  is a full-screen presenter, which does not fit in a tab.
- **Other binaries**: "This file isn't text", its size and kind, and **Open as Text** (the old
  behaviour, on request).
- Tab symbols by kind (`photo`, `doc.richtext`, `film`, `waveform`).

### 4. Preview for text that has a picture
- Offered for Markdown, HTML, SVG and CSV (by language or extension).
- A **Preview** toolbar button, VS Code's shape: first press opens the preview **beside** the
  text (a split in the detail), a second press shows the preview **alone**, a third returns to
  the text. A phone has no room beside, so the button toggles text ↔ preview.
- **Live**: re-rendered from the editor's text, not the saved file, debounced ~300 ms. Scroll
  follows roughly by heading for Markdown.
- Renderers:
  - **Markdown** → swift-markdown → HTML with one stylesheet that follows light/dark and the
    Glass text size; code blocks highlighted with the editor's own theme colours where cheap,
    plain otherwise. ` ```mermaid ` fences become `<div class="mermaid">` rendered by the
    bundled script.
  - **HTML** → the document as written, scripts off, network off.
  - **SVG** → shown as an image in the same page, so a malformed SVG shows the parser's error
    rather than nothing.
  - **CSV/TSV** → a native SwiftUI `Table` (sortable columns, first row as header when it looks
    like one), not HTML: it is faster, selectable, and platform-native. A parser that handles
    quoted fields, embedded newlines and escaped quotes (RFC 4180); rows capped for display
    (proposed 10,000) with a note saying so.
- Relative resources (images in Markdown, `<img src>` in HTML) resolved against the file's
  directory through the document's own `GlassEditorFileAccess`, via the custom scheme.

### 5. Tests and proof
- Unit: file kind from bytes and names; the viewer/text branch at open for local and a fake remote
  access; temporary copies removed on close; the remote size guard; Markdown → HTML for tables,
  task lists, a Mermaid fence; CSV parsing edge cases; the preview's resource resolver refuses
  anything outside the file's machine and paths that escape with `..`.
- Proof on screen, not only tests: a PNG, a PDF, an MP4 and a Markdown file with a table and a
  Mermaid diagram, opened locally and from the Linux server, photographed on the Mac, and on the iPhone
  simulator (rule: drive the phone). Vision Pro build only, until the headset is updated.

## Order and size

| Stage | Size |
|---|---|
| 1 File kind | ~2 h |
| 2 Viewer document, remote copies, size guard | ~4 h |
| 3 Viewers (Mac Quick Look, touch viewers, not-text screen) | ~4 h |
| 4 Preview: button and split, Markdown + Mermaid, HTML, SVG, CSV table, resource scheme | ~1.5 days |
| 5 Tests and on-screen proof | through each stage, plus ~2 h |

Built in that order; each stage installs on the Mac and the phone when it stands on its own
(stages 1–3 are the "click a PNG, see the image" answer).

## Risks

- **Mermaid's size** (~3 MB of script) and its own security record: pinned version, loaded only
  into preview pages, never with network access.
- **`WebView`/`WebPage` on visionOS 26** is newer than on the Mac; prove it in the simulator
  before relying on it there.
- **Rule 53-style seams**: a viewer document must go through the same `open` so it gets preview
  tabs and duplicate detection; a second open path would drift.
- **Remote writes**: none — viewers never save, so the conflict machinery is untouched.

## Next action

The user's go on this plan, and on D35's Mermaid script exception. Then stage 1.

## Built — 2026-09-23

**Mermaid is part of the build** (the user's condition: *"make updating it a part of the build
process. Check the version number and if it moves, download and build the new version in. We never
want stale."*). `Tools/Mermaid/update-mermaid.sh` asks the npm registry for `mermaid@latest`; if the
version moved it downloads the tarball, **verifies its sha512 against the registry's integrity
field**, and replaces `Sources/GlassEditor/Resources/Mermaid/{mermaid.min.js,LICENSE,VERSION}`;
unchanged, it writes nothing; offline or failed, the build continues on the copy it has and says so.
It runs as the **GlassPowerTools scheme's build pre-action** — not a build phase: the package
compiles before any app-target phase, and script sandboxing is on, so a phase would be too late and
could not reach the network. Proven: a faked stale `VERSION` was corrected by an `xcodebuild`, and
every build prints `update-mermaid: 12.0.0 is current`. A pinned swift-markdown `exact: 0.9.0`.

| Stage | Files | Proof |
|---|---|---|
| 1 File kind | `GlassEditorCore/Document/FileKind.swift` | `FileKindTests` (3) |
| 2 Viewer document | `GlassEditorViewer.swift`; `GlassEditorDocument.open` classifies before decoding, `viewer` beside an empty never-dirty model (not an optional model — the plan's version, changed because it kept all 25 call sites untouched); save/reload refuse a viewer; `GlassEditorWorkspace.pendingLargeOpen`, `confirmLargeOpen`, `openAsText` | `GlassEditorViewerTests` (5), bite-checked by forcing text: 4 of 5 failed |
| 3 Viewers | `GlassEditorViewerView.swift`: Quick Look (`QLPreviewView`) on the Mac; zoomable image, PDFKit, `VideoPlayer` elsewhere; the not-text screen with Open as Text; tab symbols | Mac, 0.4.210: PNG, PDF, binary photographed |
| 4 Preview | `GlassEditorPreview.swift` (pure: kinds, modes, page + CSP, resource rule, RFC 4180 CSV), `GlassEditorPreviewView.swift` (WebPage with a `glass-preview:` scheme handler, navigation that refuses everything but its own page and sends web links to the browser, native CSV table), `Resources/Preview/glass-mermaid.js`; toolbar button and split in `GlassEditorWorkspaceView` | `GlassEditorPreviewTests` (7). Mac, 0.4.212: Markdown table, task list, Mermaid (dark), relative image, **an embedded `<script>` did not run**, live update from unsaved text; CSV with quoted comma header and doubled quotes; SVG. iPhone simulator: `testAPictureOpensAsItselfAndMarkdownPreviews` passed, screenshots show the PNG and the Markdown preview |

The UI-test seed (`--ui-testing-seed-project`) now also writes a drawn `logo.png` and a `PREVIEW.md`.

**Not yet proven:** a remote file on the Linux server (viewer copy, relative images over SFTP) — needs the
user's server; the Vision Pro simulator run (in progress at this checkpoint); video and audio on
screen (Quick Look/AVKit, not photographed).

## Found on the devices, fixed the same day

1. **Open File on iPhone opened nothing** (user, 08:07: a PNG and an SVG both landed on "No
   Document"). A file from the system picker or a drop is security-scoped on iOS, and the editor's
   `fileImporter` and `dropDestination` never asked for access — only the project chooser did
   (`GlassEditorProjectsPanel.swift:302`). Not the viewer: an SVG is text and failed identically.
   The Mac passed because its open panel grants access implicitly. Fixed in
   `GlassEditorWorkspace.open(_ url:)`: access is asked for and **held while the document is
   open** (saving writes back to the same file), returned in `close`, which is the only way a
   document leaves (the preview slot goes through it too). 0.4.213. Not yet seen on the phone.
2. **The Mac froze on a remote SVG** (user: the Linux server,
   `…/client-project/artifacts/logo/logo-horizontal.svg`; they force-quit it). Not
   Preview and not the viewer: the text engine. Reproduced with a 1.88 MB one-line SVG (path data
   and an embedded base64 PNG): under `highlightingCodeUnitCeiling` (2,000,000), so fully
   coloured, and TextKit walks a line's colour runs per character each time it draws it — the
   sample was 2,817 deep in `NSTextLineFragment` rendering-attribute enumeration, triggered when
   Preview halved the editor's width. Fixed with VS Code's rule and number:
   `GlassEditorModel.setHighlights` drops runs on any line over 20,000 characters
   (`longLineHighlightLimit`), checked only when the document is longer than that.
   `LongLineHighlightTests`. Same file on 0.4.214: responsive, preview drawn. The user's own
   file was never read from here (this shell has no key for the Linux server).

## Open

- **visionOS: the editor's toolbar is invisible to UI tests** — Save, settings, Preview are not in
  the accessibility tree in the headset simulator, so Preview's half of
  `testAPictureOpensAsItselfAndMarkdownPreviews` skips there with that reason. The image viewer
  half passed on visionOS. Whether the toolbar is drawn in the headset is for the device.
- Scroll-follow by heading and highlighted code blocks in the Markdown preview (the plan allowed
  plain); a remote file on the Linux server through a viewer; video and audio on screen.

## The user's own logo on the iPhone simulator (08:31)

`logo-horizontal.svg`: **14,588,762 bytes on one line**, one `<path>`, one embedded PNG
(1368 × 1824) — over the 2,000,000-unit highlighting ceiling, so already uncoloured; the long-line
rule never applies to it. `testTheUsersOneLineLogoOpens` (reads `TEST_RUNNER_GPT_SEED_FILE`, which
did reach the simulator runner this time; the seed copies a named host file into DemoProject):
**no crash**, still responsive after Preview, but **46 s to open** and the text view draws
**nothing** for the line; **Preview draws the logo correctly**. The Mac on 0.4.214 with this file
was not observed — the user was using the Mac, so UI driving stopped.

Proposed, not built: a document whose longest line is past what TextKit can lay out (order of
1,000,000 characters) should not go into the text engine at all — an SVG opens straight in
Preview, anything else on the not-text screen saying why, with Open as Text still offered.

## Where the user's logo's time went, measured (09:00)

*"How does BBEdit open a file like that so quickly without complaining? … macOS should be able to
do that nearly instantly. … previews only on iOS, that's fine."* Measured headless on the Mac
(`LargeFileOpenTimingTests`, `LargeFileLayoutTimingTests`, both skip unless `GPT_LARGE_FILE`):

| Stage | Before | After |
|---|---|---|
| read + decode + line endings + model | 0.4 s | 0.4 s |
| **start highlighting** — a full tree-sitter parse of a document over the ceiling, then thrown away | **13.0 s** | 0.09 s |
| layout, wrapping off (the editor's default) | **26.1 s** | — (wrapped now) |
| layout, wrapping on | 1.0 s | 1.0 s |
| resize and redraw, wrapped | 1.3 s | 1.3 s |

About 40 s of blocked main thread is the freeze the user killed. BBEdit has its own text engine and
lays out only what is visible; TextKit 2's unit is the paragraph, and a 14.6 M-character line is one.

Fixed: `DocumentParser.parseFull`/`apply` check the ceiling **before** copying or parsing
(`HighlightingCeilingTests`, bite-checked against the old parser); a file with a line over
`GlassEditorDocument.veryLongLine` (100,000) opens **wrapped**, as the file's own override
(`GlassEditorVeryLongLineTests`); on a **phone** such a file opens in Preview when it has one.
Also: `BuiltInHighlightingTests.settle` waited on a count of yields against a 75 ms debounce and
failed on a quiet machine — now waits on time. Open ≈ 0.4 s, then ≈ 1 s to lay out; not instant,
and anything faster needs a text engine of our own (BBEdit's route) — not proposed.

## Scrolling (09:40) — *"Can we check and see why scrolling isn't smooth?"* (Mac editor)

Measured offscreen, release build, 120 frames of 40 pt (`ScrollTimingTests`, gated by
`GPT_SCROLL_TIMING`; `GPT_SCROLL_CASE`, `GPT_SCROLL_STEPS`, `GPT_LARGE_FILE`):

| File | Before | After |
|---|---|---|
| 10,000-line Swift, **unwrapped (the default)** | median 1.2 ms, **29 frames at ~370 ms** — every frame of the first ~1,100 pt | median 0.6 ms, 0 over 16.7 ms |
| same, wrapped | 0.6 ms, none over | unchanged |
| user's 14.6 MB one-line SVG, wrapped | 30 ms every frame | unchanged — see below |

**Every ordinary file stuttered unwrapped.** Sampled: `_NSTextViewportElementView layout` →
`-[NSTextView textContainerOrigin]` → `ensureLayoutForRange` from the top of the document, because
the container was infinitely wide inside a view the width of the window. Letting the view resize
horizontally did not help (measured); a **wide, finite container (100,000 pt) in a view exactly as
wide** did. `GlassEditorAppKitEngine.applyWrapping(_:to:in:)`, `unwrappedContainerWidth`, used at
creation and on toggling wrap. Lines over ~14,000 characters would fold at that width; such files
already open wrapped (`veryLongLine`).

**The one-paragraph file stays at ~31 ms a frame**: sampled in `-[NSTextView _updateContentHeight]`
→ `estimatedSizeForLastTextContainer`, which walks every line fragment of the paragraph each frame
— TextKit 2 internals, no API to avoid it short of an engine of our own. Not fixed; options for
the user: open such files in Preview on the Mac too, or accept ~33 fps in text.

