# A database reached through another machine (D45, 2026-10-05)

- **Authorization:** owner chose "Its own machine (Recommended)" in the design question.
- **Gap found:** `DatabaseSessionManager` always forwarded to `127.0.0.1` through the database's
  own host's Terminal service; a database on a private address behind an app server had no route.

## Built
- Shell: `GlassTunnelChoice`; `GlassCapabilityHostAccess.tunnelChoices`, `forwardPort(through:…)`,
  `resolveHostTrust(through:)`; `GlassShellModel.tunnelChoices(excluding:)` (non-local machines
  with an SSH service on their address-bearing record, `sshMember`), `tunnelMember(for:)`;
  `GlassPortForwardError.tunnelMachineGone`.
- Database: `tunnelServiceID` (saved only with `usesHostTunnel`); draft `Route` (direct / this
  machine / through X) and a **Connect** picker that replaces the switch when choices exist;
  trust settled against the chosen machine; `GlassDatabaseCapability.forwardProvider(for:hostAccess:)`
  sends the forward to `config.host` through the chosen service; failure text names the cause;
  `runtime.tunnelAccess` so the Add Host sheet offers choices too.
- Help: "Reach a database through another machine".

## Validation
- Unit: shell (choices exclude self, local and terminal-less machines; forward reaches the right
  machine and address; a gone service is refused), database (routes, persistence and old records,
  connect goes through the chosen machine). Shell 204, database 305 pass.
- Live (scratch): `tunnelReachesANetworkAddressNotOnlyLoopback` — through the VM to its own network
  address, sshd's banner comes back. Not run against the owner's real servers (by rule).
- Not seen on screen yet: the picker in the setup sheet.

## Follow-up the same day: the address, where the owner looked for it
- The owner added the database to the app server itself and chose "Through this machine's
  Terminal" — the natural shape — and found nowhere to give the private IP (the edit-service sheet
  shows no Machine section). Added `tunnelTargetHost`: with that route, a **Database address** row
  (blank = the machine itself, loopback). "Through another machine" stays for a database server kept
  as its own machine; its caption now names the address it will use, or points to Machine › Address
  (`GlassServiceDraft.hostAddressDidChange`, a requirement with a no-op default).
- Tests: the address reaches the forward, blank means loopback, saved only for this route.
