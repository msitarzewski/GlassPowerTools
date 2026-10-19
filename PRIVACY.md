# Privacy

Glass Power Tools collects nothing about you. It has no account, no analytics, no advertising and no
tracking, and no server of ours sits between you and your machines. This page lists what the app
keeps and where, and everything it sends and to whom.

Last changed 18 October 2026. Every change to this page is recorded in the public repository's history.

## What the app keeps, and where

- **Your library** (hosts, their services and their settings) is kept on your device and, with
  iCloud on, in your own private iCloud database. Only your Apple Account can read it. The developer
  cannot.
- **Secrets** (passwords, private keys, database credentials and the host keys you have trusted) are
  kept in the Keychain, and sync through iCloud Keychain. Keys made in the Secure Enclave never leave
  the device that made them.
- **Favorites, workgroups, projects and terminal settings** sync through iCloud's key-value storage.
  So do each device's name and how many connections it made per day to each machine, with no times
  of day, for the library's overview of the last 30 days.
- **On the device only:** query history (with literal values removed unless you turn that off), SQL
  drafts, session recordings you choose to make, and the app's diagnostic logs. Files you download
  stay where you put them.

## What leaves your device

- **The connections you make.** Terminal, database and remote-desktop traffic goes between your
  device and the machines you add, directly or through the SSH machines you choose to route it
  through.
- **iCloud.** The library and settings above sync through your iCloud account, under
  [Apple's privacy policy](https://www.apple.com/legal/privacy/).
- **Tailscale, if you connect it.** If you connect a Tailscale account to find your devices, the app
  asks Tailscale's API for your tailnet's devices, with the credentials you give it, which are kept
  in the Keychain.
- **Links you open.** A link a terminal prints opens only after you confirm it. A link to a 3D model
  is then downloaded from that address, and kept only if it is a model.
- **Nothing from the on-device assistant.** The database assistant runs on your device through Apple
  Intelligence. What it is given is not sent to a server.
- **Update checks on the Mac.** The Mac app checks glasspowertools.com for updates and downloads them
  from GitHub. On its second launch it asks whether to check automatically. These are ordinary web
  requests that carry nothing about you. On iPhone, iPad and Vision Pro, updates come from the App
  Store.
- **Crash reports, if you share them.** If you choose in your device's settings to share analytics
  with app developers, Apple may pass crash reports for this app to the developer. That choice and
  those reports are Apple's.

## Permissions the app asks for

- **Local Network** (iPhone, iPad and Vision Pro), to reach machines on your network.
- **Face ID, Optic ID or Touch ID**, only to use an SSH key kept in the Secure Enclave.

## This website

glasspowertools.com sets no cookies, runs no analytics and loads nothing from anywhere else.

## Children

The app is not directed at children, and it collects no information from anyone.

## Questions

Write to <msitarzewski@gmail.com>, or open an issue on
[GitHub](https://github.com/msitarzewski/GlassPowerTools/issues). How the app protects your
credentials and connections is described in [Security](SECURITY.md).
