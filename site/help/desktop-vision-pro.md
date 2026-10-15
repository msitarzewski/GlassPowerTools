# Remote desktops on Apple Vision Pro

On Apple Vision Pro a remote desktop is a window you can place, resize and see through. This page covers the window's controls, how input works in the headset, and the glass and background-removal settings. Glass also works on Mac; background removal works on Mac, iPad and iPhone.

## The desktop window

Each desktop opens in its own window with the service's name at the top and a row of controls below it:

| Control | What it does |
|---|---|
| **Shrink to Orb** | Shrinks the window into a small glass orb with the desktop's live picture; pinch the orb to bring the window back. The desktop stays connected. See [Shrink a session window to an orb on Vision Pro](library-connect.md#shrink-a-session-window-to-an-orb-on-vision-pro). |
| **Settings** (gear) | Opens **Desktop Settings**, which also holds the display this window shows and, for Screen Sharing (VNC), **Quality**. See [Give a desktop window its own settings](desktop-sessions.md#give-a-desktop-window-its-own-settings). |
| **Clipboard** | Sends this device's clipboard, or copies the remote computer's, and sends Control–Alt–Delete. With **Share clipboard** off, it types the clipboard's text instead. See [Keyboard, pointer, clipboard and audio](desktop-input.md#share-the-clipboard). |
| **Keys** | **Type Text…**, where you type text and choose **Send** to type it on the remote computer; **Escape** and **Tab**; **Control**, **Option**, **Command** and **Shift** for the next key; navigation keys; and F1–F12. See [Keys that are hard to type](desktop-input.md#keys-that-are-hard-to-type). |
| **Arrows** | Drag on it to send arrow keys. |
| ⚡ | Brings the library forward on **Active**. Pinch and hold it for **All Windows**; see [See everything open with Show All Windows](library-connect.md#see-everything-open-with-show-all-windows). |

The window is at least 800 × 440 points. It keeps the shape of the display it shows as you resize it, so the picture fills it with no bars (**Keep Display Proportions**, in **Desktop Settings** > **This Window**). While **Match Window Size** is changing the remote computer's resolution to match the window, the window can take any shape instead. See [Resolution, scaling and zoom](desktop-display-and-scaling.md) and [Keep a window in its display's shape](desktop-display-and-scaling.md#keep-a-window-in-its-displays-shape).

## A window for each display

When a computer with several displays connects, each display opens in a window of its own, as if you had a monitor for each: the desktop's window shows the main display, and the others open beside it. Place, resize, zoom and tilt each window on its own; each keeps its display's shape. The pointer and keys go to the display of the window you are using, and the pointer is drawn in whichever window shows the display it is on, at the size the computer shows it. All of them share one connection. A Mac sends its whole picture at one scale, so while a Retina display and a standard one are both on screen, each arrives at its own pixels; see [Retina displays from a Mac](desktop-display-and-scaling.md#retina-displays-from-a-mac).

Close a display's window when you don't need it: the others stay connected, and that display stops using the network. Closing the last window ends the session. To open a display again, choose **Settings** in one of the desktop's windows, and under **Displays** in **This Window** choose the display's **Open … in a New Window**, for example **Open Display 2 in a New Window**.

To keep every display in one window instead, set **Display Windows** to **One Window** in **Desktop Settings** > **Connection**, or for every desktop in **Settings** > **Desktops**. See [Several displays](desktop-display-and-scaling.md#several-displays).

## Input in the headset

- Look at a point on the desktop and pinch to click there. Pinch and drag to drag.
- Pinching is how you select in visionOS, so it does not zoom the desktop. To see more detail, make the window larger, or use **Local Scale** in **Desktop Settings** > **This Window**.
- A connected keyboard types directly into the remote computer, and a connected trackpad or mouse points and clicks. To take the keyboard back from the desktop, press ⇧⌘Esc; the desktop has the keyboard again the next time you pinch it.
- Without a keyboard, use **Keys** > **Type Text…** to send text, the rest of **Keys** for Escape, Tab, modifiers, navigation and function keys, and **Arrows** for the arrow keys. A connected keyboard's arrow keys go to the remote computer too, not to visionOS.

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
