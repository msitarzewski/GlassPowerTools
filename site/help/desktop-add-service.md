# Add a remote desktop

A Desktop service lets you see and control another computer's screen, over Remote Desktop (RDP) for Windows and Linux servers, or Screen Sharing (VNC) for a Mac or another VNC server. This page covers adding the service, its fields, and editing it.

## Add a Desktop service to a host

1. Choose **Add Host** to create a new machine, or select an existing host and choose **Add a service…** under **Services**.
2. Choose **Desktop** in the service picker.
3. In **Protocol**, choose **Remote Desktop (RDP)** or **Screen Sharing (VNC)**.
4. Enter the account:
   - For RDP, enter **Username**. It is required.
   - For VNC, **Mac user name** is optional. Enter a Mac account name to sign in to Apple Screen Sharing with that account. Leave it blank for a server that accepts only a VNC password.
5. Enter **Password**. It is required when you add a service.
6. Choose **Add**.

The address belongs to the host, not the service. If the host has no address yet, the sheet asks for one; every service on the host shares it.

> [!WARNING]
> When you choose **Screen Sharing (VNC)** without a Mac user name, the sheet says: "Without a Mac user name, VNC protects the password at sign-in, not what follows: the screen and your typing cross the network readable. Add the Mac's user name, or use it on a network you trust." With a Mac user name, a Mac is encrypted after it signs you in, and the sheet says so; a server that isn't a Mac still protects only the password. Use a Mac account, RDP, or a network you trust when that matters.

## Advanced settings

Open **Advanced** for everything optional. The RDP-only rows are hidden when you choose VNC.

| Setting | What it does |
|---|---|
| **Name** | The service's name. Leave it blank to use the machine's name. |
| **Port** | Leave it blank for the protocol's default: 3389 for RDP, 5900 for VNC. Changing **Protocol** clears this field, so choose the protocol first. |
| **Domain** (RDP) | The Windows domain for the account, for example `EXAMPLE`. Optional. |
| **Authentication** (RDP) | **Network Level (NLA)** requires Network Level Authentication. **Allow TLS fallback** also accepts servers that offer only TLS. See [Sign in and trust a remote computer](desktop-sign-in-and-trust.md). |
| **Desktop size** | Width and height in pixels, 1920 × 1080 by default. Each side must be from 200 to 8192, and the width must be even. |
| **Share clipboard** | Shares the clipboard with the remote computer: text, formatting and images over RDP, text over VNC. Off by default. See [Keyboard, pointer, clipboard and audio](desktop-input.md). |
| **Sync clipboard automatically** | With the clipboard shared, copies cross by themselves. On by default; also in the desktop's **Clipboard** menu, as **Sync Automatically**. Off, **Send Clipboard** and **Copy Remote Clipboard** move a copy when you choose them. |
| **Remote audio** (RDP) | Plays the remote computer's sound on this device. Off by default. |
| **Graphics** (RDP) | Which pictures the remote computer is asked to send. **Automatic**, the default, uses its best picture. If colours smear while things move, choose **H.264 (4:2:0)**, which leaves out H.264's 4:4:4 form; a computer that does not offer it sends its other pictures instead. If the picture breaks up or stays blank, choose **Without H.264**. Takes effect the next time you connect. |
| **Credential storage** | **iCloud Keychain** (the default) syncs the password to your other devices through iCloud Keychain. **This device only** keeps it here. |

With **Match Window Size** on, which is the default, an RDP session asks for the size of its window rather than **Desktop size**. On a Mac, **Desktop size** also sets how large a new session window opens. See [Resolution, scaling and zoom](desktop-display-and-scaling.md).

## Edit a Desktop service

1. Select the host, then choose **Edit** (pencil) on the Desktop service row.
2. Change what you need and choose **Save**.

- Leave **Password** blank to keep the saved password.
- Changing **Username** or **Domain** needs the password too. Without it you see "Enter the password to save an account or domain change. The previous credential is still preserved."
- Changing **Port** or **Authentication** clears any certificate you trusted for this computer, so you are asked to verify it again on the next connection. Changing the host's address does the same.
- Changing **Credential storage** moves the saved password to the storage you chose.

To remove the service, open the context menu on its service row and choose **Remove Service**. This removes the saved desktop from the host.

## If a field is not accepted

When you try to save, the sheet shows a message under each field it cannot accept:

- "Enter the account to sign in with." — RDP needs a user name.
- "Enter the password for this desktop." — a new service needs a password.
- "Enter a port between 1 and 65535, or leave it blank for 3389." (or 5900 for VNC)
- "Enter a size between 200 and 8192, with an even width."
