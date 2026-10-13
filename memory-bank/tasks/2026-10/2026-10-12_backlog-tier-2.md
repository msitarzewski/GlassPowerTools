# Backlog tier 2 — 2026-10-12

**Owner's ask:** "commit then knock out 2" (tier 2 of `2026-10-12_backlog-inventory.md`, section 0: what is
dated or gates the first release). **State:** the local work is done and committed; what remains needs the
owner (his devices, his accounts, or a decision that publishes something).

## Done

| Item | What | Commit |
|---|---|---|
| **found on the way — critical** | swift-nio-ssh N8: an oversized ECDSA signature in the server's key-exchange reply wrote past a stack buffer before the host key was checked (GHSA-998x-vgvp-xwpc / CVE-2026-43798). Upstream's fix and tests ported; the tests trapped before it. | 2ddc207 |
| B-X25 | After the Mac wakes or the app returns to the foreground, every SSH connection is asked to answer (nio-ssh N7, Citadel F11, `SSHLiveTransports`, `SSHWakeWatcher`); a dead one is shown lost in seconds. The keepalive loop now waits for answers too, so missed keepalives are finally counted. Desktop keys released when the Mac sleeps. Live test through a relay that goes silent. | fd729b1 |
| B-F44 | iPhone Duo. **The window gate:** `supportsMultipleScenes` and, on a phone, a regular-width scene. Measured on the Duo simulator (iOS 27.1 runtime, downloaded for it): a Duo says yes to multiple scenes folded and unfolded, and folded a new window covered the library with no way back but the app switcher; folded it reads compact, so it now opens in place. Ordinary iPhones (26.5, 27.0) say no; iPads yes. Unfolded is unverified: Xcode 27.2 beta's Device Hub has no fold controls (27.1 branch). The database's phone stack re-derives itself after unfolding. Files drag out on iPhone, iPad and Vision Pro. | aa06f51, then the fold-aware gate |
| B-H1–B-H4 | Site, help, AGENTS.md and notes corrected against the code (row limit, rich RDP clipboard, xrdp, device lines, floor, shortcut table, release path). | 2aed1f7 |
| B-T8 (part) | Advisory scan of every upstream's own security advisories (the critical one is not in GitHub's global database). DOMPurify listed at the version Mermaid's bundle carries (3.4.12, not 3.4.16); its advisories look unreachable here (Mermaid `strict`, CSP `default-src 'none'`). The app launches and runs on the iOS 26.5 simulator (iPhone and iPad) — the first run-time check on an OS 26 system. | b29917a |
| B-H9 | swift-log 1.16.1 and swift-nio 2.104.0 taken after a clean re-test (below); SwiftTerm v1.99 is B-Q28. | this commit |

**New defect, ranked into tier 3:** tree-sitter 0.25.10's query cursor counts capture-pool ids in 16 bits and
crashes highlighting very large files (upstream PR 5548, released in 0.26.9). **Re-assessed at the owner's
question:** SwiftTreeSitter's newest release is still 0.25.0 (our pin); its main branch has unreleased fixes
(Jul–Aug 2026) but still says `.upToNextMinor(from: "0.25.0")`, and no open pull request moves it — so no update
reaches 0.26. tree-sitter itself is at 0.26.13 / 0.27.1. Route: vendor tree-sitter 0.25.10 under `Packages/`
with the overflow half of PR 5548 backported (capture-pool ids 16 → 32 bits; the PR's min-heap speed-up is
separate), as a local package of the same identity, which overrides the remote one — the way Citadel and
swift-nio-ssh are carried. Jumping to 0.26/0.27 instead would also change the C API and the grammars' ABI under
SwiftTreeSitter 0.25. Until then the editor's 2M-character highlighting limit is the only bound.
**Resolved otherwise (2026-10-13, 0b5d421):** measured first — tree-sitter's own match limit on the highlight cursor
(256) keeps every capture-list id far below 16 bits and also bounds the time a pending pattern costs (2,000-number
array: 32 s → 1.4 s; 4,000: 262 s → 3.0 s, debug); no real file in 14 languages loses a match even at 64. No vendoring.

## B-H9 — the weekly dependency check's three failures

