# iPhone Duo — what it means for this product, 2026-09-20

**Owner:** coordinating agent. **State:** PLAN. Nothing built.
**Authorization:** the user asked for a read of the device introduction as a use case.

Announced 2026-09-09, ships **2026-10-23**. A 7.6-inch inner display and a 5.4-inch outer one,
**the same 1:1.4 aspect ratio on both**, ProMotion, 3000 nits, IP68, 5.2mm open. Apple's own
multitasking claim for the inner display is **Split View** — *"browse your Photos library on one
side, and drag a picture into Mail on the other"* — and iOS 27 is said to make "transitioning
between displays and orientations seamless".

## Why it matters here more than to most apps

This product's differentiator is **a machine's services in one place**: a terminal, a database and
a desktop on the same host. On a Mac that is windows; in the headset it is the spatial workspace;
on a phone it has never been possible at all, which is why the session switcher (section D of the
navigation plan) exists as a plan. The Duo's inner display is the first phone where **two of them
can be on screen at once** — a terminal beside the editor, a desktop beside the database — with a
drag between them.

That does not replace the switcher. It raises its value: two sessions visible and the rest
somewhere, which is precisely the case a switcher answers.

## The three things to act on, in order of how sharply they bite

### 1. `canOpenWindows` may refuse the one phone where a second window works

`GlassWindowPresentation.canOpenWindows` is `supportsMultipleScenes && idiom != .phone` — rule 43,
written because `openWindow` is a silent no-op on an iPhone. **The Duo is an iPhone by idiom and
supports side-by-side apps**, so if it also reports `supportsMultipleScenes`, this gate is the
thing standing between the user and two Glass windows on the device that finally allows them.

The gate is still right for every other iPhone, so the fix is not to delete it: ask the system
rather than the idiom. `UIApplication.shared.supportsMultipleScenes` alone is the honest question,
and the idiom clause exists only because some iPhone builds answered it wrongly. **Verify on a Duo
before changing it** — guessing is what rule 43 was written about.

### 2. The size class changes while a session is live

Unfolding takes the app from a compact width to a regular one **mid-session**. `GlassConnectionLibrary`
has handled this since before the merge (`onChange(of: horizontalSizeClass)` rebuilds its compact
path). The compact layouts added on 2026-09-18 and 19 — the editor's and the database's — **do
not**: each keeps its own `NavigationStack` path, and nothing re-derives it when the stack is
replaced by a split view or the other way round.

Both keep what matters in a model rather than in the path (the editor's document selection, the
database's `tabState`), so unfolding should land on the right content; **folding back starts at
the root with an open document one push away and nobody pushing it** — the same class of defect as
2026-09-17, arriving by a hinge instead of a launch.

**This is testable today, with no Duo:** an iPad in Split View changes horizontal size class when
the divider moves. That is the test to write before 23 October.

### 3. Drag and drop is the headline gesture — half of it is done (2026-09-20)

**Dropping a file into the browser now works on every platform.** `SFTPIncomingDrop` moved out of
the macOS-only file it happened to live in; the AppKit fast path (`NSFilePromiseReceiver`, the
drag pasteboard) stays fenced, and the `NSItemProvider` path — which AppKit already falls back to
— is what every other platform uses. This was not a Duo feature: **an iPad could always make the
drag and this app refused it.** Five `⌘`-shortcut fences went with it, for the same reason.
Rule 52.

**Dragging a file *out* is still macOS-only** and is a bigger piece: `SFTPFilePromiseDragSource`
is an `NSViewRepresentable`, and the iOS equivalent has to download the remote file to hand over
an item provider. Worth doing before October — dragging a log out of a server and into Mail is
the Duo's own example, with a server on the other side.

## And the question it answers

**Transparency on iPhone stays as it is.** Split View is *tiled*, not overlapping: a translucent
window on the Duo shows the wallpaper, exactly as it does on every other iPhone, because nothing is
behind it. The controls stay because they are cross-platform and cost nothing; the discipline that
matters is rule 50 — no surface may need opacity to be legible — which is already in force.
