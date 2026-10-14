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
