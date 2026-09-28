# Live desktop probes

A separate Swift package, never part of `swift test`. Its probes consume the remote desktop
transports and engines exactly as the app does, against real servers. Build it from this
directory, always with `--disable-keychain` (SwiftPM can otherwise wait on a Keychain prompt):

```sh
cd Tests/LiveDesktop
swift build --disable-keychain
```

| Probe | Against | Proves |
|---|---|---|
| `GlassWindowsRDPProbe` | a real RDP host you name | negotiation and a first real frame |
| `GlassVNCProbe` | a real VNC host you name | negotiation and a first real frame |
| `GlassRDPFunctionalProbe` | the disposable xrdp fixture (`Docker/xrdp`) | the functional checks below |
| `GlassVNCFunctionalProbe` | the disposable TigerVNC fixture (`Docker/tigervnc`) | the functional checks below |

The first two read the password from a file (`<host> <port> <username> <password-file>`) so it
never appears on a command line. The functional harnesses were moved from glassDT's
`Tests/Integration` and `Tests/IntegrationVNC`.

## Functional harnesses (Docker)

Requirements: macOS 26+, Xcode/Swift, and a running Docker engine. Each script builds the probe,
builds the fixture image, starts one container, runs the probe, and removes the container on exit:

```sh
Tests/LiveDesktop/Docker/xrdp/run.sh     [evidence-directory]
Tests/LiveDesktop/Docker/tigervnc/run.sh [evidence-directory]
```

Without an argument, evidence goes to a new `mktemp` directory under `$TMPDIR`, outside the
repository; the script prints its path. Keep evidence out of the tree. It contains
`results.jsonl` (one JSON line per check), `server-versions.txt`, the image and probe build logs,
and frame images decoded from the protocol (not screenshots of the app). The script exits nonzero
if any check fails.

Options: `DOCKER_BIN` selects the Docker binary. `GLASS_SWIFT_SCRATCH` sets a SwiftPM scratch
directory; otherwise the package's own `.build` is reused, so later runs skip most of the build.

**Isolation.** Both images start from the official `ubuntu:24.04` image and Ubuntu's packages, and
run a desktop for a disposable user, `glassfixture`. The script generates a random password
into a private temporary directory, bind-mounts that one file read-only, publishes the server on
a random port bound to `127.0.0.1` only, and limits CPU, memory and PIDs. No privileged mode, no
real accounts, no real credentials. The exit trap removes the container and the password file.
The local images `glass-xrdp-fixture:local` and `glass-vnc-fixture:local` stay cached; remove
them with `docker image rm` when done.

### xrdp (`Docker/xrdp`)

xrdp and xorgxrdp with Xorg, Openbox, an xterm and xclip; TLS security layer with a one-day
self-signed certificate generated when the container starts. `GlassRDPFunctionalProbe` checks,
in order:

- `certificate_rejection`: an unpinned certificate ends the session before any frame or input.
- `authenticated_desktop`: with that certificate pinned, a real desktop frame arrives
  (`first-desktop.png`).
- `remote_keyboard_input`: a typed shell command writes a unique marker into the container,
  read back with `docker exec` (`input-desktop.png`).
- `source_resize`: the server resizes its desktop to 1280 × 800 (`resized-desktop.png`).
- `clipboard_bidirectional`: client text appears in the X clipboard, and X clipboard text reaches
  the client.
- `reconnect`: a new session after disconnect delivers frames.

Limits: xrdp 0.9.24 has no CredSSP path, so this is TLS-only server authentication. It does not
test Windows NLA, Gateway, Kerberos, audio/devices or performance.

### TigerVNC (`Docker/tigervnc`)

Xtigervnc with VNC Authentication, a 1024 × 640 24-bit desktop accepting SetDesktopSize, Openbox,
an xterm, xclip and xdotool. `GlassVNCFunctionalProbe` (VNCKit directly) records the handshake,
negotiated version, security type, first frame and server events, then, because the script
passes the container name, asserts inside the fixture:

- `pointer_position`: the X server's pointer is where the client moved it (`xdotool`).
- `keyboard_input`: a typed shell command writes a unique marker file.
- `cut_text_client_to_server`: client cut text becomes the X clipboard.
- `cut_text_server_to_client`: X clipboard text arrives as ServerCutText.
- `set_desktop_size`: the framebuffer becomes the requested 800 × 500.

It writes `final-frame.ppm` (`sips -s format png final-frame.ppm --out final-frame.png` converts
it). Without the container argument the same probe only reports, so it can be pointed at any VNC
server: `GlassVNCFunctionalProbe <host> <port> <username-or-empty> <evidence-dir> <seconds> < password-file`.
This is standard RFB interoperability only. Apple Remote Desktop authentication needs a real Mac.
