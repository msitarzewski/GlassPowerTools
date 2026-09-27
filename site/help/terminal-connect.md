# Connect to a machine over SSH

This page covers setting up a Terminal service, connecting, passwords, jump hosts, legacy algorithms for old servers, and dropped connections.

## Set up a Terminal service

A Terminal service belongs to a host in the library. The host holds the machine's address; the service holds how you sign in.

1. In the library, select the host, then choose **Add a service…** and pick **Terminal**.
2. Enter the **Username**, for example `ann`.
3. Choose a **Method**: **Password** or **SSH Key**.
4. For **Password**, type it in **Password**. For **SSH Key**, pick a key from **SSH Key**, or choose **Add SSH Key** to import one now.
5. Open **Advanced** if you need any of these:
   - **Name**: the service's name. It defaults to one based on the host.
   - **Port**: the SSH port. The default is 22.
   - **Allow Legacy SSH Algorithms**: see [Connect to an old server](#connect-to-an-old-server).
   - **Add Jump Host**: see [Connect through jump hosts](#connect-through-jump-hosts).
   - **Use App Default Size**: turn it off to set **Columns** and **Rows** for this service's new terminals.
   - **Color tag**.
6. Save the sheet.

When you change the host's address later, its Terminal services follow it.

## Connect

Choose **Connect** on the host's Terminal service in the library.

- **On Vision Pro:** the terminal opens in a window of its own, named after the machine.
- **On Mac:** the terminal opens in a terminal window. See [Work in a terminal](terminal-sessions.md).
- **On iPad and iPhone:** the terminal takes over the screen. **Connections** at the top leading edge goes back to the library; the session keeps running.

The first time you connect to a machine, you are asked to trust its host key. See [Sign in with keys and trust host keys](terminal-keys-and-trust.md).

## Enter a password

If the service has no saved password, the **Password Required** sheet appears. It names the account, for example `ann@192.0.2.10:22`.

1. Type the password.
2. Choose **Save & Connect**.

The app saves the password in Keychain first, then connects. If the password is wrong, the connection fails with **Connection Failed**. Edit the Terminal service and enter the correct **Password**.

## Connect through jump hosts

A jump host is another saved Terminal connection that the app connects through first.

1. Edit the Terminal service and open **Advanced**.
2. Under the route, choose **Add Jump Host** and pick a saved connection.
3. Add more hops in the order the connection should take them. **Remove hop 1** (and so on) removes one.

With no hops, the route shows **Direct connection**. While connecting, the terminal prints each hop as it connects.

## Connect to an old server

Some old servers accept only algorithms that modern SSH no longer offers. For such a server only:

1. Edit its Terminal service, open **Advanced** and turn on **Allow Legacy SSH Algorithms**.
2. Each time you connect, **Use Legacy SSH Algorithms?** appears. Choose **Connect with Legacy Algorithms** to continue, or **Cancel**.

The app still tries modern algorithms first and falls back only if the server rejects them. The option never changes how the server's host key is checked.

> [!WARNING]
> Legacy algorithms give weaker protection. Use them only for a server you control, until you can upgrade it.

**On Mac:** a Workgroup that includes such a connection does not open. Open that connection directly instead.

## When a connection drops

The app checks the connection every 60 seconds. After three checks go unanswered, the connection counts as lost.

If **Auto-reconnect on disconnect** is on (it is by default), the terminal tries again up to five times, waiting longer before each try. The terminal shows **Reconnecting...** with the attempt number. To stop, choose the close button beside it, or **Cancel Reconnect** in the session's tools menu.

Auto-reconnect does not run when you disconnect yourself or when the remote shell exits normally, for example after `exit`. To try again by hand, choose **Reconnect** in the session's tools menu.

To change auto-reconnect, open Settings, then **Connections**, and use **Auto-reconnect on disconnect**.

## If a connection fails

**Connection Failed** shows the reason. For an address on your local network, such as a `.local` name or a private address, it also says how to allow Local Network access: in System Settings, open **Privacy & Security** > **Local Network** and allow Glass Power Tools.
