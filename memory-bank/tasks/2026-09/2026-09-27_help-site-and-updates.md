# Help, glasspowertools.com, Mac updates, and the audit's fixes — 2026-09-27

**State:** DOCS. Owner: coordinating agent. Release-prep items 4–7, authorized with local commits.
Nothing pushed or deployed.

## Help (D39)

Every surface was audited against the code, one area per agent (library, terminal, databases,
remote desktops, editor), and the audit's output is the help: **35 pages** in `site/help/`, Vision
Pro first, each claim at what the code does, with a private discrepancy list per area. One
`site/help/registry.json` drives the sidebar, ⌘K search, per-page metadata and JSON-LD, the sitemap
and `llms.txt`.

## The site

`site/pages/` — landing, why, and one page per capability, written in the BEDROCK voice after
loading the whole corpus, then judged against it by a second pass; its factual findings were
applied (the update feed disclosed, the library's lack of export stated, one tested RDP server not
"servers", biometric passwords not synced, Vision Pro notes dated, "Every machine" dropped).
`Tools/Site/build_site.py` builds `_site/` with pandoc and refuses to finish on a broken link or
anchor, a registry/page mismatch, or an address outside the documentation ranges. Seen in a
browser at desktop and phone widths, light and dark; search works. Not deployed.

## Mac updates (D38)

Sparkle 2.10.0 for macOS only; the updater starts only when the build names a feed and the EdDSA
public key (`Config/Identity.xcconfig`), never in a UI-test run. Check for Updates… in the app menu
and in About. `Tools/Release/release-mac.sh` and `appcast.py`: syntax-checked, feed writer tested on
a dummy release, never run (needs the owner's certificate, credentials and key).

**Found on the way:** SwiftPM consults the Keychain for GitHub credentials before downloading
Sparkle's binary and, with two saved entries, waits on a Keychain prompt — every hung build tonight.
`swift build --disable-keychain` / `xcodebuild -packageAuthorizationProvider netrc` (BUILDING.md).

## Fixes from the audit (committed)

Security and data: desktop passwords left in the Keychain on removal and on replacement
(`ce3e828`); Workgroups opening legacy-algorithm connections unconfirmed off the Mac (`73ab819`);
"Close without saving?" ▸ Save losing edits when the save failed (`10e7bac`); UI-test runs syncing
terminal settings to iCloud (`746bbfe`). Text and small defects (`559d84e`): the host-delete
confirmation's false "Credentials are not touched", old app names in user text, ⌥⌘W double-bound,
SFTP folder delete, Workgroup delete confirmation, P-256 import, empty key names, Generate without a
Secure Enclave, "Sync themes", "On this Mac" everywhere, the remote-project error, database window
id, failure-message label, assistant prompts, alert titles, a public log of a raw driver error, host
sort order, Active's swipe hint on the Mac. Each fix with a test was shown failing without it.

## Validation

- The Mac's screen locked partway through the night, so the full suite cannot pass: files written
  with complete data protection are unreadable while locked (rule 56). Instead the suite was run on
  the last commit before tonight's code and on the final tree **under the same lock**: the failing
  tests are identical (137, all file-protection, catalog-save and GlassShellTests' crash under lock),
  and every new test passes. **Rerun `swift test` with the screen unlocked.**
- macOS, iOS and visionOS Release builds succeed after every batch.
- Live: MySQL metadata test against the test VM (red on the old code, green on the new).

## For the owner

In `activeContext.md` ("Open questions").
