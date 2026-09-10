# Progress

Updated 2026-09-10.

## Done

- The decision to merge, with its reasoning and its costs, recorded in [decisions](decisions.md).
- This memory bank and the project guide.
- The staged [merge plan](tasks/2026-09/2026-09-10_merge-plan.md).
- Measurements the plan depends on: source sizes, bundle identifiers, shared entitlement groups,
  deployment targets. See [technical context](techContext.md). Re-verified 2026-09-10 at
  `~/Software/glass/GlassPowerTools` and unchanged.
- The bank reconciled with the actual workspace: project path corrected, sibling layout recorded, and
  the two siblings that are not inputs identified.

- The project-model decision: one multiplatform target, hand-maintained, approved 2026-09-10.
- Stage 1 planned against real APIs and real file locations:
  [task note](tasks/2026-09/2026-09-10_stage-1-shell.md). Its pre-steps and six decisions are
  listed there for the user.

## Not done

Everything else. There is no Xcode project, no application target, no module, no test and no build in
this repository. No source file has been moved from any of the three applications. The public
repositories are untouched.

## Known unverified assumptions

- That a new bundle identifier declaring the existing App Group and Keychain access group inherits
  current hosts and credentials in place. Now concrete: all three apps read
  `<App Group>/GlassHostCatalog/hosts.json`, so it should. Still proven only on a test build
  (Stage 1 step 1.8).
- That capability code moves largely intact. Measured by line count and structure, not by attempting
  it.

## Carried forward from glassDT, still open there

- Whether a GNOME sign-out now closes the session window rather than showing a failure panel.
- Whether the RDP Detail scale setting sharpens text on the user's Ubuntu host or merely shrinks the
  interface, which decides whether Automatic stays the default.
- A session indicator for encrypted versus unencrypted connections, and an SSH tunnel for VNC.
