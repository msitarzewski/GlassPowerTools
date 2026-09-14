# glassDT protocol capability ledger

This records the production facade's implemented surface, not a claim of complete RDP implementation or Microsoft certification. Source baseline and patches are in `GLASSDT-PATCHES.md`.

| Area | Negotiation and implementation | Evidence / limit |
| --- | --- | --- |
| Transport/security | TCP, X.224/MCS, TLS 1.2, system trust or endpoint-bound SHA-256 pin, CredSSP/NTLM, optional required NLA | Real TLS xrdp login and pre-credential certificate rejection; CredSSP fixtures. No real Windows NLA host tested. TLS-fallback policy still prefers NLA when offered. |
| Primary graphics | Raw bitmap, interleaved RLE, RDP6 planar, palette; slow and fast path; surface-bits/frame-marker commands; NSCodec and RemoteFX | Real xrdp 0.9.24 desktop and clipping regression; upstream decoder fixtures. Immutable full-frame BGRA publication requires copies. |
| RDPGFX | Optional dynamic channel; automatic upstream capability profile offers versions through 10.7; existing H.264 AVC420/AVC444, ClearCodec, RemoteFX/CAVideo and progressive handling remain | Codec and protocol fixtures. AVC444 is RDP-specific reconstruction, not a generic single video layer. No real Windows AVC444/performance claim. Upstream VideoToolbox/Metal implementations preserved. |
| BCGR drawing orders | All 32 orderSupport bytes are zero | No unimplemented drawing order advertised. |
| BCGR caches | Bitmap cache capacities zero; offscreen support/capacities zero; glyph cache capacities/support zero; default brush support | No bitmap/glyph/offscreen order cache advertised. RDPGFX surface/cache logic is separate. |
| Pointer | Classic 24-bit Color Pointer and New Pointer; 32-entry cache; 96/384-pixel large pointers; mask rows validated/aligned | UI decoder handles 1/4/8/15/16/24/32-bit formats, indexed server palettes, bottom-up masks, alpha and exact AND/XOR composition. Missing palette is an explicit malformed/unsupported-data error. |
| Input | Scancodes, Unicode when negotiated, slow/fast input, mouse buttons, wheel/horizontal wheel when negotiated, lock-key synchronization | Real remote command side effect; ordering/release/focus tests; app native keyboard paths compile. Physical iPad/visionOS keyboard validation remains. |
| Display Control | One primary monitor, MS-RDPEDISP caps-driven resize; dimensions 200–8192, even width, negotiated area limit | Real 1024x768→1280x800 source resize. Legacy reactivation repeats capability negotiation/finalization without reauth. GFX resize retains upstream Reset Graphics handling. Multi-monitor UI is not exposed. |
| Clipboard | Optional Unicode text, disabled by default | Bidirectional real xrdp clipboard. File clipboard APIs exist upstream but are not exposed by glassDT. |
| Audio | Optional server PCM16 playback, disabled by default; bounded native AVAudioEngine queue | Parser/mock and playback-buffer tests; no physical audible-output test. Microphone capture is not exposed. |
| Auxiliary DVCs | Unsupported enhanced/core input, mouse cursor, microphone channels receive CREATE failure by default | Regression verifies the server can continue with graphics. Upstream partial compatibility negotiation is opt-in only and unused by glassDT. |
| Redirection | Same-host routing and encrypted RDSTLS handoff during activation or live GFX; iterative bounded hops; cross-host opt-in only, endpoint pins remain bound; target certificate must match authenticated redirection | Complete synthetic NLA→RDSTLS→desktop and malformed/failure regressions pass. After correcting FreeRDP3.31.0 v1|v2 advertisement handling, the authorized Ubuntu26.04.1/GNOME50.2 test passes NLA→RDSTLS→frames, source resize1280×800→1408×800→1280×800 restoration and clean disconnect. No cross-host automatic trust. Synthetic post-greeter second handoff and redirect-loop refusal pass; the newly reported actual post-login desktop is not yet reverified. |

Not implemented/exposed: RD Gateway, Kerberos, legacy Standard RDP Security/RC4, UDP multitransport, AVD/broker login, RemoteApp, drive/printer/smart-card/USB redirection, camera/microphone capture, multi-monitor UI. MIT licensing does not itself grant patent rights or certify protocol compliance.

The complete engine suite and synthetic-server tests are regression evidence. The Ubuntu fixture proves the specified TLS/bitmap/display/clipboard/input path only. Microsoft Windows Protocol Test Suites and a real Windows/Windows Server matrix remain separate compatibility evidence, not claimed completed.

The two DynamicVirtualChannel width-code precondition failures were traced: encoder callers obtain only 0/1/2 from the width selector; network callers first pass throwing readers that reject all other codes. Malformed remote codes do not reach those assertions.
