# RDP: in-session bandwidth measurements answered with real bytes (2026-10-05)

- **Context:** owed live check — RDP autodetect against Windows. Owner started the Windows 11 VM.
- **Test account:** the existing local test account's password was reset to a fresh random value,
  generated into a private file on the Mac and passed to the VM on stdin (never printed). The probe
  reads it from that file. The certificate is pinned per run, as the app's own flow does.
- **Found:** nothing logged whether autodetect ran. With a log line per exchange and the session
  held for 30 s, Windows 11 sent 12 in-session measurements (Bandwidth Measure Start 0x0014 →
  session traffic → Post-connect Stop 0x0429) and every result said **0 bytes**: the meter counted
  only Bandwidth Measure Payload PDUs, which the server sends during the connection and not in the
  session. MS-RDPBCGR 2.2.14.2.2: byteCount is "the number of bytes received between the Bandwidth
  Measure Start and Stop messages". IronRDP fixed the same gap (Devolutions/IronRDP#2012).
- **Fixed:** `RDPAutoDetectMeter.countsAllTraffic` + `noteReceived(byteCount:)`; the session loop
  reports every received packet. The connect-time meter is unchanged.
- **Validated:** unit test (traffic between start and stop counted; before start not; connect-time
  still payload-only). Live: 10 measurements in 30 s reported 2,476–4,865 bytes (1–124 ms) instead
  of 0. The probe gained `GPT_RDP_HOLD=<seconds>` to stay connected after the first frame.
- RDPKit full suite: 1,025 tests; the two known MockKRDP early-authorization flakes failed under the
  full parallel run, pass alone with and without this change.
