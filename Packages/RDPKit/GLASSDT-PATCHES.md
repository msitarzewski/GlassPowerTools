# glassDT RDPKit patch provenance

Upstream: https://github.com/steelbrain/RDPKit

Baseline revision: `2032fdbc9a300e6b78065abbaf8ed1acca14f938` (RDPKit 0.3.1).
Prepared 2026-09-08. The upstream MIT license and Steelbrain copyright remain.
This fork is not Microsoft-certified and does not establish patent clearance.

## Security and integration

- Authorize the TLS certificate before CredSSP or Client Info credentials. Default Apple system trust verifies hostname. Explicit SHA-256 leaf pins bind to host and port. Hiding warnings never grants trust.
- TLS minimum and maximum are 1.2. An application can require NLA; allowing TLS fallback still advertises CredSSP and TLS. No silent downgrade when NLA is required.
- Cross-host redirection requires explicit opt-in. Same-host routing remains. Pins do not transfer endpoints.
- Expose negotiated Unicode, extra mouse-button and horizontal-wheel support; the adapter rejects unavailable operations.
- Reject incomplete auxiliary input/cursor/microphone DVCs by default with a CREATE failure. `allowsAuxiliaryInputChannels` retains upstream compatibility behavior only when explicitly enabled; glassDT leaves it disabled. Classic BCGR input/cursor handling remains active.
- Avoid scheduling input, clipboard or display writes on already inactive channels.
- Preserve actionable incomplete-credential errors through Foundation by conforming RDPCredentialValidationError to LocalizedError.

## Real-server interoperability

Live Ubuntu 24.04 xrdp 0.9.24 exposed and verified these fixes:

- Include INFO_MAXIMIZESHELL in the normal Client Info flags.
- Advance past STATUS_VALID_CLIENT after a New License Request. Ignore an undefined blob type for a zero-length licensing blob, as MS-RDPBCGR specifies.
- Propagate Client Info/licensing/activation/finalization parser failures instead of treating partial setup as success.
- Accept uncompressed Share Data PDUs whose compressedLength contains the PDU length, while preserving length, reserved-bit and compression validation.
- Render primary slow/fast-path bitmap updates before and independently of optional RDPGFX negotiation. Reuse the existing primary compositor and decoders; no fabricated RDPGFX capability set. Bound retained diagnostics and frame copies.
- Clip encoded bitmap padding to the inclusive destination rectangle. Retain bottom-up source orientation.
- On primary desktop reactivation, parse the new Bitmap capability dimensions, repeat Confirm Active and finalization, replace the input share, and reset the compositor. Preserve the authenticated transport and virtual channels.
- Propagate server RGB palettes to cached/new pointer images; validate supported mask storage depths.

No VideoToolbox or Metal codec was replaced. AVC420/AVC444 and upstream codec reconstruction remain. The facade currently publishes immutable BGRA copies; this is not zero-copy presentation.

## Encrypted server handoff

GNOME Remote Desktop50.2 can return LB_PASSWORD_IS_PK_ENCRYPTED after initial NLA login. The client now negotiates RDSTLS solely for that authenticated handoff, preserves the password blob as opaque bytes, validates the target certificate container and requires the presented TLS certificate to match it exactly as well as the configured trust policy. The original password is not reused. Initial required-NLA connections still require CredSSP; cross-host authorization remains unchanged.

Reuse: existing TLS transport, fixed-length framing and redirection parser. New RDSTLS.swift owns the previously missing authentication codec and bounded field validation. Capabilities must precede the authentication request; only a correctly typed successful authentication response advances to MCS. A synthetic TLS server verifies initial NLA→RDSTLS→actual frame, and malformed credential/certificate/result tests fail closed. The next explicitly authorized real Ubuntu/GNOME retry passed both certificate checks but failed capabilities validation before any frame. Inspection of the exact FreeRDP3.31.0 source identified its default v1|v2 SupportedVersions mask (3), which the original exact-v1 parser rejected.

Compatibility handling now accepts the documented v1-only value (1) and FreeRDP's known v1|v2 advertisement (3), while sending only the standard v1 password request. This is explicit receive-side compatibility with the server extension, not a claim that Microsoft's cited capabilities page specifies mask3 or that v2/FedAuth is implemented. v2-only/unknown masks, altered headers and wrong response types remain rejected; certificate and NLA policy are unchanged. The synthetic full-handoff server now advertises mask3. The final explicitly authorized Ubuntu26.04.1/GNOME50.2/FreeRDP3.31.0 test passes initial NLA, encrypted RDSTLS handoff, three decoded frames, source resizing1280×800→1408×800 and confirmed1280×800 restoration, followed by clean disconnect. The probe wrote no remote images or credentials and sent no remote commands; clipboard/audio were disabled. See the root validation evidence for the exact limits.

## Glass Power Tools (2026-09-13)

