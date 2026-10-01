# Remote desktops on Apple Vision Pro

On Apple Vision Pro a remote desktop is a window you can place, resize and see through. This page covers the window's controls, how input works in the headset, and the glass and background-removal settings. Glass also works on Mac; background removal works on Mac, iPad and iPhone.

## The desktop window

Each desktop opens in its own window with the service's name at the top and a row of controls below it:

| Control | What it does |
|---|---|
| **Settings** (gear) | Opens **Desktop Settings**. |
| **Clipboard** | Sends or copies clipboard text, and sends Control–Alt–Delete. See [Keyboard, pointer, clipboard and audio](desktop-input.md). |
| **Escape** | Sends the Escape key. |
| **Tab** | Sends the Tab key. |
| **Input** (keyboard) | Opens **Send Text**, where you type text and choose **Send** to type it on the remote computer. |

The window is at least 800 × 440 points. With **Match Window Size** on, resizing the window changes the remote computer's resolution to match. See [Resolution, scaling and zoom](desktop-display-and-scaling.md).

## Input in the headset

- Look at a point on the desktop and pinch to click there. Pinch and drag to drag.
- Pinching is how you select in visionOS, so it does not zoom the desktop. To see more detail, make the window larger, or use **Local Scale** in **Desktop Settings** > **Display**.
- A connected keyboard types directly into the remote computer, and a connected trackpad or mouse points and clicks. To take the keyboard back from the desktop, press ⇧⌘Esc; the desktop has the keyboard again the next time you pinch it.
- Without a keyboard, use **Input** to send text, and **Escape** and **Tab** for those keys.

## Glass

In **Desktop Settings** > **Appearance**, the **Glass** section changes how the window sits in your space:

- **Opacity** fades the whole desktop, from transparent to opaque.
- **Background Frost** changes the material behind it, from clear to frosted.
- **Clear** and **Frosted** set the frost in one step.

Set both to 0% for a clear canvas; the controls stay visible. These choices are remembered on this device and apply to the next desktop you open. **On Mac** the same **Glass** section is in each desktop's **Desktop Settings** > **Appearance** and in **Settings** > **Desktops**: the desktop window fades over a frosted or clear backdrop showing what is behind it.

> [!NOTE]
> When Reduce Transparency is on in Accessibility settings, the glass controls are unavailable and the desktop is shown opaque with **Original** presentation.

## Remove the remote desktop's background

Background removal makes parts of the remote image transparent, so a remote window can float over your surroundings or your other windows. In **Desktop Settings** > **Appearance**, choose a **Presentation**:

- **Original** — the complete image.
- **Remove Black** — black areas become transparent.
- **Remove Background Color** — a color you choose becomes transparent. Set the remote computer's desktop background to a solid color, then pick the same color in **Background Color**, or choose **Use Magenta** and set the remote background to magenta. **Color Code** shows the value, for example `#FF00FF`; choose **Copy** to copy it.
- **Remove Wallpaper** — choose **Choose Wallpaper Image** and select the same image the remote computer uses as its wallpaper. Areas that match it become transparent. The image is kept for this session only.

Matching colors anywhere on the desktop become transparent, including inside apps. Under **Edges**, **Tolerance** decides how close a color must be to match, and **Edge Softness** blends the border.

To go back, choose **Original** in the **Desktop Settings** toolbar; this also sets opacity back to full. **Reset Presentation** in **Display** resets presentation, zoom and, on Apple Vision Pro, frost.

**On Apple Vision Pro:** your presentation choice, color, tolerance and edge softness are remembered for the next desktop, except **Remove Wallpaper**.

**On Mac, iPad and iPhone:** these choices apply to the current session only.