Neither of the first two was the dependency's fault: the check copies the working tree, and at 08:41 the
D67 change was half-written, so swift-log 1.16.1 "failed to build" in our own test files; swift-nio 2.104.0
failed one iCloud settings test that runs 34 s and logs sandbox errors. **Re-run against the clean tree, both
passed everything** — resolve, build, every test target, the app for macOS, iOS and visionOS — and were taken:
swift-log 1.15.1 → 1.16.1, swift-nio 2.103.0 → 2.104.0 (Xcode's pins synced). SwiftTerm v1.99 is a 250-commit rewrite onto Ghostty-based IO that does not build here —
the owner's decision (B-Q28), recommended: stay on 1.20 until v1.99 is released as stable and its manifest's
`unsafeFlags` are gone (SwiftPM refuses unsafe flags from a remote dependency anyway).

## B-R7 — licensing before distribution (research, not legal advice)

Primary sources in the research report of 2026-10-12 (kept in the session; summary here).

- **RDP.** No MS-RDP* document is under Microsoft's Open Specification Promise or Community Promise (only
  lower layers RDP uses: X.224, T.123–T.128, TLS, SPNEGO). Every MS-RDP* document grants copyright to implement
  and says Microsoft has patents that might cover implementations, licensed separately. Microsoft's patent map
  lists none against MS-RDPEDISP, -RDPECLIP, -RDPEDYC, -RDPELE or MS-NLMP, and Microsoft pledges not to assert
  unlisted patents. Listed, in force: MS-RDPEGFX (nine, to 2031–2035, one titled for AVC444's chroma), MS-RDPRFX,
  MS-CSSP (US 7913084, to 2029), MS-RDPEA (per-application volume, to 2030), the NSCodec/planar codecs, and two
  MS-RDPBCGR patents titled for multiple transports (not implemented). Microsoft's open-source developer pledge
  covers distributing an implementation without revenue, not end users. FreeRDP and its derivatives ship
  without a Microsoft licence; Microsoft licenses RDP commercially (aka.ms/celaiplicensing).
- **H.264, HEVC, AAC-ELD.** The app ships no codec; VideoToolbox and AudioToolbox decode. The pools license
  makers of products that contain decoders; none identified for an app using the system's. Apple's OS licences
  carry the AVC "personal and non-commercial use" notice to their users.
- **Also:** the Mac Screen Sharing extensions and High Performance mode are an undocumented protocol, ported from
  remotex (MIT) with captured fixtures — whether Apple's developer agreement (§2.6, reverse engineering) reaches a
  port is unknown. Export compliance: the app has its own SSH, CredSSP/NTLM and SRTP code
  (`ITSAppUsesNonExemptEncryption`, and possibly a year-end self-classification report).

**Questions for a lawyer:** (1) does the open-source pledge cover free App Store, TestFlight and Developer ID
distribution, and would donations change that; (2) ask Microsoft for a written covenant or zero-royalty licence
for a free client; (3) does RDPKit practise any listed in-force claim — AVC444 (US 9749646), the EGFX progressive
codec, RemoteFX, CredSSP, the audio patent, NSCodec/planar — and should any feature wait for expiry; (4) confirm
the expired ones; (5) anything in the codec pools for this app, and should business users be told of Apple's AVC
notice; (6) risk from shipping the reverse-engineered Screen Sharing protocol and fixtures; (7) export
classification; (8) should the README say no patent licence is implied.

## B-V4 — the two-device acceptance run (the owner, with two devices)

The product's central promise, never run end to end (D26, Stage 3.5). On the Mac and the iPhone, both on the
same build:
1. On the Mac, add a host with a Terminal using a synced SSH key; connect once and accept its host key.
2. On the iPhone, wait for the host to appear; connect — it must not ask about the host key again.
3. Delete that terminal on the Mac; on the iPhone the key must still be in Settings ▸ Keys.
4. Add a Terminal with a Secure Enclave key on the iPhone: it must not appear on the Mac; a database on the same
   host must.
5. Edit the same host's name on both devices, one of them offline; bring it online; both converge.
6. A service that requires authentication asks again on the second device.
7. Sign out of iCloud on one device: the library stays, and says sync is off.

## Still open in tier 2 (the owner's)

- ~~**B-T5**~~ — the full package run, screen unlocked, on the new pins (2026-10-12 evening): every target passes
  (about 2,690 Swift Testing tests) once the acknowledgements were regenerated for the two moved pins — the one
  test that failed was the one that says to; the owner's tmux sessions unchanged.
- **B-T8** rest — Instruments leak and hang runs, an assistive-technology pass (VoiceOver, Voice Control, Full
  Keyboard Access), IME, dictation and international layouts on devices.
- **B-R1–B-R6** — the Sparkle key, Developer ID, the first release run, the site, the scrub decision, the
  repository and the first push. **B-R7** — the lawyer's answers above. **B-R8, B-R9** after the first push.
- **B-Q28** — SwiftTerm v1.99 (recommendation above).
- **The unfolded Duo** — with Xcode 27.1 beta's Device Hub (pose buttons) or a real Duo from 10-23: the window gate's
  log line (`windows`, now with the width class), Split View with two Glass windows, folding with a table open, and
  dragging a file out of Files. The `Duo probe` simulator (iOS 27.1) is set up.
