# Resolution, scaling and zoom

A remote desktop has two sizes: the resolution the remote computer draws at, and how large that image appears in your window. This page covers both, in **Desktop Settings** > **Display**. Open **Desktop Settings** with **Settings** (gear) in the desktop window.

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

Higher settings send more pixels over the network. A server that ignores the scale shows a smaller interface. **Detail** needs **Match Window Size** on, and your choice is remembered for every RDP desktop on this device.

## Choose a fixed resolution

Open **Desktop Resolution** and choose **1280 × 800**, **1920 × 1080**, **2560 × 1440** or **3840 × 2160**. Sizes the server does not accept are unavailable. Choosing one turns **Match Window Size** off, so resizing the window no longer changes the resolution. Turn **Match Window Size** on again to go back.

## Show one display of a multi-display computer (VNC)

When a VNC server sends one image covering several displays, a **Displays** section appears. In **Show**, choose **All Displays**, **Main Display** or another display. A single display fills the window and uses no more of the network.

## Zoom in this window

**Local Scale** enlarges the image in this window without changing the remote resolution. 100% is the whole desktop fitted to the window, the smallest it goes; 200% is the largest. **Actual Size** returns to 100% and re-centers the image.

**On Apple Vision Pro:** pinching selects rather than zooms. Use **Local Scale**, or make the window larger.

**On Mac:** use **Local Scale**. The image zooms around its center, and scrolling always scrolls the remote desktop.

**On iPad and iPhone:** pinch on the desktop to zoom between 100% and 200%. While zoomed in, drag with two fingers to move around the image; at 100%, two fingers scroll the remote desktop.

## Window size on Mac

When a new desktop window would open at its smallest size, it opens at the service's **Desktop size** instead, one point per pixel, no larger than your screen. A desktop window cannot be made smaller than 640 × 400 points.

## Reset

**Reset Presentation** sets zoom back to 100% and presentation back to **Original**. It does not change the remote resolution.
