# D26 addendum — keys are their own thing, and get their own manager

Owner: coordinating agent. 2026-09-14. **Status: PLAN. Nothing built.**

Added at the user's direction: *"We need that key to live on its own … so the key itself survives if
I delete the oscar Terminal connection, so that it can be reused for other hosts and services. …
should the keys survive on their own? Yes. That also means we need a key manager interface."*

This corrects a hole in [D26](../../decisions.md): that plan folded the key library in as a detail of
connection sync. A key is not a detail of a connection. It **outlives** connections, it is **shared
by** them, and it needs a place of its own.

## What already works, and must not be rebuilt

Measured 2026-09-14:

- **Deleting a connection already leaves the key alone.** `ServerManager.deleteServer`
  (`ServerManager.swift:371-400`) deletes the server's *password* and never touches
  `sshKeyID`. The behaviour the user wants is already the behaviour.
- **Deleting a key already unassigns it** rather than leaving servers pointing at nothing, and says
  so: *"This removes '<name>' from secure storage and unassigns it from any servers currently using
  it."* (`SettingsView.swift:313-325`).
- **A manager already exists** — Settings → SSH Keys: list, add, edit, delete, copy public key
  (`SettingsView.swift:182-275`).
- **The key material already synchronizes.** `sshKeysPrivateService` and `sshKeysPassphraseService`
  are in `synchronizableServices`.

So this is promotion and completion, not new construction.

## What is actually missing

1. **Keys are terminal-scoped.** `SettingsManager.sshKeys` (`SettingsManager.swift:161`) is the
   terminal's property, persisted under the terminal's `sshKeys` defaults key. The shell cannot
   offer keys, so nothing but the terminal can use one. SFTP already rides the terminal's session,
   but a future capability — the editor, or a database over an SSH forward wanting key auth — has
   no way to reach the library.
2. **The records do not sync.** 22 records, 4.4 KB, in `UserDefaults`. The *material* travels and
   the *record* does not, so a second device holds a secret it cannot name. This is the gap D26
   exists to close, and keys are the part of it D26 got wrong.
3. **Deletion is blind.** The alert says a key will be unassigned from servers using it; it does not
   say **which**, or how many. Deleting a key used by six hosts should not feel like deleting one
   used by none.
4. **No identity beyond a name.** No fingerprint shown, no "added on", no way to tell two similarly
   named keys apart, and no indication of which device a hardware key is bound to.

## Device-bound means it does not appear elsewhere — the user's model

*"Why show it if it's not usable on the platform? Maybe the Terminal using a device bound key
becomes a device bound terminal and doesn't show on iPhone? Trigger being the device based key?"*

**Adopted.** An earlier draft of this note proposed showing a hardware key on devices that cannot
use it, clearly marked. That is worse: a thing you can see, cannot use, and must have explained is
worse than a thing that is simply not there. A connection that cannot be made is not a connection.

**The trigger is Secure Enclave material**, and it is already detectable:
`KeychainManager.isDeviceBoundKeyMaterial` (`KeychainManager.swift:575-577`) matches the
`TRUE_SE_P256:` and `SECURE_ENCLAVE_P256:` prefixes, and routes that material to `deviceBoundConfig`
rather than the synchronizing one. It is the only device-bound credential kind today.

### Bind the service, not the host

A host can own several services. If device-binding applied to the whole machine, a host with a
hardware-key terminal **and** a database would disappear from the phone entirely, taking the
perfectly usable database with it. So the host travels; the service that cannot work elsewhere does
not. On the phone, `oscar` is present with whatever services actually function there.

A host left with no visible services on a device is still worth showing — it is a machine you know
about, with an address, that you can add a service to.

### The rule has two halves, and one of them is easy to miss

`GlassCatalogMerge.reconcile` picks a **whole-profile** winner (`GlassCatalogSync.swift:103-105`).
So:

- **On publish:** a profile is redacted — device-bound services removed — before it is saved.
- **On apply:** this device's own device-bound services are **re-attached** to whichever profile
  wins the merge.

Without the second half the Mac publishes `oscar` without its hardware-key terminal, pulls its own
record back as the winner, and **deletes its own local service**. Nothing fails; the configuration
is simply gone. This is the single most important line in this note.

### Derived, never stored

