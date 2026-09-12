# Stage 3 W-shell — a capability may borrow the host's SSH forward

Owner `/root`. 2026-09-12. Implements **D7** from the
[Stage 3 plan](2026-09-12_stage-3-database-plan.md). **Status: built and unit-tested; no live
tunnel proven yet.** Not committed at time of writing.

## The problem

glassdb's database record carries its own `sshHost`, `sshPort`, `sshUsername`, `sshAuthMethod`,
`sshKeyID`. In Power Tools the machine already owns its address and usually already has a Terminal
service with working credentials and established host-key trust. Duplicating all of that on the
database service would be a second place to get it wrong.

But capabilities must not import each other, and `GlassShell` must not pull the NIO/Citadel graph
in behind every consumer. So the shell brokers it.

## The contract

`Sources/GlassShell/GlassCapability.swift`:

```swift
public protocol GlassHostPortForward: AnyObject, Sendable {
    var localPort: Int { get }     // always a real bound port, never a request
    func close() async             // idempotent
}

public enum GlassPortForwardError: Error, LocalizedError {
    case unavailable               // no SSH service, or no capability owns .ssh
    case invalidPort(Int)
    case hostNotTrusted(name: String)
}
```

`GlassCapabilityHostAccess` gains `canForwardPorts` and
`forwardPort(toHost: String = "127.0.0.1", port: Int) async throws -> any GlassHostPortForward`.
Loopback is the default because the case this exists for is a database bound to the machine itself.

`GlassCapability` gains one requirement with a refusing default:

```swift
func openPortForward(host: HostProfile, toHost remoteHost: String,
                     port: Int) async throws -> any GlassHostPortForward
```

`GlassShellModel.hostAccess(for:)` resolves the provider once per access, so `canForwardPorts`
answers the same question the call will: it is non-nil only when the machine has an `.ssh` service
**and** a capability is registered for that kind. The closure is `@MainActor @Sendable` — the
protocol is main-actor isolated and `any GlassCapability` is not `Sendable`, so a plain `@Sendable`
closure cannot hold one. The requirement is therefore also main-actor isolated, and the doc
comment says plainly that an implementation must await its own transport actor rather than do
network work there.

## The terminal's implementation

`GlassTerminalCapability.openPortForward` finds the host's `.ssh` link, loads the saved
`ServerConfiguration` behind it, and takes **the same path a terminal connection takes**:
`prepareConnection` for credential material, `SSHConnection.makeRoute` for the route and jump
chain, `SSHTransport` with `PreparedCredentialResolver` and `SecretStoreHostTrustStore`, then
`forward(localPort: 0, …)` so the OS picks the port. The returned `GlassTerminalPortForward`
closes the tunnel and releases this borrower's claim, so a transport opened only for a tunnel goes
away with it while one shared with a live terminal session survives.

`PreparedCredentialResolver` changed from `private` to internal in `SSHConnection.swift`; nothing
else moved.

### Host-key trust is refused for now — **superseded by D14, approved 2026-09-12**

`trustDecider: nil`. A background tunnel is the wrong place to ask a user to compare a fingerprint,
and trusting one silently would be exactly the "silent security downgrade" the project rules
forbid. An untrusted machine returns `.hostNotTrusted`, whose message sends the user to connect the
Terminal service once and come back. **This is a real limitation, not a finished flow:** a user
whose host is not yet trusted cannot open a database tunnel without visiting the terminal first.
**Decided: it does.** D14 approves surfacing the terminal's own trust prompt from the database
connect flow, and resolving the fingerprint at setup time where possible, on the grounds that
opening a database is a foreground action and not a background tunnel. The refusal below stays as
the fallback for when no prompt can be shown. Wave 2 owns the change; what is described here is the
interim behaviour, not the shipping one.

## Verification

| Check | Result |
|---|---|
| `swift build` (whole package) | **passed** |
| `Tests/GlassShellTests/GlassShellPortForwardTests.swift` | **7 / 7 passed** |
| `swift test` (whole package) | **514 tests / 34 suites passed** (507 before this work) |

The seven cover: the target passing through unchanged to the lending capability; a host with no SSH
service; no capability registered for `.ssh`; a capability that never adopted the hook refusing
rather than pretending; port range rejected before the SSH capability is troubled; the lender's
error arriving intact with an actionable message; and close reaching the tunnel.

**Not proven:** a real forward to a real machine. `GlassTerminalCapability.openPortForward` has
never opened a socket — it is compiled, not exercised. The first honest test of it is wave 2's
database connection over a tunnel to the VM.

## Follow-ups

- D8: the local host must never be offered a forward (its services are already local). The provider
  resolves on "has an `.ssh` service", which the local host will have, so **W-local must exclude it**.
- A jump-host chain is carried because `makeRoute` carries it, but no test covers a forward through
  a jump host.
- D14: replace `trustDecider: nil` with the terminal's own decider routed through the connect flow.
