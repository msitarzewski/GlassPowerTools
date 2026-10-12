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

A computer with several displays sends one image covering all of them. When it says where each display sits in that image, a **Displays** section appears in **This Window**:

- **Show** chooses what this window shows: **All Displays**, **Main Display** or another display. A single display fills the window.
- **Open … in a New Window**, one for each display (for example **Open Display 2 in a New Window**), opens that display in a window of its own, on Apple Vision Pro, Mac and iPad. Each window has its own display, zoom, tilt and settings, and the pointer and keys go to the display of the window you use. All of a desktop's windows share one connection.
- **Display Windows**: **A Window for Each Display** opens one window per display whenever the desktop connects; **One Window** keeps them together. It starts as **A Window for Each Display** on Apple Vision Pro and **One Window** elsewhere, and can be set in **Settings** > **Desktops**, or for one desktop in **Desktop Settings** > **Connection**.

**Screen Sharing (VNC):** the computer is asked only for the displays that have a window on screen. A display whose window is closed or in the background costs nothing on the network, and its picture is fetched again when its window returns. Closing a display's window leaves the others connected; closing the last ends the session.

While a VNC computer has several displays, the app does not change its resolution: **Match Window Size** and **Desktop Resolution** are unavailable, because one desktop the size of a window would fold its displays into one.

If the computer does not say where its displays are, the window shows them as one picture and the **Displays** section does not appear.

**From a Mac:** the app asks every Mac where its displays are, and a Mac answers again whenever they change: when someone signs in, locks the screen, switches user, or adds, removes or rearranges a display. Each display's window then shows that display. A Retina display is sent at 1x unless you choose otherwise; see [Retina displays from a Mac](#retina-displays-from-a-mac). Displays that mirror each other are one display here.

**The pointer from a Mac:** the app asks a Mac where its pointer is and for the pointer's shapes, as Apple's own Screen Sharing does. The pointer is drawn in whichever window shows the display it is on, also when it was moved at the Mac, and at the size the Mac shows it. When the Mac hides its pointer while you type, it comes back as soon as you move it. If a Mac ends the session in a way that suggests the app misread its pointer, the message says so and **Reconnect** connects without asking: the pointer is then drawn where you last put it, until the app is opened again.

If a Mac ends the session in a way that suggests the app misread its displays, the message says so and **Reconnect** connects without asking: the displays are one picture again until the app is opened again.

## Quality and the network (Screen Sharing)

**Quality**, in **Desktop Settings** > **Connection**, chooses how much picture a VNC connection carries. It belongs to the connection, so it applies to every window of the desktop. To choose it for every desktop, use **Settings** > **Desktops**, under **Screen Sharing (VNC)**.

| Quality | What the computer is asked to send |
|---|---|
| **Automatic** (default) | Measures the connection and moves between the levels below as it changes: down quickly when the link is slow, or when the picture starts to arrive late because data is waiting in the network, as on a phone's hotspot; up slowly once pictures arrive in time again. From a Mac it goes no higher than **Balanced**. |
| **Best** | Every pixel exactly, in full color, as fast as the connection allows. |
| **Balanced** | Full color, with photos and video compressed as JPEG where the computer offers it. |
| **Data Saver** | Thousands of colors, stronger compression and JPEG, at most 15 updates a second. A Mac sends its picture at three quarters of its size. |
| **Lowest** | The strongest compression and JPEG, at most 8 updates a second; 256 colors where the computer does not send JPEG. A Mac sends its picture at half its size. |

A Mac's Screen Sharing has not been seen to send JPEG to apps other than Apple's own, so on a Mac the levels work through the size of the picture, colors, compression and how often the picture is asked for. They never go below thousands of colors there: older versions of macOS ended the session when asked for fewer. On a Mac, **Best** and **Balanced** send the same.

**A smaller picture from a Mac.** At **Data Saver** and **Lowest** the Mac draws its picture smaller before sending it: at three quarters of its size each update carries a little over half the pixels, and at half its size a quarter of them. The window still fills with the picture, so text is softer; a Retina display at half its size is about as sharp as a standard display. Pointing, clicking and dragging land where you point, at any size. The size changes once the Mac has confirmed it, which takes a moment, and the picture is fetched again in full. If a Mac ends the session while it is being asked for a smaller picture, the message says so and **Reconnect** connects without asking: it sends its own size until the app is opened again.

On the **Connection** page, under **Quality**, the figures show what the network is carrying now, updated every second: **Receiving** (for example `1.2 Mbit/s`), **Updates** per second, the **Level** in effect (with **Automatic**, the level it chose), **Color**, **Scale** (on a Mac: the size it is sending, `100%` at its own size), the **Encoding** the computer is using, **Round trip** (how long the network takes to answer, for example `42 ms`, and how much of that is data waiting in the network), and **Fetching** (the whole desktop, only the displays on screen, or nothing). On Mac, iPad and iPhone the bar at the bottom of the window shows the main figures in one line, for example `1.2 Mbit/s · 14 updates/s · 16-bit color · ZRLE · 75% size`, the last while a Mac sends a smaller picture.

