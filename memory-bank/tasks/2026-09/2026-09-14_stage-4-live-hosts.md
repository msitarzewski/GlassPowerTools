# Stage 4 — live hosts, and the first real Windows RDP session

Owner: coordinating agent. 2026-09-14. **Status: measured. Every result below is a real execution.**

Authorized by the user: *"You can set up screen sharing on the scratch parallels vm and on windows
11 to test."*

## The headline: RDP against real Windows, for the first time

`Packages/RDPKit/CAPABILITY-LEDGER.md` said, of transport and security: *"No real Windows NLA host
tested."* That has been true since the engine was written. It is no longer true.

**Host:** Parallels VM "Windows 11", **Windows 11 Pro Insider Preview, build 10.0.29648**, at
`192.0.2.3:3389`. RDP was enabled for this test with `fDenyTSConnections=0`,
`UserAuthentication=1` (NLA required) and the Remote Desktop firewall group enabled. A dedicated
local account `gptrdp` was created and added to **Remote Desktop Users**; its password was generated
randomly, written to a file with mode 600, and never placed on a command line, in a process list or
in this note.

**Result, `GlassWindowsRDPProbe`, `requiresNLA: true`:**

```
certificate : systemTrusted=false accepted=true sha256=c0:0f:af:68:…:db:93
connected   : true
first frame : 1280x800  bytesPerRow=5120  after 0.84s
pixels      : 4,096,000 bytes, nonZero=true, hardwareAccel=true
frames seen : 3
RESULT: PASS
```

**The refusal came first, and that is the more important result.** Without a pin the probe reported:

```
FAILED after 5.2s: TLS failed: server certificate identity was not authorized
```

Windows issues a self-signed RDP certificate, so `SecTrustEvaluateWithError` fails and
`ConnectionPreflight.swift:2877` throws **before any credential is sent** — the invariant stated at
`CertificateTrust.swift:3`, now demonstrated against a real Windows host rather than a synthetic
one. Supplying the leaf SHA-256 as `approvedCertificateSHA256` is the real user flow and completes
the connection.

**Two observations worth carrying into W2/W3, neither a defect:**

- **`displayCaps: none reported`.** Windows did not advertise MS-RDPEDISP here, where the Ubuntu
  fixture does. The session UI already disables every resize control while `capabilities == nil`, so
  the behaviour is correct — but "resize works" must not be claimed for Windows on this evidence.
- `hardwareAccel=true` is what the decoder reports, not a measurement. **No latency, FPS or energy
  figure is claimed.** First frame at 0.84s is a single observation on a local VM.

## VNC against TigerVNC 1.15.0

**Host:** Parallels VM "Scratch", **Ubuntu 26.04.1 LTS**, at `192.0.2.6:5902`.
`Xtigervnc` **1.15.0+dfsg-2build1** — newer than the 1.13.1 glassDT proved — run as a transient
systemd unit `gptvnc`, 1024x640, `SecurityTypes VncAuth`. The password was generated locally and
fed to `vncpasswd` **over stdin**, so it never appeared in a command line.

```
connected   : true
displayCaps : maximumMonitors=1  maximumArea=33554432
first frame : 1024x640  bytesPerRow=4096  after 0.22s
pixels      : 2,621,440 bytes, nonZero=true
RESULT: PASS
```

`maximumMonitors=1` is the asymmetry the plan already records: VNC publishes capabilities only on
ExtendedDesktopSize and never offers multi-monitor. The merged UI must keep gating on it.

## Apple Screen Sharing — the exchange, reproduced on the moved code

**Host:** this Mac's own Screen Sharing service on `127.0.0.1:5900`, its settings untouched.

Two probes, both with a deliberately invalid credential, and **no real account was used**:

| Probe | Result |
|---|---|
| Empty user name | `Authentication or authorization failure` after 2.1s |
| Nonexistent account `gpt-no-such-account` | `Authentication or authorization failure` after 32.4s |

Reaching that message means the client negotiated the Apple Remote Desktop security type, completed
the Diffie-Hellman exchange and submitted an encrypted credential block that the server parsed and
rejected on the account, not on the format. **This reproduces glassDT's 2026-09-09 result on the
moved code.**

The 32.4s on the second probe is server-side throttling after repeated failures, not client latency.

What these two probes do **not** show is a completed session — they were never meant to, having no
valid account. That is the next section, and it is now closed. To run the probe against a real
account, the password is passed as a **file path** so the secret never reaches a command line, a
process list or this repository:

```
cd Tests/LiveDesktop && swift build
read -rs -p "Password: " P; printf '%s' "$P" > /tmp/msp.pw; chmod 600 /tmp/msp.pw; unset P; echo
./.build/debug/GlassVNCProbe <host> 5900 "$(id -un)" /tmp/msp.pw ; rm -f /tmp/msp.pw
```

## Closed: a signed-in Apple Screen Sharing session works

**2026-09-14, observed by the user in the running glassDT app and shown to the coordinator in a
screenshot.** A saved desktop named `juliet`, reached over Tailscale:

