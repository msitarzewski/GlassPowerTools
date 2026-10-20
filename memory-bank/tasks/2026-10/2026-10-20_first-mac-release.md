# Ship it: the first Mac release, TestFlight 491, the site and help (2026-10-20)

**His words:** "Ship it!" Asked which outward steps, he chose all three: TestFlight 0.4.491, push to GitHub, and the
first Mac release. The Mac's version: **0.4.491** (his choice; 1.0 waits for the App Store, and every platform
reaches 1.0 together). Mid-way: "Update the public site and help with the features too, please." Then: "We need
screens for the new terminal themes! :D Add that to the list."

## Steps

| Step | State |
|---|---|
| Push main (8 commits, ee8a8007..7f824f86), scanned for private details first | done |
| TestFlight: `release-testflight.sh 0.4.491 491` with Xcode 27.1 (released) | both uploaded (no tester group yet) |
| Help for the new features (a fork owned `site/help/`) | done; build_site passes |
| Site pages: release wording, the looks, time in use, SQL, tmux, This Mac | done |
| `RELEASE-NOTES.md`, `README.md`, `PRIVACY.md`, `SECURITY.md` | done |
| The looks' pictures: `site_shots.sh looks` in the VM → `mac-look-*.webp` | six, each looked at (picture and This Window retaken) |
| Mac release: `release-mac.sh 0.4.491 491 notes.html` | done: notarized and stapled app and dmg; launched from a quarantined download in the VM |
| GitHub release v0.4.491 with the dmg, zip and checksums | published; downloads match the checksums; `releases/latest` points at it |
| Site build and deploy (feed + pages) | live: 90 files match the build; `appcast.xml` served no-cache |
| Commit the docs, pictures and feed | on his word |

## Notes

- **Notary profile:** `glasspowertools-notary` wasn't in the Keychain (the earlier dry runs skip notarization). He
  runs `xcrun notarytool store-credentials glasspowertools-notary --key … --key-id … --issuer …` with the team API
  key ([[app-store-connect-api]] in the private memory).
- **Minutes now sync**, so `PRIVACY.md`, `SECURITY.md` and the help's sync table say each device shares its minutes
  in use per day per machine (no times of day).
- **Pictures:** `Tools/Screenshots/landscape.py` draws the made-up landscape behind the Picture look, so the shot is
  reproducible; `site_shots.sh looks` takes Digital Rain, Synthwave, Amber, Green, a picture and This Window, dark
  only. Connections is minimised, not closed (the demo race with `--demo-close-connections`).
- **Sparkle and dev builds:** the app built by `build.zsh` has build number 1, so once the feed has 491 a dev copy
  would offer the release as an update.

## Found while checking the release

- **No iCloud account:** the library's footer says "iCloud sync failed" and its details show CloudKit's raw "This
  request requires an authenticated account". It should be the "iCloud unavailable" state, saying to sign in to
  iCloud. For 0.4.492.
- **Scale Text and the Mac's local terminal** (his question): an omission, not a limit. `TerminalScaling` is applied
  only in `TerminalWindowView` (SSH sessions); `MacLocalTerminalPaneView` never got it, though its engine
  (`MacLocalProcessEngine.setScaling`) and PTY proxy (the kept-grid guard in `sizeChanged`) already support it.
