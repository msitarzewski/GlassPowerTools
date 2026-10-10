# Resolution, scaling and zoom

A remote desktop has two sizes: the resolution the remote computer draws at, and how large that image appears in your window. This page covers both, in **Desktop Settings** > **This Window**. Open **Desktop Settings** with **Settings** (gear) in the desktop window.

## Let the remote resolution follow the window

**Match Window Size** is on when a session starts. While it is on, the app asks the remote computer to change its resolution whenever you resize the window, a quarter of a second after you stop.

This works only when the server offers display control. Until it does, **Match Window Size** is unavailable and the section says "Source resizing becomes available when the server offers display control." The remote image is then scaled to fit the window, with bars at the sides or top if the shapes differ.

- **RDP:** a session starts at the window's size. The server must support dynamic display resizing to follow later changes. Sizes are from 200 to 8192 pixels per side, within the limits the server announces.
- **VNC:** the server chooses the starting size. If the server supports desktop resizing, it then follows the window.

If the server changes its own size, for example after you sign in, the app asks for the window's size again, up to three times per connection.

**Current Resolution** shows the size the remote computer is drawing now. The same size appears in the bar at the bottom of the window on Mac, iPad and iPhone.

## Sharper text on high-resolution displays (RDP)

**Detail** asks for more remote pixels per point of your window, so text stays sharp without looking smaller:

- **Automatic** follows the display the window is on. This is the default.
- **100%**, **150%**, **200%** ask for that many pixels per point.

Higher settings send more pixels over the network. A server that ignores the scale shows a smaller interface. **Detail** needs **Match Window Size** on. Set here, it is this desktop window's own, kept on this device; **Detail** in **All Desktops** (the same as **Settings** > **Desktops**) sets it for every desktop window that hasn't set its own. See [Give a desktop window its own settings](desktop-sessions.md#give-a-desktop-window-its-own-settings).

## Choose a fixed resolution

Open **Desktop Resolution** and choose **1280 × 800**, **1920 × 1080**, **2560 × 1440** or **3840 × 2160**. Sizes the server does not accept are unavailable. Choosing one turns **Match Window Size** off, so resizing the window no longer changes the resolution. Turn **Match Window Size** on again to go back.

## Several displays

A computer with several displays sends one image covering all of them. When it says where each display sits in that image, **Displays** appears in the window's controls and a **Displays** section in **This Window**:

- **Show** chooses what this window shows: **All Displays**, **Main Display** or another display. A single display fills the window.
- **Open in a New Window** (in the **Displays** control) opens a display in a window of its own, on Apple Vision Pro, Mac and iPad. Each window has its own display, zoom, tilt and settings, and the pointer and keys go to the display of the window you use. All of a desktop's windows share one connection.
- **Display Windows**: **A Window for Each Display** opens one window per display whenever the desktop connects; **One Window** keeps them together. It starts as **A Window for Each Display** on Apple Vision Pro and **One Window** elsewhere, and can be set in **Settings** > **Desktops**, or for one desktop in **Desktop Settings** > **Connection**.

**Screen Sharing (VNC):** the computer is asked only for the displays that have a window on screen. A display whose window is closed or in the background costs nothing on the network, and its picture is fetched again when its window returns. Closing a display's window leaves the others connected; closing the last ends the session.

While a VNC computer has several displays, the app does not change its resolution: **Match Window Size** and **Desktop Resolution** are unavailable, because one desktop the size of a window would fold its displays into one.

If the computer does not say where its displays are, the window shows them as one picture and **Displays** does not appear.

## Quality and the network (Screen Sharing)

**Quality**, in the window's controls and in **Desktop Settings** > **Connection**, chooses how much picture a VNC connection carries. It belongs to the connection, so it applies to every window of the desktop.

| Quality | What the computer is asked to send |
|---|---|
| **Automatic** (default) | Measures how fast the picture arrives and moves between the levels below as the connection changes: down quickly on a slow link, up slowly once it is fast again. |
| **Best** | Every pixel exactly, in full color, as fast as the connection allows. |
| **Balanced** | Full color, with photos and video compressed as JPEG where the computer offers it. |
| **Data Saver** | Thousands of colors, stronger compression and JPEG, at most 15 updates a second. |
| **Lowest** | The strongest compression and JPEG, at most 8 updates a second; 256 colors where the computer does not send JPEG. |

A Mac's Screen Sharing has not been seen to send JPEG to apps other than Apple's own, so on a Mac the levels work through colors, compression and how often the picture is asked for. They never go below thousands of colors there: older versions of macOS ended the session when asked for fewer.

On the **Connection** page, under **Quality**, the figures show what the network is carrying now, updated every second: **Receiving** (for example `1.2 Mbit/s`), **Updates** per second, the **Level** in effect (with **Automatic**, the level it chose), **Color**, the **Encoding** the computer is using, and **Fetching** (the whole desktop, only the displays on screen, or nothing). The **Quality** control in the window shows the same as one line above its choices, and on Mac, iPad and iPhone the line also appears in the bar at the bottom of the window.

Zooming or shrinking the picture in the window does not change what the network carries: the computer sends its own pixels either way. To send fewer pixels, lower the remote resolution, or show fewer displays.

## Zoom in this window

**Local Scale**, under **Zoom**, enlarges the image in this window without changing the remote resolution or what the network carries. 100% is the whole desktop fitted to the window, the smallest it goes; 200% is the largest. **Actual Size** returns to 100% and re-centers the image.

**On Apple Vision Pro:** pinching selects rather than zooms. Use **Local Scale**, or make the window larger.

**On Mac:** use **Local Scale**. The image zooms around its center, and scrolling always scrolls the remote desktop.

**On iPad and iPhone:** pinch on the desktop to zoom between 100% and 200%. While zoomed in, drag with two fingers to move around the image; at 100%, two fingers scroll the remote desktop.

## Window size on Mac

When a new desktop window would open at its smallest size, it opens at the service's **Desktop size** instead, one point per pixel, no larger than your screen. A desktop window cannot be made smaller than 640 × 400 points.

## Reset

**Actual Size** sets zoom back to 100%. **Reset This Window** returns every setting the window keeps to **All Desktops**' settings. Neither changes the remote resolution.

**Match Window Size**, the display shown, a fixed resolution and **Local Scale** last for the session: each time a desktop opens, it starts with **Match Window Size** on, every display (or, with **A Window for Each Display**, the main display) and 100%. **Quality** and **Display Windows** are settings, kept like the window's others.
