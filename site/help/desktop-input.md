# Keyboard, pointer, clipboard and audio

This page covers typing into a remote desktop, pointing and clicking on each device, sharing the clipboard, and hearing the remote computer's sound.

## Type on the remote computer

With the desktop focused, a hardware keyboard types directly into the remote computer. Letters, numbers and symbols arrive as the characters you typed. Keys pressed with Control, Option or Command, and keys such as the arrows, function keys, Delete and Return, arrive as the keys themselves.

- Control sends Ctrl, Option sends Alt, and Command sends the Windows key (the Super key over VNC).
- Caps Lock on the remote computer follows your keyboard.
- Press ⇧⌘Esc to take the keyboard back from the desktop, for example to use a shortcut in this app. Click, tap or pinch the desktop to give it the keyboard again.

Buttons for keys that are hard to type:

| Button | Where | What it does |
|---|---|---|
| **Escape**, **Tab** | Apple Vision Pro window controls | Send Escape or Tab. |
| **Esc**, **Tab** | Bar at the bottom of the window on Mac, iPad and iPhone | Send Escape or Tab. |
| **Input** | Apple Vision Pro and Mac | Opens **Send Text**. Type text and choose **Send** to type it on the remote computer. |
| **Keyboard** / **Hide Keyboard** | iPad and iPhone | Shows or hides the on-screen keyboard. |
| **Control–Alt–Delete** | In the **Clipboard** menu | Sends Control-Alt-Delete, for example to reach the Windows sign-in or security screen. |

> [!NOTE]
> Over VNC, characters that have no VNC equivalent are skipped when you type or send text.

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

With **Share clipboard** off, the menu offers **Type Clipboard Text** instead, which types this device's clipboard text into the remote computer as keystrokes.

Files are not shared through the clipboard. Over VNC only text is shared, limited to Western European (Latin-1) characters; other characters are dropped.

## Hear the remote computer (RDP)

Turn on **Remote audio** in the service's **Advanced** settings to play the remote computer's sound on this device. It is off by default, and it is available for RDP only. Your microphone is never sent to the remote computer.
