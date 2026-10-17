# Preview and Viewers

Some text files have a picture: Markdown, HTML, SVG and tables. The Editor can show that picture beside the text or on its own. Files that are not text at all — images, PDFs, video, audio and 3D models — open in a viewer instead of as text. This page covers both.

## Preview a file

Preview is available for:

- **Markdown** — rendered as GitHub-flavored Markdown, including tables and task lists. Code blocks fenced as `mermaid` are drawn as Mermaid diagrams.
- **HTML** — the page as written, for any file the Editor colors as HTML, such as `.html`, `.htm`, `.xhtml` or `.vue`.
- **SVG** — the drawing as an image.
- **CSV** and **TSV** (also `.tab`) — a table.

To show it, choose **Show Preview** in the toolbar (the eye; on Apple Vision Pro, in the row of controls below the window). The button cycles through three states:

1. **Show Preview** — the preview appears beside the text.
2. **Preview Only** — the preview replaces the text.
3. **Hide Preview** — back to the text alone.

**On iPhone:** there is no room beside the text, so the button switches between the text and the preview alone. A file with an extremely long line — such as an SVG exported as a single line — opens in its preview first, because the text view cannot draw it; choose **Hide Preview** to see the text.

The preview follows your edits, not the saved file. It redraws a moment after you stop typing.

## Diagrams with Mermaid

Write a fenced code block with the language `mermaid` in a Markdown file:

````markdown
```mermaid
graph LR
  alpha --> bravo
```
````

The preview draws the diagram in the light or dark style that matches your appearance. If a diagram has an error, the preview shows a line beginning **Mermaid:** with the reason at the end of the page.

## What a preview can load

A preview is kept to the file and its surroundings:

- Images and other files referenced with a relative path are read from the file's project, or from its folder when it has no project. For a file on a server, they are read over the same connection. Files outside that folder are not loaded.
- Nothing is loaded from the internet.
- Scripts in an HTML file do not run, and script, HTML and WebAssembly files beside it are never loaded. The only script a preview runs is the Mermaid copy built into the app, and only for Markdown. HTML written inside a Markdown file is drawn, with its scripts blocked.
- Choosing a web or email link opens it in your browser or mail app. Links with other kinds of address do nothing.

## Tables

A CSV or TSV preview is a scrolling table. When the first row looks like a header — every cell filled and none of them a number — it is used as column names. Otherwise the columns are lettered A, B, C, like a spreadsheet. Choose a column name to sort by it; choose it again to reverse the order. The table shows the first 10,000 rows and says so when the file has more.

## Images, PDFs, video and audio

A file whose contents are an image, a PDF, a video or audio opens in a viewer in its tab. The Editor decides by the file's contents first and its extension second, so a picture with the wrong extension still opens as a picture. SVG files are text and open in the Editor with a preview.

On Apple Vision Pro, iPad and iPhone:

- An image fits the tab. Pinch to zoom, up to eight times, and double-tap to switch between fitted and twice the size.
- A PDF opens in a scrolling page view.
- Video and audio open in a player.

**On Mac:** the viewer is Quick Look, with its own zoom, paging and playback controls.

A viewer is never edited or saved.

## 3D models

USDZ, USD and Reality files open in a 3D viewer in their tab. As with pictures, the Editor goes by what the file contains, so a USDZ saved under another name still opens as a model. A Reality file is known by its name.

- **On Mac, iPad and iPhone:** the whole model is framed in the tab. Drag to turn it, and scroll or pinch to move closer.
- **On iPad and iPhone:** **View in AR** opens the model in AR Quick Look, to stand it in the room around you.
- **On Apple Vision Pro:** the model stands in the window, and as the file opens, Apple's Quick Look also opens it in a volume of its own that you can walk around. **View in 3D** opens the volume again.

AR Quick Look and the Vision Pro volume take USDZ and Reality files only, so a USD file stays in its tab, without **View in AR** or **View in 3D**. A USD file written as text (it starts with `#usda`) also has **Open as Text**, to edit it in the Editor. If a model can't be shown, the tab says **Can't Show This Model** and why.

## Files that are not text

Any other binary file shows **This File Isn't Text** with its size. Choose **Open as Text** to open it in the Editor anyway.

## Large files

The Editor reads a file whole, up to 64 MB.

- **On this device:** a larger image, PDF, video, audio or 3D model still opens in its viewer, which reads it from the disk. A larger text or other file is not opened, and the message says so; open it in another app. Something that is not a file at all, such as a named pipe, is not opened either.
- **On a server:** a file larger than 64 MB can't be opened in the Editor. For an image, PDF, video, audio or 3D model file, **Download this file?** shows its size first, with **Download and View** and **Cancel**, but the file still doesn't open.
