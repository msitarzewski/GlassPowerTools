# The forward dropped a server-first protocol's opening bytes

Owner `/root`. 2026-09-12. **Fixed and confirmed by the user in the running app.** A real defect in
`GlassSSHTransport` that every test passed, including the live ones.

## The symptom

`MySQL error: Server error: Got timeout reading communication packets`, at almost exactly ten
seconds, connecting a database through the host's SSH forward (D7). PostgreSQL over the same
forward never reproduced it. It appeared twice in a test run, then stopped; it reappeared for the
user against a different machine (Tailscale host, MySQL bound to loopback) in build 0.3.62.

## The cause

`SSHTransport.openDirectChannel` opened the Citadel direct-TCP/IP channel and the forwarding code
then wrapped it in a `NIOAsyncChannel` **after the open returned**
(`SSHTunnelFactory.pipe` → `wrap(_:)`).

MySQL's server speaks first: it sends its greeting the instant the forwarded connection is
accepted. When the SSH server delivers that greeting in the same read as the channel-open
confirmation, it arrives at a pipeline with nothing to consume it and is discarded at the tail. The
client then waits for a handshake it will never see and the server gives up at its own
`connect_timeout` — which is exactly `10`.

PostgreSQL is client-first, so the wrap is always in place before any byte arrives. That asymmetry
is the whole reason this looked like flakiness.

## The fix

`SSHTransport.openDirectAsyncChannel` creates the `NIOAsyncChannel` **inside Citadel's channel
initializer**, before the channel is ever active, so no inbound byte can arrive unclaimed.
`SSHDirectChannelProvider` gained the method with a default that wraps afterwards (correct only for
client-first protocols), and both forwarding paths — local `-L` and SOCKS5 — take the pre-wrapped
channel.

## Why it survived everything

- **Unit tests:** never open a socket.
- **The live tunnel test:** passes either way. The VM's MySQL listens on `0.0.0.0`, and whether the
  greeting is dropped depends on packet coalescing, so a green run proves nothing about this.
- **Comparing against the shipping app:** `openDirectChannel` is byte-for-byte identical to
  glas.sh's (`../glas.sh/glas.sh/Models.swift:2466`), and both vendored Citadel copies of
  `DirectTCPIP+Client.swift` are the same file. That identity felt like proof of correctness. It
  was the opposite: **glas.sh has the same latent bug** and simply forwards to MySQL rarely.

It took a user, a real Tailscale host and a loopback-only MySQL.

## Three wrong turns, recorded because the reasoning is the lesson

1. **"Cold `caching_sha2_password` auth fails over our forward."** Refuted by a controlled test:
   W-vm flushed the auth cache, stood off the server, and the first connection afterwards passed in
   0.072s.
2. **"The tunnel is a different cache entry from the direct path."** Stated confidently and
   **false** — MySQL keys that cache by matched account, and only `gpt_test@%` exists. It was
   propagated to a worker, who wrote it into a task note as grounds for withdrawing a sound result.
   Project rule 19 came from this.
3. **"Contention between concurrent test runs."** Not supported by the server's own counters:
   `Max_used_connections` 4 against a limit of 151, every `Connection_errors_*` zero, sshd clean.

**The fourth turn was the right diagnosis, abandoned for the wrong reason.** Early on, autoRead was
disabled on the hunch that a server-first protocol was losing its greeting. The test **hung**, and
the hang was read as "theory refuted" — when a hang is equally consistent with *right diagnosis,
wrong remedy*: nothing was issuing reads. The correct remedy was to wrap in the initializer, not to
turn reads off after the fact.

## Verification

| Check | Result |
|---|---|
| `LiveTunnelIntegrationTests`, five consecutive runs | **5/5 passed** (it was intermittent, so one run proves little) |
| Whole package | **597 tests / 45 suites** at the time of the fix |
| The user's own machine, MySQL on a Tailscale host bound to loopback | **connects** — the only verification that settles it |

## Left open

`SSHTunnelFactory.wrap(_:)`'s after-the-fact wrapping survives as the protocol's default
implementation. It is correct for client-first protocols and documented as such, but any future
provider that forwards a server-first protocol must override `openDirectAsyncChannel`.
