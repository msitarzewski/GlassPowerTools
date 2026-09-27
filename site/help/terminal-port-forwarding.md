# Forward ports through an SSH session

Port forwarding carries network connections through a live SSH session. This page covers adding local, remote and dynamic (SOCKS) forwards, starting and stopping them, and their limits.

## Open port forwarding

1. In the terminal, open the session's tools menu and choose **Settings**.
2. Choose **Port Forwarding**.

**On Vision Pro and Mac**, **Port Forwarding** is one of the sections at the top of **Terminal Settings**. **On iPad and iPhone**, it is a row in the **Terminal Settings** list.

The list, **Port Forwards**, shows this session's forwards. Each row shows the forward's type and route, and any error in red.

## Add a forward

1. Choose **Add**.
2. Choose a **Type**: **Local**, **Remote** or **Dynamic (SOCKS)**.
3. Fill in the fields for that type, described below.
4. Choose **Add**.

A new forward starts turned off. Turn on its switch to start it, and turn it off to stop it. The trash button removes it.

> [!NOTE]
> Forwards belong to the live session. They are not saved, and they end when the session ends.

### Local

A local forward listens on this device and carries each connection to an address as seen from the server.

- **Local Port**: the port to listen on, on this device. The app listens on `127.0.0.1` only.
- **Remote Host** and **Remote Port**: where the server should connect, for example `localhost` and `5432` for a service on the server itself, or `192.0.2.20` and `80` for another machine the server can reach.

The row shows the route as `localhost:8080 → localhost:80`.

### Remote

A remote forward listens on the server and carries each connection back to this device.

- **Remote Host**: the address the server listens on. It must be `localhost`, `127.0.0.1` or `::1`, so the forward cannot expose this device to the server's network.
- **Remote Port**: the port the server listens on.
- **Local Port**: the port on this device that receives the connections, on `127.0.0.1`.

### Dynamic (SOCKS)

A dynamic forward runs a SOCKS5 proxy on this device. Each connection an app makes through the proxy leaves from the server.

- **Local Port**: the proxy's port, on `127.0.0.1`.
- **Username** and **Password**, under **SOCKS5 Authentication**: every app that uses the proxy must send these.

> [!IMPORTANT]
> The SOCKS5 username and password stay in memory for this session only. They are never saved with the forward.

Point an app's SOCKS5 proxy setting at `127.0.0.1` and the port you chose.

## When a forward does not start

The row shows why. Common reasons:

- **No active SSH connection.** The session is not connected. Reconnect, then turn the forward on again.
- **Permission denied binding port**: choose a **Local Port** of 1024 or higher.
- The port is already in use on this device. Choose another **Local Port**.

**Add** stays unavailable until the ports are numbers from 1 to 65535, a remote forward's **Remote Host** is one of the allowed addresses, and a dynamic forward has both a username and a password.