The fork moved into Glass Power Tools with its Sources, Tests and fixtures. `Examples/` was **not**
carried: it is upstream's sample application, not shipping code. Its one contribution to the product
— the Mac keyboard mapping — was already extracted with attribution into `MacKeyboardMapping.swift`,
and that attribution is preserved in the root `THIRD-PARTY-NOTICES.md`.

One manifest change: the two direct dependencies were `exact:` and are now `from:` at the same
versions. Glass Power Tools resolves one dependency graph for the whole application, and an `exact:`
pin inside a nested package freezes SwiftNIO for every other consumer of it — the SSH and database
stacks included. The engine has no API requirement for an exact version; 2.102.0 and 2.37.4 remain
what the application resolves and what the suite is tested against.

Two upstream documents are stale for a vendored copy and are left in place unedited as part of the
record: `README.md` still instructs consumers to depend on the upstream URL, and `AGENTS.md` states
upstream's `steelbrain/` branch-naming policy. Neither applies here.

## Reproducibility

Direct dependencies are pinned to the app-tested SwiftNIO 2.102.0 and NIOSSL 2.37.4. `Package.resolved` also records Atomics 1.3.1, Collections 1.6.0 and System 1.8.1.

The complete engine suite passed 1010 tests on macOS with Xcode 27.0 beta (27A5252f), SDK 27.0, including credential-error localization and RDSTLS handoff regressions. The repository integration harness exercises a generated-credential localhost-only Ubuntu 24.04/xrdp 0.9.24 fixture: unauthorized certificate rejection, authorized login, real bitmap frames, remote keyboard side effect, source resize from 1024x768 to 1280x800, bidirectional clipboard, and reconnect.

This does not prove compatibility with a real Windows host, RD Gateway, Kerberos, AVD, or device runtime/performance. See `CAPABILITY-LEDGER.md` for the actual production surface and limits. Platform builds use deployment target 26.0 with SDK 27.0, not an installed SDK 26 runtime.

## Relevant standards

- Client Info: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/732394f5-e2b5-4ac5-8a0a-35345386b0d1
- Empty license blobs: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/0a1c6079-af4d-4742-bb64-fecb8fa6e1a0
- Share Data header: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/4b5d4c0d-a657-41e9-9c69-d58632f46d31
- Bitmap data: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/84a3d4d2-5523-4e49-9a48-33952c559485
- Deactivation/reactivation: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/dfc234ce-481a-4674-9a5d-2a7bafb14432

- RDSTLS sequence: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/ef2979ac-5c21-4cdf-beda-1ded533ff4da
- RDSTLS password request: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/d0c153e4-2727-4f9f-a149-765b7dc52c31
- RDSTLS capabilities: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/35910151-abed-463b-aaf0-dd95010c2dc6
- RDSTLS authentication response: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/96327ab4-d43f-4803-9aff-392ce1fc2073
- Target certificate container: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/bf61c1fc-0818-40eb-a839-a4f2dede77c3
- Observed server implementation: https://github.com/GNOME/gnome-remote-desktop/blob/50.2/src/grd-session-rdp.c#L327

- FreeRDP3.31.0 version-mask advertisement and v1 password selection: https://github.com/FreeRDP/FreeRDP/blob/3.31.0/libfreerdp/core/rdstls.c

## Post-frame server redirection (2026-09-08)

The active RDPGFX receive loop now recognizes Server Redirection PDUs after a desktop frame and passes them through the same authenticated, certificate-bound handoff policy used during activation. LB_NOREDIRECT is ignored as informational in this loop. Replaced recursive connection hops with an iterative result loop to release the previous report/socket and avoid thread stack exhaustion at the existing maximum of two redirects. A new loopback fixture reproduces NLA→greeter frame→RDSTLS→desktop frame and rejects repeated redirects beyond the bound. Engine1011 tests pass. User-host logs demonstrate the second handoff requirement; actual post-login native desktop acceptance remains pending. No server configuration was changed.

## The whole certificate chain for trust (2026-09-27)

`ConnectionPreflight.swift`: the server's TLS certificate was evaluated with `SecTrust` from its leaf
alone, because NIOSSL's `peerCertificate` returns only the leaf. A certificate issued through an
intermediate authority therefore could not validate, and was reported as untrusted even when the
server sent the intermediate. NIOSSL now records the chain the server presents through a custom
verification callback that accepts it, and `SecTrust` evaluates that whole chain before any
application data or credential is sent, exactly as it evaluated the leaf before. Trust is still
decided by Security.framework and the host's certificate policy (system trust, or a host-and-port
pin), not by BoringSSL; `certificateVerification` is `.noHostnameVerification` rather than `.none`
only because NIOSSL invokes a custom callback solely when verification is on.

Validation: the package suite (1015 tests), including the mock server's TLS, CredSSP and RDSTLS
handshakes, passes. No test presents a multi-certificate chain: the result reports only the leaf's
digest, and system trust cannot be pointed at a test root. Not yet tried against a real server
whose certificate comes from an intermediate authority.