| Field | Value |
|---|---|
| Protocol | **Screen Sharing (VNC)** |
| Port | 5900 |
| Account | a real Mac account |
| Last connected | **28 sec** |

The user's words: *"Just verified port 5900, mac user name and password."*

**This is the result that was never obtained.** `Documentation/Verification/VNC/README.md` recorded
only that the Apple Remote Desktop exchange was *well formed*, with a deliberately invalid account,
and listed "a completed Apple Screen Sharing session with a real Mac account" under **Not verified**.
It is verified now.

**What it settles:** security type 30 — the only Apple type `RFBSecurityType` implements
(`RFBModels.swift:47-51`) — completes a signed-in session against current macOS. So **Stage 4.5
item 2, Apple's security type 35, is not required**, and the largest unknown in either stage is
retired. Screen sharing is a move, not new protocol work.

**The limit on this evidence, stated plainly:** it is a user observation of the *source* app, not a
captured probe run against the moved code, and it is one host. The moved code is proven only as far
as the ARD exchange above. A probe run against a real account remains the way to prove the merged
build, and W3 should do it once a desktop can be created in the shell.

## A fourth server is available but untouched

`192.0.2.3:5900` on the Windows VM is **TightVNC Server** (`tvnserver`), already installed. Our
client reached it and reported *"This server needs a VNC password"* — the typed, actionable error
from `VNCClient.swift:132-146`, which is itself a correct result. Its password was **not** changed,
because the user may be relying on it. Testing against it needs only that password.

## What was added to the repository

`Tests/LiveDesktop/` — a separate package, deliberately not part of `swift test`, holding
`GlassWindowsRDPProbe` and `GlassVNCProbe`. Both read the password from a file, print what was
negotiated, and never print the secret.

## Credentials

None are recorded here or anywhere in the repository. The generated passwords live only in this
session's scratchpad at mode 600 and die with it. The `gptrdp` Windows account and the `gptvnc`
systemd unit are test fixtures on the user's own VMs and can be removed with
`net user gptrdp /delete` and `systemctl stop gptvnc` respectively.

---

## 2026-09-15 — re-proven on the merged build, with the VMs up again

The user reopened the Parallels VMs. Everything below is a real execution against a real host, run
from this checkout's `Tests/LiveDesktop` probes.

### VNC against TigerVNC 1.15.0 — PASS

`Xtigervnc` **1.15.0+dfsg-2build1** on Ubuntu 26.04.1 LTS, `192.0.2.6:5902`. The transient
`gptvnc` unit from September was gone (it is transient by design), so it was recreated the same way:
password generated locally, fed to `vncpasswd` **over stdin**, written to `~/.vnc/passwd` at mode
600. It never appeared in a command line, a process list or this repository.

```
connected     : true
displayCaps   : maximumMonitors=1  maximumArea=33554432
first frame   : 1024x640  bytesPerRow=4096  after 0.21s
pixels        : 2,621,440 bytes, nonZero=true
RESULT: PASS
```

`maximumMonitors=1` again: VNC publishes capabilities only on ExtendedDesktopSize and never offers
multi-monitor. The UI must keep gating on it.

### RDP certificate refusal against real Windows — reproduces, same certificate

`192.0.2.3:3389`, with a deliberately nonexistent account and a junk password file:

```
FAILED after 5.2s: TLS failed: server certificate identity was not authorized
  certificate: systemTrusted=false sha256=c0:0f:af:68:…:db:93
```

Two things worth having:

- **It failed at the certificate, not at authentication.** The credential was never sent, which is
  the invariant `CertificateTrust.swift:3` states and `ConnectionPreflight.swift` enforces.
- **The leaf SHA-256 is byte-identical to the one recorded on 2026-09-14** — same host, same
  self-signed certificate, so this is a genuine continuity check rather than a fresh coincidence.

### Windows TightVNC — the typed error still arrives

`192.0.2.3:5900`, empty password: *"This server needs a VNC password."* — the typed, actionable
error from `VNCClient.swift:132-146` rather than a generic failure. Its password was **not** changed;
the user may be relying on it.

### What is still not proven, and why

**A signed-in RDP session on the merged code.** The `gptrdp` account created in September had a
randomly generated password that lived only in that session's scratchpad and died with it, and
Windows has no SSH here, so it cannot be re-provisioned from this side. Frames, input, source resize
and clean disconnect over RDP therefore remain **unverified on this build** — the headline of Stage 4
W3. It needs an account on the Windows VM, which is the user's to supply.

**No RDP server exists on the Ubuntu VM** (no `xrdp`, `gnome-remote-desktop` inactive and its daemon
absent; only 5902 listens), so the non-Windows RDP path — GNOME's RDSTLS handoff — cannot be
exercised here either without installing one.

### Left running

`gptvnc` is active on the Ubuntu VM and will survive until the VM restarts.
`systemctl --user stop gptvnc` on `192.0.2.6` stops it.
