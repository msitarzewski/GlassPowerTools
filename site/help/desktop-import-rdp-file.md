# Import an RDP file

If you already have a `.rdp` file, for example one exported from another Remote Desktop client or sent by an administrator, you can turn it into a host with a Desktop service. This page covers what the import reads, what it leaves out, and which files it refuses.

## Import a file

1. In the library toolbar, choose **Import RDP File…**. **On Mac**, with the library window in front, you can also choose **File** ▸ **Import RDP File…** (⇧⌘I).
2. Choose the `.rdp` file.
3. The **Add Host** sheet opens with the fields filled in from the file. Nothing is saved yet.
4. Read the **Imported with changes** section at the top, if there is one. It lists what the file asked for that the app did not bring across.
5. Review the fields, add a password if you want one saved, and choose **Add**.

The host takes the file's name (without `.rdp`) as its name, and the file's server address as its address. For example, `alpha.rdp` with `full address:s:192.0.2.10:3390` becomes a host named `alpha` at `192.0.2.10`, with a Desktop service on port 3390.

> [!NOTE]
> Passwords are never imported. You can leave **Password** blank; the app asks for it when you first connect, and you can choose to save it then. See [Connect to and leave a remote desktop](desktop-sessions.md).

## What the import reads

| In the file | Becomes |
|---|---|
| `full address`, `server port` | The host's address and the service's **Port**. A port in the address wins over a separate port setting. |
| `username`, `domain` | **Username** and **Domain**. A user name written as `EXAMPLE\ann` is split into domain `EXAMPLE` and user `ann`. |
| `desktopwidth`, `desktopheight`, or `desktop size id` | **Desktop size**. Each side must be from 200 to 8192; an odd width, or a size of more than 16,777,216 pixels, is adjusted to fit. `desktop size id` takes 0 to 4, from 640 × 480 to 1600 × 1200. |
| `redirectclipboard` | **Share clipboard**. |
| `audiomode` | **Remote audio**: on when the file plays sound on this computer. |

Every imported service uses **Network Level (NLA)** authentication and the system's certificate trust, whatever the file says. Other settings are ignored. An imported service starts with **Credential storage** set to **iCloud Keychain**, like any other; choose **This device only** under **Advanced** before you choose **Add** to keep the password on this device.

The notices you can see in **Imported with changes** are:

- "Saved passwords aren't imported. Enter it in Password below, or when connecting."
- "Authentication preferences in the file weren't imported. Network Level Authentication and certificate review remain enabled."
- "The port in the server address takes precedence over the file's separate port setting."
- "The initial resolution was adjusted to fit supported desktop limits."
- "Playback on the remote computer isn't imported. Remote audio is off; enable it below to play sound on this device."
- "Other client-specific settings in the file weren't imported. Review the connection settings below."

## Files that cannot be imported

Some files describe connections the app does not make. For these, an **Import Failed** alert explains why, and no sheet opens:

- A connection through an RD Gateway.
- A RemoteApp connection, or one that starts a custom program instead of the desktop.
- A connection that needs a connection broker.
- A connection that needs Microsoft Entra sign-in.

The alert also appears when the file is not a regular `.rdp` file, is larger than 1 MB or 8,192 lines, has text that can't be read as UTF-8, UTF-16 or Windows Latin-1, has a line that is not a valid setting, repeats a setting, has a setting with an invalid value (a port out of range, a desktop side outside 200 to 8192, or a `DOMAIN\user` name whose domain differs from the file's `domain`), or has no server address.

> [!TIP]
> If a file is refused because of a gateway or broker, ask the administrator for the address of the computer itself, and add the service by hand. See [Add a remote desktop](desktop-add-service.md).
