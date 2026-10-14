# Spike: machines as locations in the Finder and Files (D72 phase 5)

**Owner's go:** "Go ahead with 5" (2026-10-13, 19:35, while away; he tests when back).
**Status:** in progress. A spike: measure, then recommend. Nothing ships as working until the owner has seen it.
**Owner:** the agent.

## The question

Can a File Provider extension (`NSFileProviderReplicatedExtension`; macOS 11, iOS 16, visionOS 1) show a machine's
SFTP home folder in the Finder's sidebar (and the Files app), read-only, using the app's own SSH stack and the
machine's saved credential and pinned host key?

## What must be measured, in order

1. **Linking:** the extension target links `GlassSSHTransport`, which brings swift-nio, swift-nio-ssh and Citadel.
   Record the extension's size and its resident memory while listing a folder.
2. **Credentials:** the sandboxed extension reads the saved password or key through the Keychain access group.
   - On the Mac, an extension's entitlements are signed with the team's wildcard profile. That profile could not
     grant a `group.` App Group to the widget (techContext, 2026-10-12).
   - Keychain access groups may hit the same wall. Measure: build, sign, run, read.
3. **Host trust:** the extension cannot prompt, so it connects only to a machine whose host key is already
   pinned, and otherwise says to connect once in the app.
4. **Enumeration:** list the home folder through `NSFileProviderEnumerator`. Fetch a file's contents on demand.
   Read-only: every write refused.
5. **Registration:** `NSFileProviderManager.add(domain)` per machine, removed with the machine, and only on the
   owner's word, since it adds sidebar entries to his Finder.

## Risks known before starting

- Each machine becomes a domain that lives in the Finder's sidebar until removed. An agent should not add domains
  to the owner's real Finder unattended. The spike registers a test domain for the **scratch VM** only, and removes
  it at the end.
- Sync semantics (conflicts, offline edits, eviction) only matter once writes exist, so they are out of scope here.
- On visionOS, an App Store upload of a File Provider UI extension is reported blocked (forum thread 802442).

## Log

- 19:40: plan written. Next: an extension target (Mac) linking `GlassSSHTransport`; measure step 1.
- 22:01 **step 1 measured:** a macOS File Provider extension target, `GlassPowerToolsFiles` (`FileProvider/`), links
  `GlassSSHTransport` (swift-nio, swift-nio-ssh, Citadel). The binary is **31 MB**. It builds and signs with the
  sandbox, `network.client`, the team App Group and `keychain-access-groups`. It is a separate derived-data build
  (`$SP/dd-spike`) and has not been installed.
- 22:02 **step 2, on paper:** the extension carries the team's wildcard profile, "Mac Team Provisioning Profile: *".
  That profile grants `keychain-access-groups` `<TEAM>.*`, so the app's team-prefixed credential group is allowed.
  This differs from the widget, where a `group.` App Group was refused. **Still to prove at run time:** the
  extension reading a credential. That needs a registered domain, which adds a Finder sidebar entry, and so waits
  for the owner's word.
- **Next without the owner:** steps 3–4 as library code testable from the test runner against the scratch VM
  (pinned-key-only trust, listing the home folder, fetching a file), then a written recommendation. Registering
  a domain waits for him.

## Findings and recommendation (22:10)

**Proven or settled by existing code:**
- **Links and signs on the Mac:** see steps 1 and 2 above. The team profile grants the Keychain group the
  credentials live in.
- **Pinned keys only:** an `SSHTransport` with no trust decider refuses an unpinned or changed key
  (`SSHHostTrustRequiredError`, `SSHHostTrust.swift`). An extension that cannot prompt therefore connects only to
  a machine trusted in the app first, and says so. Nothing new is needed.
- **Listing and reading files:** the editor's project path (`openSFTPConnection`, `GlassTerminalDirectoryLister`)
  already lists folders and reads files with bounds, with live tests against the scratch VM.

**Unproven until a domain is registered on a real Mac:**
- The Keychain read from inside the extension's sandbox.
- Sockets and NIO inside a File Provider process.
- The extension's memory under the system's limit.
- How the Finder shows the location.

Registering a domain adds a sidebar entry to the owner's Finder, so it waits for him.

**Recommendation:**
1. **With the owner present:** register one domain, for the scratch VM, from a debug-only command. Browse it in the
   Finder, measure memory, then remove the domain.
2. If that holds, build read-only browsing for real: a domain per machine with a Terminal service, switched on
   per machine by the owner (never automatically), metadata for the extension in the App Group, and a message
   when the host key is not yet trusted.
3. **Writes later, as their own decision:** conflicts, offline edits, eviction and the verified upload's
   no-replace rule all need designing.
4. **iPhone and iPad after the Mac:** the same extension point, with automatic signing for the App ID. Vision Pro
   waits on the reported App Store block (forum 802442).

**State left:**
- The `GlassPowerToolsFiles` target is in the project and embedded in Mac builds, inert: no domain, an empty
  root. Remove it if the owner declines.
- Nothing has been installed from the spike build.
