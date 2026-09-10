# Stage 1 — GlassLayers module

Owner: layers worker (fork of `/root`). Written 2026-09-10. **Status: implemented and unit-tested;
running-window verification pending the app target.**

## Task

- **Objective:** the one layering system every surface draws from — state, persistence, legacy
  migration, environment injection, window/panel bridge views, and Appearance controls.
- **Authorization:** Stage 1 build, approved 2026-09-10; decision D2 (transparent-first, frost on,
  migrate each legacy key set).
- **Owned files:** `Sources/GlassLayers/`, `Tests/GlassLayersTests/`, this note. `Package.swift`
  untouched (GlassLayers → GlassConnectionUI dependency was already declared).

## What was bridged from GlassConnectionUI versus written new

| Bridged, unchanged | Used by |
|---|---|
| `GlassCanvasBackdrop(material:blurAmount:)` | `GlassLayerBackground` — the frost layer everywhere |
| `GlassNativeWindowFrame` (visionOS only) | `GlassLayeredWindow` on visionOS, title/controls ornaments passed through |
| `GlassWindowChrome.installTitlebarMaterial(in:materialStyle:)`, `GlassTitlebarMaterialView` | `GlassWindowLayerPolicy` on macOS |
| `GlassSettingSlider` | `GlassLayerControls` |

| Written new | Why it did not exist |
|---|---|
| `GlassLayerState`, `GlassLayerMaterial` | Each app had its own model with its own defaults (see the drift table in [technical context](../../techContext.md)); no shared state type existed |
| `GlassLayerLegacy` | Read-side migration of the three key sets, mirroring each app's own resolution (`resolvedBlurBackground` Boolean handling, `windowOpacity` over `backgroundFill`, `glassFrost` over `glassMaterialStyle`) |
| `GlassLayerStore` | One persisted state under `glass.layers.state`, migration once, `migrationSource` provenance |
| `EnvironmentValues.glassLayers`, `View.glassLayers(_:)` | Injection |
| `GlassWindowLayerPolicy`, `GlassWindowLayerReader` (macOS) | The three apps each repeat the same NSWindow sequence (`isOpaque = false`, `backgroundColor = .clear`, `titlebarAppearsTransparent = true`, install material) in `MacTerminalWindowPolicy.swift:248-256`, `glassdb/Constants.swift:633-652`, `DesktopMetalSurface.swift:244-249`; this is the fourth copy's replacement, plus title-bar alpha following `frost` |
| `GlassLayeredWindow`, `GlassLayeredPanel`, `GlassLayerBackground`, `GlassLayerResolution` | Composition of theme paint + frost + platform framing; Reduce Transparency forcing opaque as glassDT does (`DesktopSessionView.swift:92`) |
| `GlassLayerControls` | Appearance section with identifiers `layers-paints-theme`, `layers-opacity`, `layers-frost`, `layers-material`, `layers-reset` |

## Legacy keys found (verified 2026-09-10)

| App | Keys | Defaults | Suite the app writes | Evidence |
|---|---|---|---|---|
| glas.sh | `windowOpacity`, alias `backgroundFill`; `blurBackground` (Bool or Double); `glassFrost`, older `glassMaterialStyle` | 0.0 / 1.0 / `ultraThin` | `.standard` of `sh.glas.app` (`settingsDefaults ?? .standard`, `SettingsManager.swift:205`) | `Constants.swift:25-31,53`; `SettingsManager.swift:167-171,279-294,427-436`; picker values `SettingsView.swift:736-741` |
| glassdb | `glassdb.windowOpacity`, `glassdb.blurBackground` (Bool or Double) | 0.95 / 1.0 | `.standard` of `app.glassdb` (`defaults: UserDefaults = .standard`, `SettingsManager.swift:142`) | `Constants.swift:27-28`; `SettingsManager.swift:112-113,183-196` |
| glassDT | `display.glass.opacity`; frost under `display.glass.material` | 1.0 / 0.25 | `.standard` of `app.glassdt` (`@AppStorage`) | `DesktopSettingsView.swift:5-8,43-44`; `DesktopSessionView.swift:52` |

**Consequence, stated plainly:** all three apps keep their layer keys in their own `.standard`
domains, not the App Group. On iOS and visionOS another bundle cannot read those, and under
macOS App Sandbox the same is true. So the migration is **guaranteed only for keys present in the
App Group suite or this app's own standard domain**, and **best-effort on macOS** via
`UserDefaults(suiteName: "sh.glas.app")` etc., which returns empty under sandbox. The design is
correct for the suites it can see and does no harm otherwise; it should not be presented as
"your setting carries over" on every platform. Priority order glas.sh → glassdb → glassDT,
first source with any key wins whole, no blending.

## Semantics

Two dimensions as in glas.sh's `TerminalGlassAppearance`: `opacity` paints the theme colour,
`frost` composites the material. `paintsTheme` is stored explicitly (migrated as `opacity > 0`);
`effectiveOpacity = paintsTheme ? opacity : 0`. Turning the theme on with a zero slider starts it
at 0.95 (glassdb's figure) so the toggle is visible. Default per D2:
`opacity 0, frost 1, ultraThin, paintsTheme false`. Reduce Transparency resolves every surface to
`opacity 1, frost 1`.

On macOS the title bar material's `alphaValue` follows `frost` and it is hidden at 0, so the title
bar is exactly as transparent as the window body. The window's `styleMask` is left alone, as
glas.sh's policy does (glassdb additionally inserts `.fullSizeContentView`; the shell can decide).

## Validation

| Check | Result |
|---|---|
| `swift test --filter GlassLayersTests` | **21 passed, 0 failed**, 2 suites (state: 7; migration: 14) |
| `swift build` (macOS host, whole package) | passed |
| `xcodebuild -scheme GlassLayers -destination 'generic/platform=visionOS Simulator'` | **BUILD SUCCEEDED**, no warnings in `Sources/GlassLayers` |
| `xcodebuild -scheme GlassLayers -destination 'generic/platform=iOS Simulator'` | **BUILD SUCCEEDED**, no warnings in `Sources/GlassLayers` |
| Title bar transparency in a running macOS window | **Not run** — needs the app target. Integration pass must: open the library window, set frost to 0 and theme off in Appearance, confirm the desktop shows through the title bar band as well as the body; set frost to 1, confirm the sidebar-style material appears behind the title bar and its edge follows the sidebar divider; confirm toolbar controls remain opaque and hit-testable throughout |
| visionOS ornaments and backdrop in a running window | **Not run** — same integration pass, on the Vision Pro |
| Reduce Transparency | Logic unit-tested; visual confirmation with the accessibility setting on is part of the same pass |

## Open items

- The shell should inject `GlassLayerStore()` once at the composition root with `.glassLayers(_:)`;
  the environment default constructs one on `.standard` if it does not.
- Whether the merged app's macOS target is sandboxed decides whether the best-effort legacy
  domains are readable. Record the outcome of the first macOS run.
- `GlassLayeredWindow` on macOS/iOS has no title/controls chrome; the ornaments are a visionOS
  construct. If the shell wants a Mac-side equivalent, that is a shell decision, not a layers one.
