# Project brief

## What this is

Glass Power Tools is one native Apple application for every machine a user owns and every service on
it: terminal and file transfer over SSH, databases, and remote desktops over RDP and VNC, with text
editing available as a further capability. Bundle identifier `com.glasspowertools`. MIT licensed.

It replaces three separate applications that were converging on the same shell: glas.sh, glassdb and
glassDT.

## Where this came from

The journey began with building a world-class SSH tool **for visionOS**, one that uses what visionOS
actually offers rather than shipping a phone app into a headset. Databases followed for the same
reason, then remote desktops. Glass Power Tools is the same intent at full scope.

This is the reason for the 26.0 floor. It is **not** housekeeping or a preference for recent APIs. It
is the version that reaches the visionOS capabilities the product is built on, and everything else
inherits that floor rather than the other way round.

It follows that **visionOS leads the design**, and Mac, iPad and iPhone adapt from it. A surface
designed for the Mac and then fitted into a headset arrives having already given up the things worth
having. The reverse adapts cleanly. Where the three source applications did this backwards, the merge
is the moment to correct it, not to preserve it.

## Why it exists

The shared host catalog already models a host that owns several services of kind `ssh`, `database`
or `rdp`. The three applications were each a partial view of that one model, and a large amount of
code existed only to keep three processes agreeing about it. Merging deletes that code rather than
moving it.

The differentiator is not any single protocol client, all of which have mature competitors. It is the
combination: every host, every service, one credential store, one settings surface, and on Vision Pro
a spatial workspace where a host's terminal, database and desktop can sit side by side. Three
separate applications cannot compose that way.

## Scope

- Native Mac, iPad, iPhone and Vision Pro. Apple TV and watchOS are excluded.
- Capabilities in build order: SSH terminal with SFTP and port forwarding; databases; RDP and VNC
  remote desktops; then the editor interface. GlassEditorKit comes in as a library from the start.
- Apple Silicon only, 26.0 floor on every platform.
- The Glass layering system, including window and title bar transparency, is foundational rather than
  a later polish pass.
- One library, one settings surface, one credential store, one window and navigation model.

## Requirements added during the build

- **2026-09-10 — choose a key file, not only paste.** SSH private-key import (settings SSH-keys page
  and the server form) must offer a file picker in addition to the pasted-text box, reading the
  chosen file through the same import path; the file's path and contents are never persisted
  outside the credential store. Owner: Stage 2 W3.

## Non-goals

- Matching competitors feature for feature inside any single capability. Depth is chosen for what a
  user needs while already looking at that host.
- Shipping to an App Store at this stage. None of the three source apps is published, which is why
  merging carries no product-identity cost. *Superseded 2026-09-25 by D38 (`decisions.md`): the Mac
  ships outside the App Store (Developer ID, notarized, updated by Sparkle), because the App Store
  requires a sandbox a local shell cannot live in; iPhone, iPad and Vision Pro go to TestFlight, then
  the App Store. Neither has happened yet (2026-10-12).*

## Constraints carried in

- Follow protocol specifications precisely and advertise only implemented capabilities.
- Validate untrusted protocol data before use.
- Keep credential storage in GlasSecretStore, with its existing eligibility and mobility rules.
- Preserve the familiar library navigation. Users must not relearn the app.
- Never present a stub, a compile, or a dependency declaration as a working feature.

**Added 2026-09-10 (user):** system-wide tags are essential — labels, groups, clients — and
comma-separated text entry is a non-starter. Host aliases and collections are edited with a shared
token/tag field whose suggestions come from one system-wide vocabulary. Assumption in force: one
flat vocabulary; labels/groups/clients are uses of tags, not tag types.

**Added 2026-09-10 (user):** the machine identity (IP or DNS name) belongs to the host, entered
once; services inherit it and never ask for it again. "Connection > Terminal > IP address" is wrong.
Port and username remain per service.

**Refined 2026-09-11 (user):** a service setup form (terminal/SSH, and later database and
desktop) never shows a host/address field, not even as a fallback. The address is defined at the
machine level and inherited; if a host has no address yet, the shell collects it on the host
before any service setup opens. The Add SSH Key window needs a proper layout.

**Added 2026-09-11 (user): one-and-done setup.** Adding a host offers its services right then; a
service is created complete, with its required configuration, in the same sheet — no "Set Up…"
or pending state anywhere, and no legacy path (there is no legacy; plan for the first-run experience).
Layout: machine fields (Name, Address) on top, then tabs `[ Terminal | Database | Desktop ]`; a tab
shows an "Add <kind> to this host" toggle and, once on, only that kind's required fields with the
optional ones under an Advanced disclosure; the tab label marks enabled services. Save is all or
nothing. The same sheet serves Add Host, Add a service (tab preselected, host fields read-only)
and Edit service. Aliases and collections sit under a disclosure. Apple HIG patterns throughout
(rule 15).

**Refined 2026-09-11 (user): the library row.** No "Connect" text, no last-connected value, no
services-count subtitle on any platform — the service icons already say how many there are. The
connect control is one button with two regions: the play glyph connects **every** service on the
host; the chevron picks a single service (tap, click or pinch, not hover-only). The database icon
is Heroicons `circle-stack`; terminal and desktop keep their SF Symbols. Applies family-wide.

## Distribution and documentation (2026-09-25)

- **Updates are automatic on every platform** — Sparkle on the Mac (Developer ID; the Mac App Store's
  sandbox rules it out), TestFlight then the App Store on iPhone, iPad and Vision Pro (D38).
- **Primary audience:** developers who want a first-class Vision Pro experience across the suite.
- **glasspowertools.com**: a landing page, a page per capability and an Anomalous-style help centre,
  written from an audit of the code; Bedrock for the copy (D39).
