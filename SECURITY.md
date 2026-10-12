# Security

Glass Power Tools holds the keys to other machines: SSH keys, database passwords, remote-desktop
credentials. This page says how it protects them, what it does not protect, and how to report a
problem.

## Reporting a vulnerability

Please report security problems privately, through GitHub's private vulnerability reporting on this
repository (**Security ▸ Report a vulnerability**), not in a public issue. Include what you found,
how to reproduce it, and the version (Settings ▸ About). You will get an answer, and a fix or a
plan, as quickly as the problem warrants. Please give a reasonable time to fix a problem before
disclosing it.

Only the latest release is supported.

Problems in third-party code this app carries (`Packages/`) are reported to that project as well;
this repository's `PATCHES.md` files record what is changed locally.

## How credentials are kept

- **Secrets live in the Keychain**, never in preferences or files: passwords, private keys,
  database credentials and host-key pins. Configuration (hosts, services, settings) is stored
  separately from secrets.
- **Syncing is iCloud's.** The host library syncs through CloudKit in your private database;
  credentials and host-key pins sync through iCloud Keychain. Keys created in the **Secure
  Enclave** never leave the device they were made on and are never offered to another device.
- **Nothing is sent anywhere else.** The app connects to the servers you add, to iCloud for sync,
  and, only if you connect a Tailscale account for device discovery, to Tailscale's API. The Mac app,
  once released, also checks an update feed — Sparkle asks on its second launch whether to do so
  automatically, and installs only updates signed with the project's key. It has no analytics or
  telemetry. The editor's Markdown preview runs with a content security policy that
  allows no network access.

## Connections

- **SSH** host keys are pinned on first use, after you confirm them; a changed key stops the
  connection. Older algorithms (SHA-1 key exchange, AES-CTR) are off unless you turn them on for a
  host. RSA keys sign with `rsa-sha2-512`.
- **Databases** support TLS with certificate verification against system trust or a certificate
  you supply, and can be reached through the host's SSH connection instead. A direct connection
  with encryption off is allowed — a database on the same machine, or on a network you trust, is a
  legitimate choice — and the app says so where you set it up. Query history redacts literals
  unless you turn that off.
- **RDP** checks the server's certificate before any credential is sent: against system trust,
  or against a certificate you have pinned for that host and port.
- **VNC** is not encrypted after sign-in. The security types this client supports (none, VNC
  password, Apple Remote Desktop account) protect the password, not the session. Use VNC on a
  network you trust.

## The Mac app is not sandboxed

A terminal has to start your shell and reach your files, tools and SSH agent, which App Sandbox
does not allow. The Mac app therefore runs outside the sandbox, with the hardened runtime and no
runtime exceptions. It is to be distributed outside the Mac App Store, signed with a Developer ID
and notarized by Apple. Its widget extension runs sandboxed: it reads only the summary the app writes
for the widgets (machine names, service kinds, times and counts) from an App Group of its own. The
iPhone, iPad and Vision Pro apps run in their platforms' sandboxes.

## Third-party code

The SSH stack (Citadel and its fork of SwiftNIO SSH) and the RDP engine (RDPKit) are carried in
`Packages/` at recorded upstream commits, with every local change listed and explained in the
package's `PATCHES.md` or `GLASSDT-PATCHES.md`. Every dependency is pinned to an exact revision in
`Package.resolved`. See `THIRD-PARTY-NOTICES.md`.
