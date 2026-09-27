# Encryption and the SSH tunnel

This page covers how a MySQL or PostgreSQL connection is protected: TLS with one of three verification modes, the warning for an unencrypted connection, and reaching a database through the host's SSH service. SQLite files are local and use neither.

## Turn on encryption

1. Edit the database service and open **Advanced**.
2. Turn on **Encrypt the database connection**.
3. Choose a **Verification** mode. The sheet explains each one below the picker.
4. Choose **Save**.

TLS 1.2 or later is required. If the server fails the chosen mode's checks, the connection fails; the app never retries with a weaker mode.

### Verification modes

| Mode | What is checked |
|---|---|
| **Verify with the system's certificate authorities** | The certificate must be issued by an authority this device already trusts and must name this machine. |
| **Verify with a certificate I supply** | The certificate must be issued by the authority in the file you choose and must name this machine. Authorities this device would otherwise trust are not accepted. |
| **Verify with a certificate I supply, without checking the server's name** | The certificate must be issued by the authority in the file you choose. The name is not checked. |

> [!WARNING]
> The third mode lets any machine holding a certificate from the same authority take the connection unnoticed. Use it only when the server's certificate carries no usable name, as with a default MySQL or PostgreSQL install.

The name checked is always the host's address, for example `db.example.com`, even when the connection goes through the SSH tunnel.

### Supply a certificate

The two modes that use your own certificate require one before you can save.

1. Choose **Choose Certificate…** and pick the authority's certificate. PEM and DER files are accepted, and a PEM file may contain a chain.
2. Check the summary shown under the file name. It lists each certificate's SHA-256 fingerprint in the same colon-separated form that `openssl x509 -fingerprint -sha256` prints, so you can compare them character for character, and it says if a certificate has expired.
3. Choose **Save**.

A file that is not a certificate is rejected when you choose it. To replace a certificate, choose **Choose Different Certificate…**.

## The unencrypted warning

When **Encrypt the database connection** is off and the tunnel is off, the sheet shows an orange warning: the password and every query and result cross the network readable unless the database is on this device.

In the workspace's **Overview**, **Connection Details** has a **Transport** row that says how the connection travels:

- **Direct** or **Host tunnel**, the route.
- **not encrypted**, added for a direct connection without TLS to an address other than `127.0.0.1`, `::1` or `localhost`.
- **TLS:** followed by what is verified, for example **system authorities, server name checked**.

## Reach a database through the host's SSH service

Most database servers accept connections only from their own machine. The tunnel reaches one through the host's Terminal service, using that service's credential and host-key trust.

1. Make sure the host has a Terminal service.
2. Edit the database service and open **Advanced**.
3. Turn on **Reach it through this machine's Terminal service**.
4. Set **Port** to the port the database listens on, on that machine.
5. Choose **Save**.

The forward goes to `127.0.0.1` at that port, as the host's machine sees it. A database on another machine belongs to that machine's host.

When you turn the tunnel on for a saved host, the app checks the machine's SSH host key right away. The row then reports one of these:

- **This machine's SSH host key is trusted.**
- The host key was not trusted, so the tunnel will not open, and you are asked again the first time you connect.
- The host key is checked the first time you connect, where you can review its fingerprint.

If the host has no Terminal service, the row says so. You can still save, but connecting fails until you add one or turn the tunnel off.

While a tunnelled session is open, **Connection Details** shows a **Tunnel** row with the local port in use.

> [!TIP]
> If a direct connection fails because the server did not answer, the message suggests turning the tunnel on. If a tunnelled connection fails the same way, check that the database is running and listening on the port you entered.
