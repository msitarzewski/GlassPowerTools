# Connections do not travel between devices — the gap behind the CloudKit report

Owner: coordinating agent. 2026-09-14. **Status: diagnosed, not fixed. Needs a decision.**

Reported by the user: CloudKit sync was not working for connections.

## What is actually true

**CloudKit works.** It was proven on hardware (a host defined on the Vision Pro appeared on the Mac
unaided), the entitlements are correct on the installed app, and since 0.4.92 the library also
updates live through silent pushes.

**A first diagnosis was wrong and is recorded here so it is not repeated.** `synchronizeCatalog()`
has one caller, which looked like "nothing publishes after a change" — but that caller is `load()`,
and *every* mutation ends in `await load()`. Publishing was never missing. Checking the callers of
the callers is what corrected it.

**The real gap is that only the catalog syncs.** What travels and what does not:

| Travels | Stays on the device that made it |
|---|---|
| `HostProfile` — name, address, aliases, tags | **Terminal:** `ServerConfiguration` → `SharedDefaults`, key `servers` |
| `HostServiceLink` — kind, display name, credential id | **Database:** `DatabaseConnectionConfig` → `UserDefaults.standard` (`ConnectionManager.swift:38-47`) |
| Credentials — iCloud Keychain (D18/D23) | **Desktop:** `DesktopConnection` → `connections.json` (`DesktopAppModel.swift:76`) |

`grep -rn "CloudKit\|CKRecord" Sources/GlassTerminal Sources/GlassDatabase Sources/GlassDesktop`
returns **nothing**. No capability's record has ever synced.

## What the user sees, and why it is the worst possible shape

The second device receives the host, sees its service rows, and **holds the password already**,
because credentials synchronize by default (D18). Then Connect says:

> "… has no saved terminal configuration. Edit the service to set it up, or remove it."
> — `GlassTerminalCapability.swift:227`, and the same sentence in the database and desktop
> capabilities.

The library looks complete and nothing in it works. A host that had not synced at all would be
*less* confusing than one that syncs everything except the part that connects.

**This subsumes the open item recorded as "SSH key records do not sync."** That was the same defect
seen through one capability; it is all three.

## Three ways to fix it

**A — an opaque configuration on the service link.** Add `configuration: Data?` to
`HostServiceLink`; capabilities encode their own record into it and decode on the other side.

- *For:* no CloudKit schema change whatsoever — the profile already travels as one encoded payload
  and `HostProfile` already versions itself and decodes records written by builds that knew less.
  One sync path, one merge, already proven. Deletion already cascades (D25).
- *Against:* changes `HostProfile` in GlassConnectionKit, a shared package. Puts capability data in
  the catalog, which stretches "capabilities own their storage" — though the link already carries
  `credentialID`, so the boundary is not pristine today either.

**B — a second CloudKit record type per configuration.** `ServiceConfiguration`, keyed by
`endpointID`, carrying the same opaque payload.

- *For:* the catalog stays exactly what it is; configurations can be fetched and merged separately;
  a malformed configuration cannot stall a host sync.
- *Against:* a new record type is **a schema commitment** — the backend's own header says fields are
  hard to change once real data exists. It is a second merge to write, own and test.

**C — each capability syncs its own records.** Three implementations of what D19 already does once.
Recorded for completeness; the merge exists precisely so this does not happen.

**Recommendation: A.** It reuses a proven, hardware-verified path, adds no CloudKit schema, and is
reversible — an optional field that older builds ignore. The size question is real but small:
a `DesktopConnection` or `ServerConfiguration` is on the order of a kilobyte against CloudKit's
~1 MB record limit, and the check belongs in the encoder.

## Constraints any fix must respect

- **Secrets never enter the catalog.** The project rule is *"keep metadata separate from secrets"*,
  and credentials already have their own synchronized home in the Keychain. A configuration payload
  carries the *reference* (`credentialID`), never the secret.
- **A record this build cannot decode must not stall a sync** — the existing backend already skips
  and logs, and the same rule has to hold for configurations.
- **The local host is not shared.** D8's "This Mac" and its services are local by definition and
  must not travel.
- Whatever lands needs the two-device check, which no test can replace.

## Next action

The user's decision on A, B or C. Until then, the honest description of the product is: **the
library syncs; the connections inside it do not.**
