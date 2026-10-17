# Sign in and trust a remote computer

This page explains how a Desktop service signs in over RDP and VNC, how the app decides whether to trust an RDP server's certificate, and which RDP features and server setups are not supported.

## RDP sign-in

An RDP service signs in with **Username**, **Password** and, optionally, **Domain**. Choose how strict the connection is under **Advanced** > **Authentication**:

- **Network Level (NLA)** — the default. The server must offer Network Level Authentication, which checks your account before the remote desktop starts. If the server does not offer it, the connection fails with **Unable to Connect**, and **Technical Details** say the server did not negotiate Network Level Authentication. For such a server, choose **Allow TLS fallback**.
- **Allow TLS fallback** — also connects to a server that offers TLS without Network Level Authentication. When the server offers Network Level Authentication, it is still used.

Network Level Authentication uses NTLM. Kerberos is not supported, so a domain account signs in with its user name, domain and password.

> [!NOTE]
> The older RDP security layer, which does not use TLS, is not supported. A server that offers only that layer cannot be reached.

## VNC and Screen Sharing sign-in

A VNC service picks the sign-in method from what the server offers and what you entered:

- With a **Mac user name** and password, it signs in with that Mac account when the server offers it. This is how Apple Screen Sharing expects to be reached. User names and passwords can be up to 63 bytes. A server that doesn't offer account sign-in but does offer a VNC password gets the password alone, and the user name is not used.
- With only a password, it uses the VNC password. VNC passwords use at most their first eight bytes, which is eight characters of English; that is part of the protocol.
- If the server asks for nothing, the app still needs a password to connect, but does not send it.

When the server wants something you did not enter, the connection fails with "This server needs a Mac user name and password (Apple Remote Desktop authentication)." or "This server needs a VNC password." If the server offers only methods the app does not support, the message asks you to enable VNC password or user-account access on the host.

> [!WARNING]
> With a **Mac user name** and password, a Mac is reached in Apple's own Screen Sharing revision, and the session is encrypted after sign-in. Other VNC — a password alone, or a server that isn't a Mac — protects the password at sign-in, not what follows: the screen and your typing cross the network readable. If a Mac can't be reached in its own revision, the message says so, and Reconnect connects unencrypted, as does every connection to that Mac until the app is opened again. Use VNC without a Mac account on a network you trust.

## Verify an RDP server's certificate

Every RDP connection uses TLS with the server's certificate. By default, the app accepts a certificate your device already trusts.

When the certificate is not trusted, which is common for a self-signed certificate, the connection stops before your password is sent, and the **Verify Remote Computer** alert shows the certificate's SHA-256 fingerprint.

1. Compare the fingerprint with the one the computer's administrator gives you.
2. If they match, choose **Trust and Reconnect**. The app saves the fingerprint for this host and port and connects again.
3. If they do not match, or you cannot check, choose **Cancel**.

After you trust a certificate, the service accepts only that certificate. If the server's certificate changes, for example when it is renewed, you are asked to verify it again. Changing the service's **Port** or **Authentication**, or the host's address, clears the saved fingerprint.

## Saved passwords

A password is saved in Keychain. **Credential storage** decides where it lives:

- **iCloud Keychain** — the default for a service you add by hand. It syncs to your other devices that use iCloud Keychain.
- **This device only** — stays on this device.

If there is no saved password, or it cannot be read, the app asks for one when you connect. See [Connect to and leave a remote desktop](desktop-sessions.md).

## What is not supported

These RDP features and setups are not available:

- RD Gateway, connection brokers, Azure Virtual Desktop and Microsoft Entra sign-in.
- Kerberos.
- RemoteApp (single remote programs).
- Drive, printer, smart-card and USB redirection.
- Microphone and camera.
- Multiple remote monitors. An RDP session shows one monitor.
- UDP transport. Connections use TCP.

Files are not shared through the clipboard. Over RDP a copy carries its text, formatting and images; over VNC, only text. See [Keyboard, pointer, clipboard and audio](desktop-input.md#share-the-clipboard).

> [!NOTE]
> The RDP engine has been tested against Windows 11, signing in with Network Level Authentication, and against two Linux RDP servers, GNOME Remote Desktop and xrdp. Other versions of Windows and Windows Server have not been tried. The Windows 11 host did not offer resizing, so on it the remote resolution stays fixed.
