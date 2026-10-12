# 2026-10-12 — Widgets: Machines and Active (D68)

**Owner:** "update the widget suite to make all of them useful for today's platform"; chose
Machines and Active (not Workgroups or Controls), on iPhone & iPad, Vision Pro and the Mac.

## Before

One widget, "Recent Servers" (`ServerHealthWidget`, kind `ServerHealthWidget`), read
`UserDefaults(group).servers`, which nothing writes since D26 attached the catalog store: it showed
"No Servers" or a frozen list. No tap target (the `glassh://` link went with D4); not built for
macOS; glas.sh branding; privacy manifest declared a UserDefaults reason. Inventory by an Explore
agent; findings checked in the code.

## Now (cd6a2f1)

- `Sources/GlassWidgetData` (new product): `GlassWidgetSnapshot` (machines: id, name, favourite,
  last connected, services by kind; active: per machine open/running counts and kinds; schema 1;
  metadata only), `GlassWidgetStore` (App Group `Widgets/snapshot.json`, written only on change),
  App Intents `GlassConnectServiceIntent`, `GlassShowMachineIntent`, `GlassShowActiveIntent`
  (`openAppWhenRun`), `GlassWidgetRequests` (queues until the app sets its handler),
  `GlassWidgetIntents: AppIntentsPackage`.
- `GlassShellModel.widgetSnapshot()` (GlassShell): library + Active; local host and empty machines
  left out.
- `App/GlassWidgetBridge.swift`: started at launch (not in UI tests); rebuilds on observation change
  or every 60 s, writes + `reloadAllTimelines` only on change; carries out taps (connect, hostToShow,
  showActiveConnections; Connections brought forward/opened on Mac and visionOS).
- `Widgets/`: `MachinesWidget` (system S/M/L; iOS accessoryRectangular/Inline), `ActiveWidget`
  (system S/M; iOS accessoryCircular/Rectangular/Inline); visionOS glass texture and mounting styles.
  Old files removed; entitlements renamed; macOS entitlements (sandbox + App Group).
- Project: widget target builds for macosx too (deployment 26.0, hardened runtime, runpaths); the Mac
  app embeds it; GlassWidgetData linked to the app and the extension.

## Validation

- Builds: macOS, iOS, visionOS (visionOS needed the accessory families guarded).
- Mac build: `.appex` in `Contents/PlugIns`, sandboxed, `group.sh.glas.shared`; the three intents in
  both Metadata.appintents.
- Tests: GlassWidgetDataTests (6), the shell's snapshot test; every module passes.
- Installed 0.4.382 on Mac, iPhone, Vision Pro. On the Mac the snapshot was written within seconds
  (7 machines, 2 favourites, keys only id/name/favourite/lastConnected/services; later 22 running);
  `pluginkit` lists `com.glasspowertools.widgets`.
- **Not yet seen:** the widgets placed and drawn on any device; a tap carried out by the app.

## Remaining

- Owner to place them and try a tap on each device.
- The release script's Developer ID export now has a Mac widget to sign (it said so before it was
  true); check on the next Mac release.
- Workgroups and Controls widgets were offered and not chosen.

## After: counts and the Mac's read (6ca8927, b554534; 0.4.385 on all three)

- Active counted a Mac's local tmux tabs (Active's running rows marked open here, W6) as running:
  "0 open · 22 running". Now open, as Active shows them.
- The Mac widget still read nothing: logged as Cocoa 257, permission denied. Xcode signed the Mac
  extension with the wildcard "Mac Team Provisioning Profile: *", which cannot grant a `group.` App
  Group, so the sandbox kept it out though its signature named the group (iOS/visionOS extensions
  have the explicit profile). On a Mac the snapshot now lives in a team-prefixed group,
  `GPT_WIDGET_GROUP` = `7JQGQ7CRH8.com.glasspowertools.widgets` (no profile needed), elsewhere the
  library's group; Info.plist key `GlassWidgetGroup`. Verified: the restarted extension reads it;
  the owner sees the counts.
- The snapshot was rewritten every minute unchanged (dates to the second vs fractions): compared
  as written now.
- A backboardd abort on the headset at 11:34 (RealitySimulation, xrOS 27.2 beta) was the owner
  viewing a three.js page in the browser: unrelated.
