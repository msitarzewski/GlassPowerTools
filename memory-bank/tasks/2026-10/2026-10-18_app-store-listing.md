# 2026-10-18 — The App Store listing

**Objective.** The App Store listing for iPhone, iPad and Vision Pro (D38): the text, screenshots,
privacy and support pages, and the answers App Store Connect asks for.
**Authorization.** The owner, 2026-10-18: "we need the full app store setup, descriptions,
screeshots, etc.", then "free, start now. ill get france settled." Local edits only. Nothing is
committed, pushed, deployed or entered in App Store Connect.
**Owner.** The coordinating agent: the text, the pages and the notes. A forked agent: the
screenshots (`Tools/Screenshots/store_shots.sh`).

## Reuse

glas.sh's draft listing (`../glas.sh/memory-bank/app-store-listing.md`) and its privacy page
(`../glas.sh/docs/privacy.html`) were the starting point. Several of their claims are no longer true
and were not carried over:
- the MIT licence (now GPLv3, D82);
- credentials kept on one device only (now synced through iCloud Keychain, D18/D21/D23);
- `glassh://` links;
- the shared App Group with glassdb.

The current facts come from `SECURITY.md` and the help pages, which are written from the code.

## Changes

- `Documentation/AppStore/`:
  - `README.md` gives the answers for App Store Connect: pricing, content rights, age rating, App
    Privacy, export compliance, accessibility labels and review.
  - `metadata/` holds the listing's fields, one per file, in fastlane `deliver`'s layout.
- `PRIVACY.md` and `SUPPORT.md` are rendered by `Tools/Site/build_site.py` as `privacy.html` and
  `support.html`, with footer links. A link between rendered files now stays on the site.
- `App/PrivacyInfo.xcprivacy` is new: the app had no privacy manifest. Only the widget and the
  bundled packages had one.

## The privacy manifest

`nm -u` on the uploaded iOS binary (0.4.479) lists required-reason APIs: `NSUserDefaults`, the
`stat` family, `NSURLContentModificationDateKey` and `NSURLCreationDateKey`,
`NSURLVolumeAvailableCapacity…` and `NSFileSystemFreeSize`. Each use was traced in the source and
given a reason:

| API | Reason | Where it is used |
|---|---|---|
| User defaults | CA92.1 | Settings, history and drafts in the app's own defaults |
| User defaults | 1C8F.1 | The App Group suite, `GlassAppIdentity.appGroup` (`Sources/GlassTerminal/Constants.swift:69`, `GlassLayerStore.swift:78`) |
| File timestamps | C617.1 | Files in the app's own and App Group containers: SQL drafts, recordings, dropped-file inbox, external requests, the host catalog |
| File timestamps | 3B52.1 | Files the user opened: the editor's change check (`GlassEditorFileAccess.swift:186`) and `AtomicSaver`'s `lstat` |
| Disk space | E174.1 | Space checked before a write that then fails with an error: `SessionRecorder.swift:158`, the SFTP download check in `SFTPBrowserView.swift` |
| System boot time | 35F9.1 | How long a touch was held, `SwiftTermHostView.swift:2086` |

Statically linked swift-nio's `fstat` is covered by NIOPosix's own manifest.

Only the widget extension ships on iOS and visionOS. The Mac's extensions are not in those builds.
The file sits in `App/`, a synchronized group, so the app target picks it up on every platform.

Checked: a Debug iOS simulator build's `.app` holds `PrivacyInfo.xcprivacy` at its root, with the four
categories.

## Found on the way: on iPad, opening a database stopped the app

The screenshots fork found it in demo mode on the iPad Pro 13-inch simulator: "No Observable object of type
DatabaseIOSRouter found". `DatabaseWorkspaceView` read `DatabaseIOSRouter` as required on iOS. Only
`GlassDatabaseBootstrap` (the library's window) supplies it, for a phone's in-place workspace. An iPad
with multiple windows opens the workspace in `WindowGroup(id: "database-workspace")`, which has none.
The required read dates from Stage 3 (3e6df408). It was very likely in 0.4.479 on iPad. The owner has
no iPad, so it was never seen on a device.

**Fix:** the read is optional. Connections uses the router only on a phone, where it is always
present. The iPad already opens the Connections window.

**Test:** `UITests/DatabaseOnIPadUITests.swift` opens the demo database on the iPad simulator.
- Before the fix: "com.glasspowertools crashed", the window never appeared, and the app state was 1
  (not running).
- After the fix: passed in 5.6 s.

To make that possible, the demo's database (`GlassDemoMode.shopDatabase`) now makes a one-table
stand-in when `demo-shop.sqlite` is missing, because a UI test cannot put a file in the app's
container.

**Builds:** Debug builds on the iOS and visionOS simulators passed.

## Translations and accessibility (surveyed, not started)

**Translations.** The app is English-only:
- there are no string catalogs, and `knownRegions` is en and Base;
- `SWIFT_EMIT_LOC_STRINGS` is on in most targets;
- there are about 1,400 distinct literal UI strings across 19 modules.

Most of the UI lives in package modules. A literal there looks up the main bundle, so a catalog for
each module needs `bundle: .module` (or `#bundle`) at its strings. The listing can be translated
separately, but a translated store page for an English-only app would mislead.

**Accessibility.** There is a good base of explicit accessibility:
- 191 `accessibilityLabel`, 38 hints, 43 values;
- Reduce Motion in 4 files.

There is no automated audit (`performAccessibilityAudit`). Accessibility Nutrition Labels are
voluntary as of this date, per Apple's App Store Connect help. Declare a feature for a device only
after the common tasks pass with it there.

## Validation

- **Field lengths** checked against App Store Connect's limits: name 17/30, subtitle 30/30,
  promotional text 163/170, description 2849/4000, keywords 99/100.
- **The site builds,** and its link checks pass.
- **The manifest** passes `plutil -lint`.
- **Screenshots:** 17 at App Store sizes, all looked at: iPhone 6.9″ ×5, iPad 13″ ×6, Vision Pro ×6.
  The iPad's database was retaken after the fix and then dropped: upright, its schema sidebar lies
  over the grid and cuts off the grid's left edge (a question for the owner, not yet a defect). They live in `build/appstore/screenshots/`, not committed.
  Left out: Vision Pro's all-four workspace (the windows stack in the simulator), the iPhone's library
  (zero counts under `--ui-testing`), Files (empty until connected), the iPhone's Workgroups (an empty
  screen). The iPhone's desktop is on its side (2868×1320).

## Decided

- **Versions:** 1.0 when it ships on the App Store; TestFlight builds stay 0.4.n until then (the owner,
  2026-10-18: "1.0 when it ships? testflight can stay < 1").
- **Committed and uploaded:** "commit, upload 480, and stage the site. accessibility: yes."

## Open, for the owner

- A demo server for App Review.
- The France encryption declaration.
- An App Store Connect API key, which would let the listing, builds and TestFlight groups be set
  from here.
- `ITSAppUsesNonExemptEncryption`, once App Store Connect has accepted the answers.
- Whether to translate.
- An accessibility audit.
