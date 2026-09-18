# A terminal service that synced without its settings — 2026-09-17 (night)

**Owner:** coordinating agent. **State:** BUILD → DOCS.
**Reported:** *"I set up the desktop on iPhone and ssh — the desktop settings transferred and
worked, but the ssh settings didn't."* The Mac showed **Terminal on juliet** in the library and
connecting said: *"has no saved terminal configuration. Edit the service to set it up, or remove
it."*

## What it actually was

**The Mac deleted the phone's configuration.** Not a sync that failed to deliver — a delivery that
arrived and was then overwritten.

`GlassServiceRecords.replaceAll(with:)` reconciles the catalog to the list it is handed: every
stored configuration of that kind **not** in the list is deleted. Its own documentation calls it
*"the one call in D26 that can destroy data by doing exactly what it was asked"*, and it guards the
case it can see — a write before the catalog was ever read.

It cannot guard the case that bit here: the catalog was read, and then **changed underneath**. That
is what D19 does on every delivery.

And the terminal's list was stale by construction:

```swift
func loadServersIfNeeded() {
    guard !hasLoadedServers, store.isReadable() else { return }
```

`catalogDidLoad()` is called after *every* catalog load. The terminal ignored all of them after the
first. So:

1. The phone created the service — the link went into the catalog and synced. ✅
2. The phone saved its configuration onto that link, and it synced too. ✅
3. The Mac had read its server list once, at launch, before any of that arrived.
4. The Mac saved *something else* — any server edit will do — and `replaceAll` wrote its stale
   list back, **deleting the configuration the phone had put there**.
5. The link survived, because a reconcile clears configurations and not links.

Which is precisely the state reported: a service the library offers Connect for, with nothing
behind it.

**Why the desktop was fine.** The desktop's `catalogDidLoad()` calls `app.load()` directly and the
database's calls `connectionManager.load()`. Both re-read every time. The terminal was the only
capability whose list could be stale when it reconciled — so the desktop configuration added in the
same sitting travelled and survived.

## The evidence, in order

| Step | Finding |
|---|---|
| Is the configuration in the CloudKit payload? | **Yes.** The whole `HostProfile` is JSON-encoded as the record payload; `HostServiceLink.configuration` has no custom coding keys and nothing redacts it |
| Does writing a configuration bump the merge key? | **Yes.** `HostCatalogStore.mutate` raises `updatedAt` monotonically, so it is not losing a merge on a stale timestamp |
| Can I read the Mac's catalog to check? | **No.** TCC refuses the shell `~/Library/Group Containers/group.sh.glas.shared` — `Operation not permitted` |
| Does the Mac hold it after the re-read fix? | **No.** The edit sheet came up **blank**, so `ServerManager` found nothing, so the catalog holds no decodable ssh configuration for that link |
| Does Mac → phone work? | **Yes**, demonstrated by re-entering it on the Mac |
| Can a stale list destroy another device's record? | **Yes** — `aStaleListDeletesAnotherDevicesConfiguration`, which fails on the old once-only path with *"a save on this device deleted a configuration another device had written"* |

## Fixed

- **`ServerManager.reloadFromStore()`**, called from `catalogDidLoad()` in place of
  `loadServersIfNeeded()`. The once-only guard is right for *"the store can answer now"* and wrong
  for *"the store says something different now"*. Two tests: a late-arriving service is found, and
  a stale list no longer deletes another device's record.
- **An unconfigured link can be set up.** `setupDraft(for:host:)` answered nil when there was no
  saved server, so Edit had nothing to show — for exactly the case the failure message is about.
  The only offered action that worked was the destructive one, and the app was walking the user
  toward deleting the thing. It now returns a **new** draft; `commit(endpointID:host:address:)`
  binds to the endpoint it is given, so setting it up fills the existing link rather than making a
  second service beside it. The old test asserting nil documented the behaviour without defending
  it and was updated with the reason.

## Not fixed, and worth deciding on

- **The data was already gone.** The fix prevents the next occurrence; it cannot restore what the
  reconcile deleted. Re-entering the service on the Mac was the recovery, and it synced to the
  phone.
- **`replaceAll` is still a whole-kind reconcile driven by one device's in-memory list.** Freshness
  is now maintained by every capability, but the primitive remains one where a stale caller deletes
  another device's work. A per-record write, or a reconcile that refuses to delete records it has
  never seen, would make the class impossible rather than merely avoided.
- **`configurations(ofKind:)` skips undecodable records silently**, by design. Correct for one bad
  record; it also means a shape mismatch between builds would look exactly like this report.
