# Stage 3 W-floor — glassdb's 27.0 floor is one SwiftUI call, and it is 26.1

Owner W-floor. 2026-09-12. Read-only analysis for the [Stage 3 plan](2026-09-12_stage-3-database-plan.md).
**Status: measured by compiling, three platforms, all green at 26.0 after one guard.**
Nothing in `../glassdb` was modified; all builds ran against a scratch copy.

## Answer first

**One API is above the Power Tools floor. It is at macOS 26.1, not 27.0.** The earlier measurement
named the right call site — `visibilityPriority` in `Constants.swift` — and was right that it is the
only one. It named the wrong version: the SDK says **macOS 26.1**, so glassdb's declared 27.0 floor
is over-stated by a full major version for a reason that does not exist.

The fix already exists in this repo and is copy-ready:
`macKeepVisibleWhenCompact()` at `Sources/GlassTerminal/macOS/MacWorkspaceView.swift:865`.

## 1. What glassdb actually declares

| Setting | Value | Where |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | **27.0** | `../glassdb/glassdb.xcodeproj/project.pbxproj:421, 531, 558, 586` — all four configs |
| `IPHONEOS_DEPLOYMENT_TARGET` | 26.0 | same file `:415, 525, 556, 584` |
| `XROS_DEPLOYMENT_TARGET` | 26.0 | same file `:433, 543, 571, 599` |
| `SUPPORTED_PLATFORMS` | `iphoneos iphonesimulator macosx xros xrsimulator` | same file `:425, 535, 562, 590` |
| GlassDBKit platforms | `.visionOS(.v26), .macOS(.v26), .iOS(.v26)` | `../glassdb/Packages/GlassDBKit/Package.swift:8-12` |

The kit is already at 26.0 on every platform. Only the app project is at 27.0, and only on macOS.

## 2. Measurement — compile, not inference

Scratch copy at `<scratchpad>/glass/glassdb` (`rsync -a --exclude .git --exclude .build`), with
`<scratchpad>/glass/GlassConnectionKit` symlinked to the real sibling so the project's
`relativePath = "../GlassConnectionKit"` (`project.pbxproj:651`) still resolves.

Toolchain: **Xcode 27.0 (27A5252f), MacOSX27.0.sdk**. A 27.0 SDK with a 26.0 deployment target is
exactly how Swift availability is checked, so this measurement is sound — every use of a post-26.0
symbol is a hard error.

### 2a. Baseline at the declared 27.0 floor

```
xcodebuild -project <scratch>/glass/glassdb/glassdb.xcodeproj -scheme glassdb \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath <scratch>/dd-baseline CODE_SIGNING_ALLOWED=NO build
```

**exit 65, 1 error** — and it is **not** a floor problem:

```
ConnectionManagerView.swift:756:34: error: extra arguments at positions #5, #6 in call
note: 'init(name:subtitle:isFavorite:favoriteSymbol:color:)' declared here
```

glassdb calls `GlassLibraryConnectionRow` with a `lastConnected:` argument
(`../glassdb/glassdb/ConnectionManagerView.swift:755-769`). The current
`../GlassConnectionKit/Sources/GlassConnectionUI/GlassLibraryComponents.swift:109-111` has no such
parameter — its init is
`init(name:subtitle:isFavorite:favoriteSymbol:color:nameAccessibilityIdentifier:accessory:)`.
Real version skew between glassdb and the GlassConnectionKit working tree, recorded here because the
port will hit it, but unrelated to the deployment floor. Dropping the argument in the scratch copy
resolved it; deciding whether the kit should grow `lastConnected` or glassdb should drop it belongs
to whoever ports `ConnectionManagerView.swift`.

### 2b. macOS at 26.0 — the measurement

```
xcodebuild ... -derivedDataPath <scratch>/dd-26 CODE_SIGNING_ALLOWED=NO \
  MACOSX_DEPLOYMENT_TARGET=26.0 build
```

**exit 65. Two availability diagnostics, one call site, zero others:**

```
Constants.swift:663:9:  error: 'visibilityPriority' is only available in macOS 26.1 or newer
Constants.swift:663:29: error: 'high' is only available in macOS 26.1 or newer
```

1055 frontend invocations carried `-target arm64-apple-macos26.0`, including GlassDBKit — the
override reached every target, packages included.

### 2c. Confirming nothing hid behind the failure

A failing compile group can stop the build before later groups report. So the scratch copy was
patched twice — the `lastConnected:` argument dropped (matching the current kit) and the one call
guarded with `if #available(macOS 26.1, *)` — and rebuilt:

