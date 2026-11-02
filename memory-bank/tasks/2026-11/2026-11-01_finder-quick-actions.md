# Finder Quick Actions: Tab Here beside Window Here (2026-11-01)

- **Owner and authorization:** the owner, with a screenshot of the Finder's Quick Actions showing none of ours: "We
  need this on a right click on a folder in Finder. I thought we had this wired up?!", then, seeing them under
  Services, "add the tab one too, then deploy and push".
- **What was wrong:** the Window Here Quick Action (D72, `QuickActions/`) was installed but off. macOS leaves a new
  action extension off until it is turned on in Quick Actions ▸ Customize… (or `pluginkit -e use -i <id>`); the
  three Services in the Mac's `Info.plist` (`NSServices`) are on by default, which is why the Services submenu had
  them. A stale Debug copy of the app in Xcode's derived data was also registered; it was unregistered
  (`pluginkit -r`, `lsregister -u`), its files left alone.
- **Reuse:** the request already existed (`GlassWidgetRequest.newLocalTerminalTab`, used by the Services and the
  Finder toolbar), and so did its handling (`GlassTerminalRuntime.openLocalTerminalTab`: the window in front, or a
  window when none). The Finder lists one action per extension, so the tab is a second target,
  `GlassPowerToolsQuickTab` (`$(GPT_BUNDLE_ID).quicktab`), built from the same `QuickActions/` folder, `Info.plist`
  and entitlements. The plist names its class through `GPT_QUICK_ACTION_CLASS`; `GlassQuickTabAction` overrides one
  class property of `GlassQuickAction`.
- **Changed:** `GlassPowerTools.xcodeproj/project.pbxproj` (the target, embedded and depended on by the app),
  `QuickActions/Info.plist`, `QuickActions/GlassQuickAction.swift`; the help (`site/help/library-siri-and-system.md`:
  both Quick Actions and how to turn one on), README and the home page ("Quick Actions"), release notes 0.4.575.
- **Validation:** 0.4.575 built for the Mac (Release, development signed; `codesign --verify --deep --strict`
  passes), installed and read back 0.4.575 (575), no new crash reports. Both extensions registered from
  `/Applications` and on (`pluginkit -m` shows `+`); display names, bundle ids and principal classes read from the
  built plists; each binary holds `_TtC…GlassQuickTabAction` / `GlassQuickAction` as named. Not run from the Finder
  by an agent: that is the owner's screen. No unit test covers an extension's principal class (no test target
  builds the extensions); the request and its handling are covered (`GlassOpenedURLTests`).
- **Not done:** a Mac release (Sparkle) with 0.4.575 — the published download is 0.4.569, whose Window Here Quick
  Action is the one he turned on; iPhone and Vision Pro unchanged at 0.4.574.
