# A machine is the name it was given (D100, 0.4.604)

**Asked (2026-11-05):** "this shoudl be in all connections, not in a machine", with a screenshot of the Mac's
library: one machine's detail listing its own terminal and another named one's, each with a Files row.
**Owner:** this session. **Authorization:** his ask; local build and install as usual. Not committed.

## What happened

- The library file (read only; a copy in `<work>/machine-split/`) held three deleted records of the new machine,
  created at 14:54, 14:56 and 14:58 that day, each deleted within a minute; its terminal lived on the other
  machine's record. Both machines had one address (two sites on one server).
- Cause: `GlassShellHostGrouping.group` joined records by name, by a shared alias, **or by the same address**, and
  D32's fold (`GlassShellModel.consolidate`) then folded any group agreeing on the address into one record on every
  device: the new record deleted, its services moved, aliases and collections unioned onto the survivor.

## Changed

- `Sources/GlassShell/GlassShellHost.swift`: grouping by normalised name only; `normalizedAlias` and the loopback
  list removed (unused after). Comments in `GlassShellModel.swift` (`consolidate`, `sshMember`) and
  `GlassShellTunnelHopTests.swift` say so.
- Tests: `GlassShellConsolidationTests.sharedAddressAndAliasStayApart` (new; replaces the test that pinned alias
  grouping); `GlassShellHostAddressTests.addressGroupsNothingAndDisagreementIsSettled` (was "same address groups").
  Both seen failing with the old `GlassShellHost.swift` and passing with the new, the file restored byte for byte.
- `decisions.md`: D100; D32 marked narrowed.

## Checked

- His 9 live machines group identically under both rules (a script over the file copy): nothing already there
  splits or joins.
- Package tests: 3,368 pass. 0.4.604 built for macOS, iOS, visionOS; installed on the Mac, Vision Pro and iPhone,
  each read back 0.4.604; no new Mac crash report. The library file after the Mac's relaunch: the same 9 machines.

## Left to him

- Add the machine again (every device now has 0.4.604, so nothing folds it), then remove its terminal from the
  machine it was folded into. The folds may also have added an alias and two collections to that machine.
- D27's adoption (`adoptService`) still joins a server from the terminal's form or an `ssh_config` import to the
  machine with its address; its test pins that. Asked whether to make it match by name too.
- TestFlight 603 testers' devices still run the old rule.