| Build | Command | Result |
|---|---|---|
| macOS 26.0 | `... -derivedDataPath <scratch>/dd-26b MACOSX_DEPLOYMENT_TARGET=26.0 build` | **BUILD SUCCEEDED**, exit 0, **0 errors** |
| iOS Simulator 26.0 | `-destination 'platform=iOS Simulator,name=iPhone 17 Pro' IPHONEOS_DEPLOYMENT_TARGET=26.0` | **BUILD SUCCEEDED**, exit 0, 0 errors |
| iOS device 26.0 | `-destination 'generic/platform=iOS' IPHONEOS_DEPLOYMENT_TARGET=26.0` | **BUILD SUCCEEDED**, `-target arm64-apple-ios26.0` |
| visionOS Simulator 26.0 | `-destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=26.5' XROS_DEPLOYMENT_TARGET=26.0` | **BUILD SUCCEEDED**, `-target arm64-apple-xros26.0-simulator` |

Three platforms, device and simulator, whole app plus GlassDBKit plus the dependency graph, clean at
26.0 with a single guard added. **That is the whole adaptation list.**

## 3. Cross-check by reading

Every `@available` / `#available` / `#unavailable` in `../glassdb/glassdb/` and
`../glassdb/Packages/GlassDBKit/Sources/` — six hits, all of them already guards, none of them
blockers:

| `file:line` | Guard | Verdict |
|---|---|---|
| `glassdb/Constants.swift:665` | `if #available(iOS 27.0, *)` around the same call | Already correct — iOS needs 27.0 (see §4) |
| `glassdb/AIAssistant.swift:176, 217, 282, 364, 396` | `guard #available(visionOS 27.0, macOS 27.0, *)` | Compiles at 26.0; **but see §5 — this guard is wrong on its own terms** |

GlassDBKit's six source files contain **zero** availability annotations.

The compiler cannot see into untaken `#if` branches, so the branch inventory was checked against the
platforms actually built:

| Condition | Count | Covered by |
|---|---|---|
| `#if os(macOS)` / `#if !os(macOS)` | 81 / 6 | macOS + iOS + visionOS builds |
| `#if os(iOS)` / `#if !os(iOS)` | 38 / 3 | iOS device + simulator builds |
| `#if os(visionOS)` | 6 | visionOS simulator build |
| `#if canImport(FoundationModels)` | 9 | taken on all three (SDK ships it) |
| `#if canImport(UIKit)` / `canImport(AppKit)` | 6 / 1 | iOS/visionOS and macOS respectively |
| `#if DEBUG` / `#if RELEASE` | **0** | — Debug-only builds lose nothing |

No branch went unchecked. `grep -c "#if DEBUG"` returning 0 is why a Release build was not also run.

## 4. The adaptation — all of it

| `file:line` | Symbol | What it does | Introduced | Fix |
|---|---|---|---|---|
| `../glassdb/glassdb/Constants.swift:663` | `ToolbarContent.visibilityPriority(.high)` | Marks the SQL **Run** toolbar item as high priority so it survives toolbar collapse in a narrow window | `@available(iOS 27.0, macOS 26.1, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)` — `MacOSX27.0.sdk/.../SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:13394`; `.high` itself is `@available(iOS 27.0, macOS 26.1, *)`, `visionOS unavailable`, ibid. `:13372-13375` | Wrap in `if #available(macOS 26.1, *) { … } else { self }` |

That is the entire list. The surrounding code, so the fallback can be judged
(`../glassdb/glassdb/Constants.swift:659-673`):

```swift
extension ToolbarContent {
    @ToolbarContentBuilder
    func databaseHighVisibilityPriority() -> some ToolbarContent {
        #if os(macOS)
        visibilityPriority(.high)          // ← line 663, the only blocker
        #elseif os(iOS)
        if #available(iOS 27.0, *) {
            visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
```

The iOS branch is already guarded correctly, and visionOS already falls to `#else self` — which is
also right, since `.high` is marked `visionOS, unavailable` outright. **Only the macOS branch is
bare, and only because glassdb's own floor is 27.0.**

**What the fallback costs.** Two call sites —
`../glassdb/glassdb/QueryEditorView.swift:559` and `../glassdb/glassdb/TableDetailView.swift:142` —
both attach it to the `SQLRunControl` toolbar item. On macOS 26.0 exactly, that item reverts to
`.automatic` priority: when the window is narrow enough for AppKit to collapse the toolbar, Run can
be pushed into the `»` overflow menu instead of being pinned visible, so running a query becomes one
click deeper at narrow widths. Nothing is unreachable, no data or state is affected, and at 26.1 and
above the behaviour is identical to today. This is the mildest possible degradation.

**Reuse, not a new helper.** This repo already solved this, twice, in the terminal capability:

```swift
// Sources/GlassTerminal/macOS/MacWorkspaceView.swift:865-872
@ToolbarContentBuilder
func macKeepVisibleWhenCompact() -> some ToolbarContent {
    if #available(macOS 26.1, *) { visibilityPriority(.high) } else { self }
}
```

with `macOverflowFirstWhenCompact()` (`.low`) beside it at `:856-863`. Both live inside
`#if os(macOS)` and so are macOS-only; the database helper must also serve iOS. The right move when
the database capability lands is to **extract the pair into a shared module** (GlassShell or
GlassLayers) with the iOS and visionOS branches folded in, and have both capabilities call it —
rather than letting a third copy of the same `#available` appear. Recording it here for whoever
ports `Constants.swift`; W-floor changed nothing.

