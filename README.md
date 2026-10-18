# Glass Power Tools

Terminals, databases, remote desktops and an editor for every machine you work on — one app,
built natively for Apple Vision Pro, Mac, iPad and iPhone.

## Why

A developer's machines each offer several ways in: a shell, a database, a desktop, files to edit.
The usual answer is one app per protocol, each with its own list of the same machines, its own
settings and its own idea of where you are. Glass Power Tools keeps **one library of your
machines**. Each machine lists its services — Terminal, Database, Desktop — and connecting opens
the one you want, with the address, keys and trust you set up once.

It started as an SSH client for Vision Pro, and the headset still leads the design: native windows
you can place around you, so a server's terminal, its database and its desktop can sit side by side
in the room. The Mac, iPad and iPhone apps are the same app, adapted to each.

## What it does

- **Terminal:** SSH with host-key pinning, password and key sign-in (including keys held in the
  Secure Enclave), tabs, splits, themes, workgroups, port forwarding, and an SFTP file browser. A
  local shell on the Mac. Terminals kept in tmux, on servers and on the Mac, outlive the app and can
  be picked up on another device. Windows scale as well as resize, and on the Mac a file whose path
  a terminal prints previews over it.
- **Databases:** MySQL, PostgreSQL and SQLite — browse, filter and edit rows, follow foreign keys,
  see a live diagram of every table and key (in three dimensions on Vision Pro), write and explain
  queries (or ask the on-device assistant for one), reach a database directly with TLS, through its
  machine's SSH connection or through another machine, or mark it read-only.
- **Remote desktops:** RDP and VNC, including Apple's own Screen Sharing protocol (encrypted after
  you sign in with a Mac account), with the remote resolution following the window, a window per
  remote display, image quality that adapts to the link, audio, a shared clipboard with formatting
  and images, and see-through glass on Mac and Vision Pro.
- **Editor:** files on this device or on a server, projects with a file tree, syntax highlighting
  for fifteen languages, and previews for Markdown (with Mermaid diagrams), HTML, SVG and CSV;
  images, PDFs, video, audio and 3D models open as themselves. On the Mac it can be your default
  text editor.
- **Everywhere you are:** the library, favorites, workgroups and projects sync through iCloud, and
  credentials through iCloud Keychain; keys made in the Secure Enclave stay on their device. Active
  and Show All Windows show what is open and running on every device; widgets, Siri and Shortcuts,
  Spotlight, Controls and Handoff reach your machines, and on the Mac so do the Finder's Services,
  toolbar button and Quick Action.

## Status

Not released yet. It is in use daily and in release preparation; there is no download or TestFlight
build today. What the first release holds, and what changed in the builds leading up to it, is in
[RELEASE-NOTES.md](RELEASE-NOTES.md); what is verified, and how, is recorded in
[memory-bank/progress.md](memory-bank/progress.md).

When it ships, the Mac app will be distributed directly (signed and notarized, with automatic
updates) — it cannot be in the Mac App Store, because a terminal cannot work inside App Sandbox —
and the iPhone, iPad and Vision Pro apps through TestFlight and then the App Store.

## Build it

You need a Mac with Apple silicon and Xcode 27. See
[Documentation/BUILDING.md](Documentation/BUILDING.md), including how to sign it under your own
Apple Developer team.

## Security and privacy

The app talks to the servers you add and to iCloud, and to nothing else unless you connect a
Tailscale account for device discovery, or open a link to a 3D model that a terminal printed; the
released Mac app will also check its update feed. There are no analytics. Secrets live in the Keychain. See
[SECURITY.md](SECURITY.md) for how credentials and connections are protected — and what is not
protected — and how to report a vulnerability.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The project's decisions, rules and working notes are in
[`memory-bank/`](memory-bank/toc.md); [`AGENTS.md`](AGENTS.md) is the guide for making changes.

## Licence

Copyright © 2026 Michael Sitarzewski. Glass Power Tools is free software: you can redistribute it
and/or modify it under the terms of the GNU General Public License, version 3, as published by the
Free Software Foundation ([LICENSE](LICENSE)). It comes with no warranty. Contributions come with the
permissions in [CLA.md](CLA.md). Third-party components keep their own licences; see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), and Settings ▸ About ▸ Acknowledgements in the app.
