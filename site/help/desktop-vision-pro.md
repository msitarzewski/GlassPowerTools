# Remote desktops on Apple Vision Pro

On Apple Vision Pro a remote desktop is a window you can place, resize and see through. This page covers the window's controls, how input works in the headset, and the glass and background-removal settings. Glass also works on Mac; background removal works on Mac, iPad and iPhone.

## The desktop window

Each desktop opens in its own window with the service's name at the top and a row of controls below it:

| Control | What it does |
|---|---|
| **Settings** (gear) | Opens **Desktop Settings**. |
| **Clipboard** | Sends or copies clipboard text, and sends Control–Alt–Delete. See [Keyboard, pointer, clipboard and audio](desktop-input.md). |
| **Displays** (two rectangles) | Only for a computer with more than one display: chooses the display this window shows, and opens another display in a window of its own. |
| **Quality** (gauge) | Only for Screen Sharing (VNC): chooses how much picture the connection carries, under a line showing what it carries now. |
| **Escape** | Sends the Escape key. |
| **Tab** | Sends the Tab key. |
| **Input** (keyboard) | Opens **Send Text**, where you type text and choose **Send** to type it on the remote computer. |

The window is at least 800 × 440 points. With **Match Window Size** on, resizing the window changes the remote computer's resolution to match. See [Resolution, scaling and zoom](desktop-display-and-scaling.md).

## A window for each display

When a computer with several displays connects, each display opens in a window of its own, as if you had a monitor for each: the desktop's window shows the main display, and the others open beside it. Place, resize, zoom and tilt each window on its own; the pointer and keys go to the display of the window you are using, and the pointer is drawn in whichever window shows the display it is on. All of them share one connection.

Close a display's window when you don't need it: the others stay connected, and that display stops using the network. Closing the last window ends the session. To open a display again, choose **Displays** and the display under **Open in a New Window**.

To keep every display in one window instead, set **Display Windows** to **One Window** in **Desktop Settings** > **Connection**, or for every desktop in **Settings** > **Desktops**. See [Several displays](desktop-display-and-scaling.md#several-displays).

## Input in the headset

- Look at a point on the desktop and pinch to click there. Pinch and drag to drag.
- Pinching is how you select in visionOS, so it does not zoom the desktop. To see more detail, make the window larger, or use **Local Scale** in **Desktop Settings** > **This Window**.
- A connected keyboard types directly into the remote computer, and a connected trackpad or mouse points and clicks. To take the keyboard back from the desktop, press ⇧⌘Esc; the desktop has the keyboard again the next time you pinch it.
- Without a keyboard, use **Input** to send text, and **Escape** and **Tab** for those keys.

## Glass

In **Desktop Settings** > **This Window**, the **Appearance** section changes how this window sits in your space:

- **Opacity** fades the whole desktop, from transparent to opaque.
- **Glass** is the window's own glass, from none to Apple's.

The desktop sits inset in the window, with corners that follow the window's. Set both to 0% and only the title and controls remain. Only this window changes, and it keeps these on this device for the next time this desktop opens. To change every desktop window, use **All Desktops**, beside **This Window**, or **Settings** > **Desktops**, which are the same page; there **Clear** and **Frosted** set **Glass** in one step. A window follows **All Desktops** until you set its own; see [Give a desktop window its own settings](desktop-sessions.md#give-a-desktop-window-its-own-settings). **On Mac** the same settings apply: the desktop window fades over a frosted or clear backdrop showing what is behind it.

> [!NOTE]
> When Reduce Transparency is on in Accessibility settings, the glass controls are unavailable and the desktop is shown opaque with **Original** presentation.

## Remove the remote desktop's background

Background removal makes parts of the remote image transparent, so a remote window can float over your surroundings or your other windows. In **Desktop Settings** > **This Window**, under **Background Removal**, choose a **Presentation**:

- **Original** — the complete image.
- **Remove Black** — black areas become transparent.
- **Remove Background Color** — a color you choose becomes transparent. Set the remote computer's desktop background to a solid color, then pick the same color in **Background Color**, or choose **Use Magenta** and set the remote background to magenta. **Color Code** shows the value, for example `#FF00FF`; choose **Copy** to copy it.
- **Remove Wallpaper** — choose **Choose Wallpaper Image** and select the same image the remote computer uses as its wallpaper. Areas that match it become transparent. The image is kept for this session only.

Matching colors anywhere on the desktop become transparent, including inside apps. Under **Edges**, **Tolerance** decides how close a color must be to match, and **Edge Softness** blends the border.

To go back, choose **Show Original**, under **Presentation**: this window shows the complete image, at full opacity. **Reset This Window** returns the window to **All Desktops**' settings.

Each desktop window keeps its own presentation, color, tolerance and edge softness on this device, for the next time that desktop opens, except **Remove Wallpaper**, which lasts for the session that chose its image. To choose them for every desktop window, use **Background Removal** in **All Desktops** (the same as **Settings** > **Desktops**); it offers **Original**, **Remove Black** and **Remove Background Color**.
