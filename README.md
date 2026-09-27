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
  Secure Enclave), tabs, themes, workgroups, port forwarding, and an SFTP file browser. A local
  shell on the Mac.
- **Databases:** MySQL, PostgreSQL and SQLite — browse, filter and edit rows, follow foreign keys,
  write and explain queries, reach a database directly with TLS or through the machine's own SSH
  connection, or mark it read-only.
- **Remote desktops:** RDP and VNC, with the remote resolution following the window, audio and
  clipboard.
- **Editor:** files on this device or on a server, projects with a file tree, syntax highlighting
  for fifteen languages, and previews for Markdown (with Mermaid diagrams), HTML, SVG and CSV.
- **Everywhere you are:** the library syncs through iCloud, and credentials through iCloud
  Keychain. Keys made in the Secure Enclave stay on their device.

## Status

Not released yet. It is in use daily and in release preparation; there is no download or TestFlight
build today. What is verified, and how, is recorded in
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
Tailscale account for device discovery; the released Mac app will also check its update feed. There
are no analytics. Secrets live in the Keychain. See
[SECURITY.md](SECURITY.md) for how credentials and connections are protected — and what is not
protected — and how to report a vulnerability.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The project's decisions, rules and working notes are in
[`memory-bank/`](memory-bank/toc.md); [`AGENTS.md`](AGENTS.md) is the guide for making changes.

## Licence

MIT — see [LICENSE](LICENSE). Third-party components keep their own licences; see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), and Settings ▸ About ▸ Acknowledgements in the app.
