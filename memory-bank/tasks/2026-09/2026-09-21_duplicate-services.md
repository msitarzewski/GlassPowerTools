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
