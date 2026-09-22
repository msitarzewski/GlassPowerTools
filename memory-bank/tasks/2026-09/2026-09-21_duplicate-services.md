# Duplicated services on the phone — 2026-09-21

**Reported:** *"services are duplicated on iPhone. Is it a build/versioning/sync part?"* The oscar
host detail on 0.4.195 shows two Terminals, two Desktops, one MySQL, and two Files rows.

**Neither build nor versioning. Sync — and more precisely the design under it.** Read straight
out of the phone's catalog, mounted on the Mac through CoreDevice DeviceFS while the phone was on
the cable (`~/Library/Developer/CoreDevice/DeviceFS/device-…/AppDataContainers/com.glasspowertools/
Library/Application Support/GlassPowerTools/GlassHostCatalog/hosts.json`):

- **Eleven host records named oscar**, all at `192.0.2.10`, from three writer ids. Writer ids
  are persisted in `shell-preferences.json`, so three writers are three devices.
- Two records carry full service configurations: **`c737ab54` is the Mac's** (its preferences key
  it, last-used MySQL) with Terminal + MySQL + Desktop, and **`e6a9eaed` is the phone's** (its
  preferences key it) with Terminal + Desktop. The third writer — the Vision Pro, by elimination —
  made three more with bare links and no configuration.
- The other six are **empty** (no services), all from the phone's writer.

`HostCatalogStore.merge` is per record id; two ids never become one. `GlassShellHost` then
*groups* every record at the same address into one library row and shows the **union** of their
services — which is exactly the screenshot: the Mac's Terminal and the phone's Terminal, the Mac's
Desktop and the phone's Desktop, and the one configured MySQL. The Files rows are the two
Terminals each offering their tool.

**Why there are two configured records.** Each device set oscar up itself, before it had the
other's record — the D26 two-device acceptance run that was never done would have shown this on
day one. `adoptService` matches an existing host by address, but only among records it already
holds; and the six empty records are adoptions that saved a host and then nothing on it.

## The fix has two halves, and only the first is quick

1. **Prevention (small):** setting up or adopting a service on a machine whose address is already
   in the library attaches to that record — including one that arrived by sync a moment ago — and
   an adoption that ends with no service discards its host (`discardAdoption` exists for exactly
   this and evidently is not reached on every path).
2. **Consolidation (a migration, across three devices):** merge same-address members into the
   canonical record, move their service links over, drop links that are the same service twice
   (same kind, name and configuration), tombstone the rest — and let it sync. Preferences keyed
   on member ids already resolve through `canonicalID(for:)`. This is the D26 run, done properly,
   and it touches synced data on every device the account has. Not something to start at 21:00
   without deciding to.

**Until then, nothing is broken underneath:** both Terminals connect, both Desktops connect;
they are two records for one machine, not a corrupt one.

---

# Built — the same evening

*"There is no every device. It's just you, me, this Mac, a Vision Pro, and the iPhone."* So both
halves, tonight, and the second half turned out to be **already written**: `consolidateRecords(of:)`
existed from Stage 6, held back only because the three source applications still read
`hosts.json` by their own record ids. They are obsolete. Rule 57 paying for itself again — the
inventory found the fix before the fix was written.

## What changed

| File | Change |
|---|---|
| `Sources/GlassShell/GlassShellModel.swift` | `consolidateDuplicateHosts()` runs in `load()` after every sync; `consolidate(_:)` folds a group into its canonical record, **only when the members agree on the address**; `deduplicated(_:)` keeps one link per (kind, name) with the smallest endpoint id, and the losers go to their capability as a removal; `mergedMemberIDs` keeps a folded member's id resolving; preferences migrate *before* the fold |
| `Tests/GlassShellTests/GlassShellConsolidationTests.swift` | Four new tests (the oscar shape, capability cleanup, an untouched clean library, deterministic dedup) and five old ones brought to the one-record truth |
| `Tests/GlassShellTests/GlassShellHostAddressTests.swift`, `GlassShellTunnelHopTests.swift` | Same: a group that agrees on its address is one record after load |

## Three decisions inside it

1. **Only a group that agrees on the address is one machine.** Two records named "db" at two
   addresses are two machines sharing a name; the design surfaces that for the user to settle
   with one edit, and merging them would glue a database on one box to a terminal on another.
   The existing address-disagreement test guards it.
2. **Which duplicate survives is decided from the catalog alone** — same kind and name, smallest
   endpoint id — never from this device's preferences, so the Mac, the phone and the headset all
   reach the same record instead of each preferring its own and fighting over it forever.
3. **Preferences migrate first, then the fold.** The other order left favourites keyed on a
   tombstone. Seen red before it was seen green.

## What is proven

| Claim | Evidence |
|---|---|
| The oscar shape collapses to one record with each service once, smallest id winning | `loadConsolidatesAndDeduplicates` |
| The losing duplicate reaches its capability as a removal | `droppedDuplicatesReachTheCapability` |
| A clean library is not rewritten (so not republished) | `cleanLibraryIsUntouched` |
| Disagreeing addresses are left alone | `addressGroupsAndDisagreementIsSettled`, unchanged in that half |
| The whole thing bites | `GlassShellAutoConsolidationTests` seen red with the call in `load()` commented out |
| **On the phone** | **Seen.** 0.4.196 launched on the iPhone over the cable and its catalog copied back with `devicectl device copy from` within a minute: **oscar live: 1, tombstoned: 10** — `c737ab54`, Terminal / MySQL / Desktop each exactly once, all configured. The survivors are the Mac's endpoints, as the smallest-id rule predicts (`76bb64f3` < `f26b23f7`, `48c918ef` < `c48ea999`) |
| The headset | Still on 0.4.123 and still holding its old records live. It cannot resurrect them — in `precedes`, a tombstone beats a live record regardless of dates — but it will keep showing them to itself until it is updated |
