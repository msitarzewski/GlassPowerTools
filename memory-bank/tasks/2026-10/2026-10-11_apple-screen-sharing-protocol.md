# Apple's Screen Sharing protocol (RFB 003.889), then High Performance

**Owner request (2026-10-11):** "Why aren't we speaking Apple's version now?" … "is this why every other solution
has a computer side agent? I really, really don't want to force that on people." Then: "we're going to need apple's
version I think." Authorization: standing "go with your recommendations, commit each piece as it lands".

## Why
- Our VNCKit answers a Mac's `RFB 003.889` with 3.8 (`RFBProtocolVersion.negotiated`), as glassDT did.
- **Security finding:** after type-30 sign-in our sessions are cleartext — a Mac encrypts only when the viewer asks
  (`SetEncryption`), and 3.8 never asks. Keystrokes cross the LAN readable (Tailscale's own encryption covers remote).
- High Performance (HEVC + AAC-ELD media stream, one or two virtual displays at the viewer's size) is the agentless
  answer to quality, two independent displays and sound; it requires 003.889 + the record layer.
- The Mac's pointer: arming (`AutoFrameBufferUpdate`, dbaec46) is what keeps cursor *shapes* coming per remotex;
  remotex advertises CursorPos but ignores it, so a pointer moved at the Mac itself may never be reported (Sill, an
  agent, reads it directly).

## Sources
- remotex (MIT, Andrew Chen) `docs/apple-vnc-889.md` (copy in the scratchpad) and `src/vnc.rs` (`apple_preface`,
  `await_rekey`, `read_server_init`, `Buttons`), `src/vnc_record.rs`, `src/vnc_apple.rs`. Port with attribution in
  THIRD-PARTY-NOTICES if code is translated closely.
- Sill (Apache 2.0) — an agent (ScreenCaptureKit + HEVC + TLS, private virtual-display API); not this path.

## Step 1 — 003.889 Standard mode (behind `VNCConfiguration.appleProtocol`, probe `--apple`)
1. Version `RFB 003.889\n`; type 30 as now, keeping `MD5(shared)` as the wrap key; SecurityResult refusal is the word
   alone (no reason string).
2. ClientInit `0x81`; enhanced ServerInit name field = `u16 0, u32 flags, 16-byte client-command bitmap, name`.
3. Cleartext prelude, back to back: ViewerInfo (66 bytes), SetMode(1), SetEncryption(1) `12 00 0001 0001 0001
   00000001`, SetEncryption(2) `12 00 0002 0001 0000`; then read cleartext until the rekey rectangle (encoding
   0x44f, 36 bytes: u32 generation, key and IV each one AES-128-ECB block under the wrap key), stepping over Bell
   and MiscStatus.
4. Record layer both ways from then on: `u16 len || AES-128-CBC(u16 body_len || body || zero filler || SHA1(u32 seq
   || plaintext))`, one CBC chain and one sequence counter per direction for the whole session; **one client message
   per record** (two in one record: the Mac drops the second); records written in the order framed.
5. Then SetPixelFormat, SetEncodings, arming after each layout (dbaec46). Pointer mask on 003.889: bit 2 = right,
   bit 3 = middle (swap RFB's).
6. Verify with the owner's probe run; then make it the default for Macs, keep 3.8 for others.

## Step 2 — High Performance
SetDisplayConfiguration virtual displays, media stream (SRTP, HEVC via VideoToolbox, AAC-ELD), per remotex
`vnc_apple_media.rs`. Requires an Apple silicon Mac whose ServerInit lists 0x1d.

## State
- 2026-10-11 PLAN → BUILD (step 1).