## 5. Separate finding — the AI assistant gates itself at 27.0 for no SDK reason

`../glassdb/glassdb/AIAssistant.swift:176` and four siblings read:

```swift
guard #available(visionOS 27.0, macOS 27.0, *) else {
    availability = .unsupportedOS
    return
}
let modelAvailability = SystemLanguageModel.default.availability
```

But the SDK declares `SystemLanguageModel` as
`@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`
(`MacOSX27.0.sdk/.../FoundationModels.swiftmodule/*.swiftinterface`). The guard is a full major
version stricter than the framework requires — most likely a habit formed under glassdb's own 27.0
floor, since it costs nothing there.

It compiles fine at 26.0 (the builds in §2c prove that), so it is **not** a port blocker. But shipped
as-is under a 26.0 floor it would report `.unsupportedOS` and leave the on-device SQL assistant dark
on every macOS 26.0-26.x and visionOS 26.x machine, while working on iOS 26.0 — because the `*` in
that guard resolves to the iOS deployment target. That asymmetry is almost certainly unintended.
Note the `#if canImport(FoundationModels)` + `@_weakLinked import` wrapper is already correct and
should stay.

Recommendation for whoever ports `AIAssistant.swift`: relax the guard to
`#available(macOS 26.0, visionOS 26.0, *)` — which at a 26.0 floor makes it redundant and removable —
and let `SystemLanguageModel.default.availability` do the real gating, which is what it is for. It
already handles `.deviceNotEligible` / `.appleIntelligenceNotEnabled` / `.modelNotReady` at
`:181-196`. **Not actioned; flagged for the owner of that file.**

## 6. Floor recommendation

**Keep the product floor at macOS 26.0 and guard the one call.** Reasons, in order:

1. **The cost is one `if #available` around one line**, and the fallback loses a toolbar pinning
   nicety at narrow widths — nothing functional. Raising a whole product's floor to buy that back is
   not a trade worth making.
2. **The pattern is already in the codebase** at `MacWorkspaceView.swift:865`. Power Tools has
   already decided how it handles 26.1-only toolbar APIs; the database capability should match, not
   diverge.
3. **26.0 is the floor `Package.swift:9-11` and every shipped module already targets.** Raising it
   to 26.1 would be a product-wide decision taken to accommodate a single cosmetic call in one
   capability — the tail wagging the dog.
4. **glassdb's 27.0 was never justified.** The measurement above shows nothing in 22,244 lines
   requires it. Carrying that number into the merged product would import a constraint that was
   already wrong where it came from.

The floor is the user's call, and nothing here was changed.

## Verification summary

| Check | Result |
|---|---|
| `project.pbxproj` deployment targets, all 4 configs | **read** — macOS 27.0, iOS 26.0, xrOS 26.0 |
| GlassDBKit `Package.swift` platforms | **read** — 26.0 on all three |
| macOS build at declared 27.0 floor | **failed**, 1 error — GlassConnectionKit API skew, not a floor issue |
| macOS build at `MACOSX_DEPLOYMENT_TARGET=26.0` | **failed**, 2 diagnostics, **1 call site**, `Constants.swift:663` |
| macOS 26.0 after the guard + skew fix | **BUILD SUCCEEDED**, 0 errors |
| iOS Simulator 26.0 / iOS device 26.0 | **BUILD SUCCEEDED** both, 0 errors |
| visionOS Simulator 26.0 | **BUILD SUCCEEDED**, 0 errors |
| `grep` for `@available` / `#available` / `#unavailable`, app + kit | **6 hits**, all pre-existing guards, none blocking |
| `#if` branch inventory vs platforms built | **all covered**; zero `#if DEBUG` |
| SDK availability of `visibilityPriority`, `.high`, `SystemLanguageModel` | **read from the swiftinterface**, cited above |

## Limits of this measurement

- Compile-time only. It proves the code **builds** at 26.0; it does not prove runtime behaviour on a
  real macOS 26.0 machine, which nobody here has.
- Measured against **Xcode 27.0 beta 27A5252f / MacOSX27.0.sdk**. A later SDK could move an
  availability annotation; this is the answer for the SDK on this machine today.
- glassdb's own **test targets were not built** (`glassdbTests/glassdbTests.swift`, 4567 lines;
  `Packages/GlassDBKit/Tests/`, 862 lines). Both contain zero `@available` / `#available` hits, so
  no blocker is expected, but this is a grep result rather than a compile result.
- Debug configuration only — justified in §3 by there being no `#if DEBUG` anywhere in the sources.
- The scratch copy resolved `GlassEditorKit` and `GlasSecretStore` from their pinned **remote**
  revisions (`project.pbxproj:643-659`), and `GlassConnectionKit` from the local sibling working
  tree. The §2a skew is a consequence of that last one and is the honest current state.
