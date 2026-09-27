# Contributing

Thank you for looking. Glass Power Tools is one app for the machines you work on — terminal,
databases, remote desktops and an editor — built natively for Vision Pro, Mac, iPad and iPhone.

## Before you start

- Read [Documentation/BUILDING.md](Documentation/BUILDING.md) to build it and run the tests,
  including how to sign it under your own team.
- For anything larger than a small fix, open an issue first to agree the approach.
- Security problems go through private reporting, not issues: see [SECURITY.md](SECURITY.md).

## How the project works

The repository carries its own working notes in `memory-bank/`: decisions with their reasons
(`decisions.md`), the project's rules (`projectRules.md`), what is verified and what is not
(`progress.md`), and a record of each piece of work under `tasks/`. `AGENTS.md` is the guide for
anyone — person or coding agent — making changes. The parts that matter most:

- **Reuse before writing.** Most behaviour already exists somewhere in the app. Find its owner and
  extend it rather than adding a second copy.
- **Keep the family's interface.** The library, its selection, favorites, collections and detail
  panel work the same way for every kind of service. A capability supplies its data and actions;
  it does not invent its own navigation.
- **Every platform.** A change is not done until it works on Mac, iPad, iPhone and Vision Pro, or
  says why a platform is different.
- **Say what is proven.** A pull request says what was run — unit tests, UI tests, a real device,
  a real server — and what was not. A test that has never failed without its fix proves nothing,
  so show it failing first.
- **Validate what comes from the network.** Lengths, sizes and protocol state from a server are
  untrusted. Fail closed, and never swallow an error silently.
- **Errors say what to do.** Messages are plain sentences with the action that fixes the problem;
  the underlying error goes to the log.

## Pull requests

- Keep a pull request to one change, with tests where the behaviour can be tested.
- `swift test` must pass (unlock the Mac first; see the building guide), and the app must build for
  macOS, iOS and visionOS.
- Adding a dependency means adding its entry to `Tools/Licenses/components.json` and running
  `Tools/Licenses/generate-acknowledgements.py`; the tests check this.
- Changing third-party code in `Packages/` means recording the change, and why, in that package's
  `PATCHES.md` (or `GLASSDT-PATCHES.md` for RDPKit). Prefer sending the fix upstream too.
- Examples and test fixtures use neutral values — `alpha`, `bravo`, `example.com`, addresses in
  `192.0.2.0/24` — never a real machine, address or account.

## Licence

Contributions are accepted under the project's [MIT licence](LICENSE). Third-party code keeps its
own licence; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