Zooming or shrinking the picture in the window does not change what the network carries: the computer sends its own pixels either way. To send fewer pixels, lower the remote resolution, show fewer displays, or, from a Mac, keep **Retina Displays** at **Send at 1x** or choose **Data Saver** or **Lowest**.

## Retina displays from a Mac

**Retina Displays**, in **Desktop Settings** > **Connection** under **Quality**, chooses how a Mac sends a Retina display:

- **Send at 1x (Recommended)**, the default: one pixel for each of the Mac's points, which is half a Retina display's pixels across and half down, so each update carries a quarter of the pixels. Text looks as it does on a standard display. **Quality**'s own reduction comes on top: at **Data Saver** a Retina display arrives at three eighths of its pixels across, and at **Lowest** at a quarter.
- **Native 2x**: every pixel of the Retina display, four times as many, for the sharpest picture on a fast connection.

A standard display is sent at its own pixels either way. Like **Quality**, this belongs to the connection, so it applies to every window of the desktop, and it can be set for every desktop in **Settings** > **Desktops**.

A Mac draws its whole picture at one scale, and all of a desktop's windows share one connection, so a Retina display and a standard display cannot both arrive at 1x. While a Mac has both on screen, each arrives at its own pixels, as Apple's own Screen Sharing app shows them; **Send at 1x** applies while only Retina displays are on screen.

Under **Windows**, the **Connection** page lists each window of the desktop and what it is being sent: its size in pixels and how many pixels for each of the Mac's points, for example `1512 × 982 at 1x (50%)`. On Mac, iPad and iPhone the same appears in the bar at the bottom of the window.

## High Performance from a Mac (experimental)

**Mac Screen Sharing**, in **Desktop Settings** > **Connection** under **Quality**, chooses how a Mac shares its screen:

- **Standard**, the default: the Mac's own displays, as described above.
- **High Performance (Experimental)**: the fast mode Apple's own Screen Sharing app offers. The Mac moves its windows to a virtual display the size of this window, at your screen's density, and sends it as video, with its sound. The Mac stops playing sound itself meanwhile. It adapts the video between 20 and 60 Mbit/s; **Data Saver** holds it to 8 and **Lowest** to 3.

High Performance needs macOS 14 or later on a Mac with Apple silicon, a **Mac user name** and password for the connection, not only a VNC password, and UDP between this device and the Mac on ports 5900 and 5901. It takes effect the next time the desktop connects. While it runs, **High Performance** under **Quality** says what it is doing: **Starting…**, **Streaming**, or **Restarting after a display change…**. When the Mac or the connection can't use it, the desktop connects in **Standard** and the same line says why. A device that can't decode the Mac's video connects in **Standard** too, and says so.

Like **Quality**, it belongs to the connection, and it can be set for every desktop in **Settings** > **Desktops**.

## Keep a window in its display's shape

**Keep Display Proportions**, in **Desktop Settings** > **This Window** under **Remote Desktop**, lets a desktop window be resized only in the shape of the display it shows, so the picture fills it with no bars at the sides or top. It is on unless you turn it off, on Apple Vision Pro and Mac. The window takes the display's shape as soon as the picture arrives, keeping its width, and again whenever you show another display or the computer's displays change.

While **Match Window Size** is changing the remote computer's resolution to fit the window, the window can take any shape and the desktop follows it instead. A Mac never changes its resolution to fit a window, so a Mac's windows always keep their display's shape.

Turn it off to give a window any shape, for example to zoom into part of a display with **Local Scale**. Set in **This Window** it is that window's own; in **All Desktops** (the same as **Settings** > **Desktops**) it is every desktop window's that hasn't set its own. On iPad and iPhone a window's shape cannot be held, and the setting does not appear.

## Zoom in this window

**Local Scale**, under **Zoom**, enlarges the image in this window without changing the remote resolution or what the network carries. 100% is the whole desktop fitted to the window, the smallest it goes; 200% is the largest. **Actual Size** returns to 100% and re-centers the image.

**On Apple Vision Pro:** pinching selects rather than zooms. Use **Local Scale**, or make the window larger.

**On Mac:** use **Local Scale**. The image zooms around its center, and scrolling always scrolls the remote desktop.

**On iPad and iPhone:** pinch on the desktop to zoom between 100% and 200%. While zoomed in, drag with two fingers to move around the image; at 100%, two fingers scroll the remote desktop.

## Window size on Mac

When a new desktop window would open at its smallest size, it opens at the service's **Desktop size** instead, one point per pixel, no larger than your screen. A desktop window cannot be made smaller than 640 × 400 points. With **Keep Display Proportions** on, the window then takes the shape of the display it shows, and keeps it as you resize it.

## Reset

**Actual Size** sets zoom back to 100%. **Reset This Window** returns every setting the window keeps to **All Desktops**' settings. Neither changes the remote resolution.

**Match Window Size**, the display shown, a fixed resolution and **Local Scale** last for the session: each time a desktop opens, it starts with **Match Window Size** on, every display (or, with **A Window for Each Display**, the main display) and 100%. **Quality**, **Retina Displays**, **Mac Screen Sharing**, **Display Windows** and **Keep Display Proportions** are settings, kept like the window's others.
