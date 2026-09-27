# Connect to and leave a remote desktop

This page covers opening a remote desktop, entering a password when one is needed, what the status messages mean, and how to reconnect or close a session.

## Connect

1. Select the host in the library.
2. Choose **Connect** (play) on the Desktop service row.

On Apple Vision Pro, Mac and iPad, the desktop opens in a window of its own. Choosing **Connect** again for a desktop that is already open brings its window forward.

**On iPhone:** the desktop covers the library. Choose the back chevron (**Connections**) to close it and return to the library.

While the session starts, the window shows **Connecting…**, then **Waiting for desktop…** until the first image arrives, then **Connected**. On Mac, iPad and iPhone the bar at the bottom of the window shows the status and the remote resolution, for example `1920 × 1080`.

## Enter a password when asked

If there is no saved password, or it cannot be used, a **Connect to** sheet opens with the service's name.

1. Check **Username** (RDP) or **Mac user name (optional)** (VNC). For a VNC server that uses only a password, leave the name blank; the password field is then labeled **VNC password**.
2. Enter **Password**.
3. Turn on **Save in Keychain** to keep the name and password for next time.
4. Choose **Connect**.

An RDP connection uses the **Domain** saved in the service. To change the domain, edit the service. See [Add a remote desktop](desktop-add-service.md).

To enter a different account at any time the session is not connected, choose **Enter Credentials** in the middle of the window.

## When a connection fails

If the desktop cannot be opened, the window shows **Unable to Connect**. If an open desktop drops, it shows **Connection Lost**. Both offer:

- **Reconnect** — tries again with the saved password.
- **Close** — ends the session and closes the window.
- **Enter Credentials** — opens the **Connect to** sheet.
- **Technical Details** — the server's or the network's own message, which you can select and copy.

A problem that does not end the session, such as a key the server cannot accept, appears in a strip below the desktop. Choose **Dismiss** (the x) to hide it.

If a certificate needs checking first, you see **Verify Remote Computer** instead. See [Sign in and trust a remote computer](desktop-sign-in-and-trust.md).

## Leave a session

- **On Apple Vision Pro, Mac and iPad:** close the desktop's window. The session ends.
- **On iPhone:** choose the back chevron.
- When the remote computer ends the session cleanly after the desktop has appeared, for example because you signed out, the window closes by itself.

You can also see and close every open desktop from the ⚡ **Active** list, where each desktop shows **RDP** or **VNC**, followed by its status when it is not connected. On iPhone, the ⚡ button is in the desktop's toolbar.

When the app moves to the background, or the desktop window loses focus, keys and mouse buttons you were holding are released on the remote computer, so nothing stays pressed.

> [!NOTE]
> **On Apple Vision Pro and Mac:** desktop windows are not restored when you quit and reopen the app. Connect again from the library.
