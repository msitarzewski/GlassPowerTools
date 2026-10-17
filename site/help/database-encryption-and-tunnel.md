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
2. Check the summary shown under the file name. It says how many certificates the file holds and gives the first one's SHA-256 fingerprint, in the same colon-separated form that `openssl x509 -fingerprint -sha256` prints, so you can compare them character for character. It warns when a certificate is outside its validity window, expired or not yet valid, because the server will then not be accepted.
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
3. Turn on **Reach it through this machine's Terminal service**. When other machines in your library have a Terminal service, this is a **Connect** menu instead: choose **Through this machine's Terminal**.
4. Set **Port** to the port the database listens on, on that machine.
5. Choose **Save**.

The forward goes to `127.0.0.1` at that port, as the host's machine sees it.

If the database is on another server that only this machine can reach — a production database behind an app server — enter that server's address in **Database address**, which appears once the connection goes through this machine's Terminal, as this machine sees it (for example `192.0.2.12`). The machine's Terminal service connects on to it for you. Leave it blank, as its prompt **This machine** says, for a database on the machine itself.

## Reach a database through another machine

The database above was added to the machine that reaches it. If you'd rather keep the database server as its own machine in the library, connect through the other machine instead:

1. Add the database server as its own host, with its private address (for example `192.0.2.12`).
2. Add the database service to it, and open **Advanced**.
3. In **Connect**, choose **Through** and the machine that can reach it — the app server. That machine needs a Terminal service. The sheet then says where the connection goes, for example **Connects to bravo over SSH, then to 192.0.2.12:5432 from there.** If the database's host has no address yet, it asks for its private address under **Machine** first.
4. Choose **Save**.

When you connect, the app signs in to the app server with its Terminal service's credential and host-key trust, then opens a tunnel from there to the database's address and port. The database server needs no SSH of its own. If that machine, or its Terminal service, is later removed from the library, the database says so and asks you to choose again.

When you turn the tunnel on for a saved host, the app checks the machine's SSH host key right away. The row then reports one of these:

- **This machine's SSH host key is trusted.**
- The host key was not trusted, so the tunnel will not open, and you are asked again the first time you connect.
- The host key is checked the first time you connect, where you can review its fingerprint.

If the host has no Terminal service, the row says so. You can still save, but connecting fails until you add one or turn the tunnel off.

While a tunnelled session is open, **Connection Details** shows a **Tunnel** row with the local port in use.

> [!TIP]
> If a direct connection fails because the server did not answer, the message suggests turning the tunnel on. For a private network address or a `.local` name, it may instead say that Glass Power Tools may not be allowed on the local network: allow it in **Settings** (**System Settings** on Mac) ▸ **Privacy & Security** ▸ **Local Network**. A name that can't be found says so; check the host's address. If a tunnelled connection fails because the server did not answer, check that the database is running and listening on the port you entered. Through another machine, also check that the database accepts connections from that machine.
