# Stage 4 — the remote desktop capability (glassDT) and its engines

Owner `/root`. Drafted 2026-09-10. **Status: planned; starts when Stage 3 reaches parity.**

## Task

- **Objective:** glassDT at parity — RDP and VNC sessions, Metal presentation, input mapping,
  spatial display on visionOS, import commands, audio, cursor decoding — with its engines as
  packages, its dual local/shared catalog and pairing machinery removed in favour of the shell's
  one catalog, and its settings merged into the one surface.
- **Inputs, read-only:** `../glassDT` (`Sources/GlassDesktopCore`, `Sources/GlassDesktopUI`,
  ~5,573 lines; `Packages/RDPKit`, `VNCKit`, `GlassRDPTransport`, `GlassVNCTransport`; `App/`;
  `Tests/`, `UITests/`; `VALIDATION.md` and its Memory Bank for the tested-server ledger).
- **Already the target shape:** glassDT is Core + UI over engine packages, which is exactly the
  merged layout. This stage is mostly a move.

## Module layout

| Module | Owns | Depends on |
|---|---|---|
| `Packages/RDPKit`, `VNCKit`, `GlassRDPTransport`, `GlassVNCTransport` | moved verbatim | swift-nio, nio-ssl |
| `Sources/GlassDesktopCore` | moved verbatim | the four engine packages, GlasSecretStore (`RDPCredentialStore`), GlassConnectionKit |
| `Sources/GlassDesktopUI` | moved; `DesktopAppModel` loses its dual catalog, publication, outbox and `pairedSection`; `DesktopLibraryView` is replaced by the shell's library with `ConnectionEditor` as the desktop service editor; `DesktopSettingsView` becomes shell settings pages | `GlassDesktopCore`, `GlassShell`, `GlassLayers`, later `GlassSSHTransport` |
| App target | registers the desktop capability (`kind: .rdp`; VNC kind arrives in Stage 5), declares the `desktop` `WindowGroup(for: UUID.self)` | — |

## What is deleted rather than moved

`DesktopAppModel.swift:58-76` (local + shared catalog, `resolvesSharedContainer`),
`hostLibraryStatus`/`pendingHostPublicationCount`, `pairedSection` and `PairServiceView`
(`DesktopLibraryView.swift:291-343`), the `glassdt://` URL handling and "the paired app could not be
opened" path — all machinery for three processes.

## Layering

glassDT's frost/opacity state (`display.glass.opacity`, `frost`) is already migrated by
`GlassLayers`; `DesktopSessionView`'s window frame and canvas backdrop route through
`GlassLayeredWindow`. The Metal surface keeps its own presentation; source resolution stays
independent of local scale and spatial tilt, as decided.

## Validation (from the family's testing table)

RDP against the named real servers in glassDT's `VALIDATION.md` (Windows, Ubuntu GNOME, the
identified macOS implementation); VNC likewise; malformed-input/fuzz coverage moved with the kits;
resize/reset and GPU resource lifetime; physical Vision Pro spatial checks (tilt, resizing, input,
legibility) recorded separately from simulator; the two glassDT open items (GNOME sign-out window
behaviour; whether the RDP Detail scale setting sharpens text on the Ubuntu host) re-tested here.

## Carried to Stage 5

VNC-over-SSH via `GlassSSHTransport.forward` (the engine already exists); the encrypted/unencrypted
session indicator; the `.vnc` service kind and VNC credential record — all three were deferred in
glassDT only because sibling apps could not decode them, and become safe once the source apps are no
longer reading the catalog (Stage 6) or once decoding is tolerant.