Whether a service is device-bound is re-evaluated from its credential every time it is saved. A
stored flag would drift: switching a terminal from a hardware key to a password must make it start
synchronizing, and switching back must stop it. A flag that disagreed with the credential would
either leak a connection that cannot work or strand one that can.

### What this decides about key records

It removes the decision. With device-bound services absent from other devices, a device-bound key
has nothing to explain there either — so a key record can ride in the Keychain beside its material,
where it can never contradict it, and there is no second store and no reconciliation rule.
Portable keys synchronize because their material already does; hardware keys stay home along with
everything that uses them.

### Where the user is told

At the point of choice, not afterwards. Generating a Secure Enclave key says plainly that the key —
and anything that uses it — stays on this device. The connection's own editor shows the same thing
while that key is selected. Nothing about this should first be discovered on another device.

## The key manager interface

A workspace-level surface, not a terminal setting. Following D24, it belongs in the library
sidebar as a contributed panel — the same shape Workgroups now uses — so it sits beside the hosts
it serves rather than three levels into Settings.

**The list.** Name, algorithm, fingerprint, added date, and a badge for how it is held — *iCloud*
or *This device only*. Every key shown is a key this device can actually use; a hardware key from
another Mac is not listed here, because nothing on this device can use it and its connections are
not here either.

**Per key:** rename · copy public key · export public key · **used by** · delete.

**"Used by" is the piece that does not exist today** and is what makes deletion safe: the hosts and
services referencing this key, by name, reachable from the key. It is a straight read across the
catalog once connections live there (D26), which is why this comes after the store consolidation
rather than before it.

**Add.** Import an existing private key, or generate one — including a Secure Enclave key, with the
consequence stated at the point of generation: *this key cannot leave this device.* That sentence
belongs where the choice is made, not in a support note afterwards.

**Delete.** Names what will be unassigned and how many, and requires the key's name to confirm when
anything is using it. Never silently breaks a connection.

## Reference semantics, stated so they cannot drift

- A connection references a key **by id**. It never embeds key material, and never a copy of the
  record.
- **Deleting a connection never deletes a key.** Already true; a test should pin it so it stays true
  once connections move into the catalog.
- **Deleting a key unassigns it** from every connection that references it, in one transaction with
  the deletion. Already true for the terminal; must hold for every capability.
- **A key is never deleted as a side effect of anything.** Only the key manager deletes keys.
- Key ids are stable across devices, because the record synchronizes — which is what lets a
  connection made on the Mac find the same key on the phone.

## Where this sits in D26

Revised sequence. The key work moves out of "a detail of step 2" and becomes its own stage:

| | Stage | Why here |
|---|---|---|
| 1 | Connection configuration onto the service link; per-capability stores deleted | Everything else reads the catalog |
| 2 | Synced deletion cascades to capabilities, as local deletion does (D25) | Same seam; fix once |
| 3 | **Keys promoted: library moved to the shell, records beside their material; device-bound services redacted on publish and re-attached on apply** | Needs 1 so a key can be referenced from anywhere |
| 4 | **Key manager surface, including "used by"** | Needs 1 and 3 |
| 5 | Storage cleanup: `glassdb.*` / `app.glassdb.*` key names retired, window restoration bounded, abandoned test suites swept | Independent; last because it is the least interesting |

## Acceptance

The user's scenario, unchanged, plus the one this addendum adds:

1. Add `oscar` with a Terminal service on the Mac, authenticate with an imported key, connect from
   the phone without re-approving host trust.
2. **Delete the oscar Terminal connection. The key is still there**, still usable, and the manager
   shows it is now used by nothing.
3. Attach the same key to a second host and connect with it from a third device.
4. **Generate a Secure Enclave key on the Mac and use it for a second terminal on the same host.**
   The host still appears on the phone. That terminal does not. The database on the same host still
   does. Then delete the hardware key on the Mac and watch the terminal it served become unassigned
   rather than silently broken.
5. **The one that catches the dangerous bug:** with the hardware-key terminal in place, sync twice.
   It must still be there. A publish that redacts without an apply that re-attaches passes every
   test on one device and deletes the connection on the second sync.

No unit test replaces any of these. 1–3 need two devices; 4 and 5 need a Mac with a Secure Enclave
and one other device.
