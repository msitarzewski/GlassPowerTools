# System patterns

Status: **intended structure, not yet built.** Nothing in this file describes existing code in this
repository, because this repository contains no code yet.

## Intended shape

**One multiplatform application target** for macOS, iOS and visionOS — the glas.sh and glassdb
model, decided 2026-09-10 in [decisions](decisions.md) — plus a widget extension, over a set of
local modules:

| Module | Owns |
|---|---|
| Shell | Library, host and service navigation, settings, window and scene model, credentials boundary |
| Layers | Window transparency, title bar backgrounds, panel and detail materials, opacity controls |
| Terminal capability | SSH sessions, SFTP, port forwarding, workgroups. Moved from glas.sh |
| Database capability | Connections, browsing, query surfaces. Moved from glassdb |
| Desktop capability | RDP and VNC sessions, Metal presentation, input. Moved from glassDT |
| Protocol engines | RDPKit, VNCKit, SSH and database drivers, kept as separate modules |

| Editing capability | GlassEditorKit. Library in from the start, interface built last |

The shell depends on no capability. Each capability depends on the shell and on its own engines.
Capabilities do not depend on each other.

**Layers are not a later polish pass.** Every surface gets its material from one system: windows,
title bars, panels, detail views and session canvases. A capability never invents its own background
treatment. This exists before the first capability arrives, because retrofitting transparency across
four capabilities is how the three apps ended up with three settings designs.

Build on what exists: the titlebar material already extracted into GlassConnectionUI and consumed by
all three applications, plus glassDT's window frame, canvas backdrop, opacity and background frost.

## What this replaces

Each item below exists today only because three processes had to agree, and should not be carried in:

- Service pairing between applications.
- The `glassh://`, `glassdb://` and `glassdt://` link routing and its "the paired app could not be
  opened" failure path.
- The shared App Group catalog with its publication journal, removal journal and offline retry.
- Three independently pinned copies of GlassConnectionKit, GlasSecretStore and GlassEditorKit.

The host catalog itself stays. It stops being a synchronisation mechanism and becomes the store.

## Design order

Every shared surface is designed for visionOS first and adapted down to Mac, iPad and iPhone. This
applies to the shell, the layering system, the library and the settings surface. A capability that
arrives with a Mac-shaped surface is adapted, not enshrined.

## Rules for the move

- Move code as modules; do not rewrite working functionality to make it fit.
- Draw the shell boundary before importing the second capability, or the first one's assumptions
  become the boundary by default.
- One capability at a time reaches parity, with the source application still building until it does.
- A capability's protocol engine never gains a dependency on the shell.
