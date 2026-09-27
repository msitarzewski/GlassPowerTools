# Active context

Where the work is now. Rewritten 2026-09-27; the session-by-session log it replaces is in git
history, and each piece of work's evidence is in its task note under `tasks/2026-09/`.

## State: release preparation, no new features

The owner decided on 2026-09-26 to stop adding features and prepare the first public release.
All four capabilities (terminal, databases, remote desktops, editor) and the shell are built; see
`progress.md` for what is verified and how.

**Authorization in force:** local edits, tests, builds and local commits for release preparation.
**Not authorized without the owner's explicit word:** pushing, opening pull requests or issues
upstream, deploying the site, the git history rewrite, installing over a running copy of the app,
anything touching real servers (SSH and database tests use the disposable test VM only).

## Release-prep checklist

| # | Item | State |
|---|---|---|
| 1 | Licences and acknowledgements | done (`2026-09-26_licensing-and-acknowledgements.md`) |
| 2 | Dependency refresh | done within reach: point releases, SwiftTerm 1.18; tree-sitter 0.27 and swift-crypto 5 blocked upstream (`techContext.md`) |
| 3 | Public-release audit fixes | done (`2026-09-27_release-audit-fixes.md`) |
| 4 | Memory bank curated | this rewrite; quotes paraphrased; `.brain/` untracked |
| 5 | README, SECURITY, CONTRIBUTING, building guide | in progress |
| 6 | Upstream contributions (swift-nio-ssh, Citadel) | drafted locally for the owner's review; nothing sent |
| 7 | Help, site and the Mac release path (D38, D39) | in progress |
| 8 | History rewrite, then the first push | only on the owner's word |

## Open questions for the owner

- Delete the legacy `SFTPRemoteEditorView` sheet? (Recommended.)
- Take SwiftTerm 1.19, which adds a build-tool plugin Xcode must be told to trust?
- The Vision Pro needs re-pairing with the Mac before anything new can be seen on it.

## Working rules that matter right now

- Privacy (rule 61): no real machine names, addresses, device identifiers, hosting details or code
  names in tracked files.
- Every shortcut has one owner (D37, rule 60); read the running app's menu bar after changing one.
- Prove a test fails without its fix before trusting it.
- After `swift package update`, run `Tools/Packages/sync-xcode-pins.py`; `PackagePinAgreementTests`
  fails if Xcode's pins and the package's differ.
