# Connect to and leave a remote desktop

This page covers opening a remote desktop, entering a password when one is needed, what the status messages mean, how to reconnect, giving a desktop window its own settings, and closing a session.

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

## Give a desktop window its own settings

Anything about how a desktop window looks and behaves can be set for that window alone: a see-through window for one computer and an opaque one for another, or a different **Detail** for each. Choose **Settings** (gear) in the desktop window to open **Desktop Settings**: it opens on **This Window**. **All Desktops**, beside it, is the same page as **Settings** > **Desktops** and changes every desktop window on this device. **On iPad and iPhone**, choose **This Window** or **All Desktops** from the list.

**This Window** has:

- **Appearance** (**on Mac and Apple Vision Pro**): **Opacity** and **Glass**. See [Remote desktops on Apple Vision Pro](desktop-vision-pro.md#glass).
- **Background Removal**: **Presentation**, with **Background Color**, **Tolerance** and **Edge Softness**, and **Show Original**, which shows this window's complete desktop image, opaque, in one step. See [Remove the remote desktop's background](desktop-vision-pro.md#remove-the-remote-desktops-background).
- **Remote Desktop**: **Detail** (RDP), and **Keep Display Proportions** (**on Mac and Apple Vision Pro**). See [Resolution, scaling and zoom](desktop-display-and-scaling.md#sharper-text-on-high-resolution-displays-rdp) and [Keep a window in its display's shape](desktop-display-and-scaling.md#keep-a-window-in-its-displays-shape).
- **Touch** (**on iPad and iPhone**): **Pointer**. See [Keyboard, pointer, clipboard and audio](desktop-input.md#point-and-click).

For Screen Sharing (VNC), and for any computer with several displays, a third page sits between them: **Connection**, with **Quality**, **Retina Displays** and what the network carries now, the desktop's **Windows** and what each is sent, and **Display Windows**. These belong to the desktop's connection rather than to one window, so every window of the desktop shows and changes the same ones. See [Several displays](desktop-display-and-scaling.md#several-displays), [Quality and the network](desktop-display-and-scaling.md#quality-and-the-network-screen-sharing) and [Retina displays from a Mac](desktop-display-and-scaling.md#retina-displays-from-a-mac).

Each setting follows **All Desktops** until you change it here. Once you do, a small ↺ appears beside its name; choose it to follow again. Its tooltip says what it returns to: hold the pointer over it, or on Vision Pro look at it. **Reset This Window**, at the end, returns every one. Only this window changes, at once.

A desktop's window keeps its own settings on this device. Desktop windows are not reopened when you quit the app, but the next time you connect to the same desktop here, its window has them again. A display's window keeps its own too, for that display. They are not synced to your other devices, and removing the desktop removes them all.

**This Window** also holds this session's own controls, which start over each time the desktop opens: **Match Window Size**, the display shown, **Desktop Resolution** and **Local Scale**. **Remove Wallpaper** and its image also last only for the session.

Some settings are only ever the desktop's, or this device's. The account, password, domain, authentication, certificate, **Desktop size**, **Share clipboard** and **Remote audio** belong to the service: edit it in the library, and the change applies the next time the desktop connects. **Important Session Notices** is for every desktop on this device.

## Leave a session

- **On Apple Vision Pro, Mac and iPad:** close the desktop's window. The session ends. If its displays are in windows of their own, it ends when the last of them closes; until then **Connect** brings the desktop's window back onto the same connection.
- **On iPhone:** choose the back chevron.
- When the remote computer ends the session cleanly after the desktop has appeared, for example because you signed out, the window closes by itself.

You can also see and close every open desktop from the ⚡ **Active** list, where each desktop shows **RDP** or **VNC**, followed by its status when it is not connected. On iPhone, the ⚡ button is in the desktop's toolbar.

When the app moves to the background, or the desktop window loses focus, keys and mouse buttons you were holding are released on the remote computer, so nothing stays pressed.

> [!NOTE]
> **On Apple Vision Pro and Mac:** desktop windows are not restored when you quit and reopen the app. Connect again from the library; each window has its own settings again when you do.
