# Release preparation: dependencies and the audit's fixes — 2026-09-27

**State:** DOCS. Owner: coordinating agent. Authorized by the owner on 2026-09-26/27 as release
preparation, with local commits; nothing pushed.

## Dependencies

| Change | Commit | Evidence |
|---|---|---|
| Point releases within range: swift-nio 2.103.0, swift-nio-ssl 2.37.5, swift-collections 1.7.1, swift-asn1 1.7.3, swift-async-algorithms 1.1.6 | `c645783` | package suite green |
| `Tools/Packages/sync-xcode-pins.py`: copies the package's pins into Xcode's `Package.resolved`, which does not follow a `swift package update` on its own | `c645783` | `PackagePinAgreementTests` |
| SwiftTerm 1.15.0 → **1.18.0** | `96d394f` | suite green, Mac app builds; not yet looked at on screen |

Not taken, and why:
- **SwiftTerm 1.19.0** adds a build-tool plugin (it writes SwiftTerm's branch and commit into a
  generated file on every build) that Xcode refuses to run until someone trusts it. The owner's
  call. 1.20.0 is a pre-release.
- **tree-sitter 0.27**: SwiftTreeSitter, on its latest tag and on `main`, allows only
  `.upToNextMinor(from: "0.25.0")`; the app is on 0.25.10, the newest that allows.
- **swift-crypto 5**: postgres-nio 1.33.1 (latest release) allows `< 5.0.0`; its `main` allows
  `< 6.0.0` but is unreleased. mysql-nio, upstream and the fork this app pins, allow `< 5.0.0`.

## The public-release audit's fixes

| Finding | Fix | Commit | Proof |
|---|---|---|---|
| Built-in terminal theme's identifier spelled a joke in hex | New random UUID; the old one is read from saved and synced libraries, rewritten, and saved once | `bf178ce` | two tests, each failing without its half of the fix |
| Signing identifiers hard-coded in six places | `Config/Identity.xcconfig`, read by the project, entitlements, Info.plists and `GlassAppIdentity`; a fork overrides it in a git-ignored local file | `9db8178` | built apps' entitlements byte-identical on macOS, iOS, visionOS and the widget |
| Widget linked to `glassh://`, a scheme nothing handles | Links removed; a tap opens the app | `9db8178` | builds |
| swift-nio-ssh patch N7 changed only an error's wording | Dropped; the file is upstream's again | `685f074` | package suite 363/363 |
| Database connections could be unencrypted without a word | Warning under the encryption toggle; detail says "not encrypted" | `ca471f5` | unit test |
| Query history stored literals (passwords in `ALTER USER`) by default | Redaction on unless turned off; setting and writer read it the same way | `ca471f5` | unit tests |
| MySQL metadata lookups escaped names by hand | Bound parameters | `0b5aa99` | live test on a real MySQL: a table with a backslash under `NO_BACKSLASH_ESCAPES` showed no columns before, correct after |
| Editor UI-test seed could run without the per-run UUID | Seed requires the UUID and a non-standard suite; the editor gets its own suite and no sync under UI tests. The seed had been able to empty — and sync away — the real project list | `31801ff` | two iPhone simulator UI tests that seed projects pass |
| RDP trust evaluated from the leaf certificate only | NIOSSL records the presented chain; `SecTrust` evaluates it whole | `3c039bb` | RDPKit suite 1,015; no multi-certificate test exists |
| VNC sessions unencrypted after sign-in | Stated in the setup form where VNC is chosen | `663eaf4` | builds |

Found already fixed: the "Set Up…" path that bypassed the address gate was removed on 2026-09-11
(`8fb17f9`); the notes had kept it as open.

The push environment (`aps-environment`) is now a build setting, `development` for local builds;
the release build must pass `GPT_APS_ENVIRONMENT=production` (D38).
