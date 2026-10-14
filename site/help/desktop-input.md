# Keyboard, pointer, clipboard and audio

This page covers typing into a remote desktop, the **Keys** menu and arrow pad, pointing and clicking on each device, sharing the clipboard, and hearing the remote computer's sound.

## Type on the remote computer

With the desktop focused, a hardware keyboard types directly into the remote computer. Letters, numbers and symbols arrive as the characters you typed. Keys pressed with Control, Option or Command, and keys such as the arrows, function keys, Delete and Return, arrive as the keys themselves.

- Control sends Ctrl, Option sends Alt, and Command sends the Windows key (the Super key over VNC). To a Mac, Option arrives as Option and Command as Command.
- Caps Lock on the remote computer follows your keyboard.
- Press ⇧⌘Esc to take the keyboard back from the desktop, for example to use a shortcut in this app. Click, tap or pinch the desktop to give it the keyboard again.

**On iPad and iPhone**, **Keyboard** in the bar at the bottom of the window shows the on-screen keyboard, and **Hide Keyboard** hides it.

> [!NOTE]
> Over VNC, characters that have no VNC equivalent are skipped when you type or send text.

## Keys that are hard to type

For keys your keyboard lacks, or when you have no keyboard, the desktop window has a **Keys** menu and an arrow pad (**Arrows**). They are in the row of controls below the window on Apple Vision Pro, and in the bar at the bottom of the window on Mac, iPad and iPhone (on Mac, **Keys** only). On iPad and iPhone, the bar above the on-screen keyboard has them too, with **Tools**, which holds the window's **Settings** and **Clipboard**, and a button that hides the keyboard.

**Keys** has:

- **Type Text…** (Apple Vision Pro and Mac): opens **Send Text**. Type text and choose **Send** to type it on the remote computer.
- **Escape** and **Tab**.
- **For the Next Key**: **Control**, **Option**, **Command** and **Shift**. Turn on one or more, and they are held down for the next key you send from **Keys**, the arrow pad or the on-screen keyboard, then let go. While any are on, the menu's name says which, for example **Keys: Control**. With **Command** on, typing `c` on the on-screen keyboard sends ⌘C to a Mac; with **Control** on, it sends Ctrl-C to Windows.
- **Navigation**: the arrow keys, **Home**, **End**, **Page Up**, **Page Down** and **Forward Delete**.
- **Function Keys**: F1–F12.

Drag on the arrow pad to send arrow keys: one for each short step, along the direction you first move, back as well as forward. Keys turned on under **For the Next Key** are held for the whole drag, so with **Shift** on, the drag selects as it goes.

**Control–Alt–Delete**, in the **Clipboard** menu, sends Control-Alt-Delete, for example to reach the Windows sign-in or security screen.

## Point and click

**On Apple Vision Pro:** look at a point and pinch to click there; pinch and drag to drag. A connected trackpad or mouse also works.

**On Mac:** the mouse or trackpad moves the remote pointer. Left, right and middle buttons, the back and forward buttons, and vertical and horizontal scrolling are sent. Over VNC the forward button is not available.

**On iPad and iPhone:** choose how touch works in **Desktop Settings** > **This Window** > **Touch** > **Pointer**:

- **Trackpad** — the default on iPhone and in a narrow iPad window. Drag anywhere to move the pointer, tap to click where it sits, and tap with two fingers to right-click. Tap, then drag, to move something. If the remote computer does not draw a pointer, the app draws one so you can see where it is.
- **Direct Touch** — the default in a full-width iPad window. Touching the screen presses the button at that point, which suits a large screen or Apple Pencil.

In both modes, two fingers scroll the remote desktop, and a connected trackpad or mouse moves the pointer when you hover. The choice is this desktop window's, kept on this device. To choose for every desktop window, use **Pointer** in **All Desktops** (the same as **Settings** > **Desktops**), where **Automatic** chooses as described above. See [Give a desktop window its own settings](desktop-sessions.md#give-a-desktop-window-its-own-settings).

## Share the clipboard

Turn on **Share clipboard** in the service's **Advanced** settings to share the clipboard with the remote computer. It is off by default.

- **Over RDP**, a copy carries its text, formatting (HTML and rich text) and images, both ways. Something copied on the remote computer is on this device's clipboard straight away.
- **On Mac**, something you copy here reaches the remote computer when its window becomes active, and whenever you copy again while it is. **On iPhone, iPad and Vision Pro**, choose **Send Clipboard** in the **Clipboard** menu, because the system asks before an app reads another app's copy.
- **Copy Remote Clipboard** in the **Clipboard** menu puts the remote computer's latest copy on this device's clipboard again.
- **Sync Automatically**, at the top of the **Clipboard** menu, is on unless you turn it off. Off, copies no longer cross by themselves, in either direction: **Send Clipboard** and **Copy Remote Clipboard** still move one when you choose them. It takes effect at once and is remembered for the desktop; the service's settings have it too, as **Sync clipboard automatically**.

With **Share clipboard** off, the menu offers **Type Clipboard Text** instead, which types this device's clipboard text into the remote computer as keystrokes.

Files are not shared through the clipboard. Over VNC only text is shared. With a Mac signed in with a Mac user name, any text is shared, through the Mac's own pasteboard. With other VNC servers it is limited to Western European (Latin-1) characters; other characters are dropped.

## Hear the remote computer

Turn on **Remote audio** in the service's **Advanced** settings to play the remote computer's sound on this device. It is off by default, and it is for RDP only. Your microphone is never sent to the remote computer.

A Mac in **High Performance (Experimental)** sends its sound with its picture, and it plays without **Remote audio**; see [High Performance from a Mac](desktop-display-and-scaling.md#high-performance-from-a-mac-experimental).
