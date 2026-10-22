# Backgrounds and glowing text

A terminal window can have a look of its own: a picture or a moving background behind its text, the text in one phosphor's colours, and a glow around it. This page covers choosing a look, each background, the text's palette and glow, and keeping the text readable.

A look belongs to one window and is one of its own settings, so it is set in **This Window**: in any tab of the window, open the tools menu and choose **Settings**. **On Mac, iPad and Vision Pro** only; iPhone has no **This Window**. See [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings).

A Workgroup can have a look too, which every window it opens starts with, on every device, iPhone included: set it under **Look** and **Text** when you create or edit the Workgroup (see [Save and open terminal Workgroups](terminal-workgroups.md#create-a-workgroup)).

## Start from a look

Under **Look**, choose **Start From** ▸ **Choose a Look**, then one of:

- **Coding Agent**: the coding agent each terminal is running, with the text glowing in that agent's colour (see [The coding agent](#the-coding-agent)).
- **Digital Rain**: falling columns of green glyphs, with the text in **Digital Green** and a glow.
- **Synthwave**: a sunset over a grid that rolls toward you, with the text in **Vaporwave** and a pink glow.
- **Aurora**: curtains of northern light drifting across the window, with a cyan glow.
- **Starfield**: stars coming toward you, with a soft glow.
- **Amber Phosphor** and **Green Phosphor**: a phosphor screen, with the text in that phosphor's colour and a glow.
- **Blueprint**: a drafting sheet, a fine grid on deep blue, with the text in **Blueprint** white.
- **None**: takes the look away.

Each sets the whole look at once, in place of the window's own, and you can change any part of it afterwards. A picture you chose for the window stays chosen, so going back to **Picture** finds it.

## The background

**Background** chooses what is drawn behind the text of every tab in the window:

- **None**, the starting setting: the window's canvas and glass, as always.
- **Picture**: a picture of your own (below).
- **Coding Agent**: the coding agent running in each terminal (below).
- **Digital Rain**: falling columns of glyphs. With **Quicken with Output** on (the starting setting), they fall faster while a terminal in the window prints.
- **Synthwave**: a sunset over a rolling grid.
- **Aurora**: curtains of northern light. With **Quicken with Output** on, they drift faster while a terminal prints.
- **Starfield**: stars coming toward you. With **Quicken with Output** on, they stretch into streaks while a terminal prints.
- **Phosphor Screen**: a glow in the text's colour, darker at the edges, with scanlines.
- **Blueprint**: a fine grid on deep blue, with a bolder line every fifth. It never moves.

**Intensity**, from **Faint** to **Strong**, sets how strongly it shows. The window's own **Opacity** and **Glass** still show through around it.

Moving backgrounds stay still with **Reduce Motion** or **Low Power Mode** on, and while the app is in the background. In a window that isn't in front they move more slowly.

### The coding agent

With **Coding Agent** as the **Background**, each terminal shows the coding agent running in it, such as Claude Code, Codex or Gemini CLI: its mark, large and faint behind the text, in the agent's own colour. The agent is recognized the same way **Show All Windows** recognizes it on a Mac.

- **While the agent works**, and the terminal prints, a smoke of its colour drifts behind the text and the mark breathes.
- **When the agent stops and waits for you**, the smoke thins and stops, and the mark holds still and glows. In a window of several terminals, the one that wants you is the one that has gone quiet and bright.
- **With no agent running**, nothing is drawn behind that terminal's text.

Agents without a colour of their own show in the text's colour. **Glow Color** ▸ **Coding Agent's Color** makes the text glow in the agent's colour too.

### A picture

1. Choose **Picture** as the **Background**.
2. Drop a picture on the well under it, or choose **Choose…** and pick one.

Then:

- **Blur**, from **Sharp** to **Soft**. It softens the picture gradually: a little near **Sharp**, the picture still recognisable halfway, and fully blurred at **Soft**.
- **Pixelate**, from **Smooth** to **Blocky**.
- **Tone to Theme**, from the picture's own colours to the theme's.

**Remove** takes the picture away. The picture is kept on this device, at a size suited to a screen; a picture of 80 MB or more, or a file that isn't a picture, is refused, and the well says why.

> [!NOTE]
> Dropping a picture on a terminal still types its path, or uploads it to a server, as it always has (see [Drop files on a terminal](terminal-sessions.md#drop-files-on-a-terminal)). To make it the background, drop it on the well in **This Window**.

## Keep the text readable

**Readability**, from **Less scrim** to **More scrim**, darkens the background under the text. Wherever the background is bright enough to make the text hard to read, such as a sun in a picture, it is darkened further, there alone, so ordinary text and dimmed text both stay readable while the rest of the background keeps its brightness.

What you can select, copy and search, and what VoiceOver reads, is the same text whatever the look.

## The text

Under **Text**:

- **Text Palette**: **Theme's Own** (the starting setting), **Green Phosphor**, **Amber Phosphor**, **Digital Green**, **Vaporwave** or **Blueprint**. **Blueprint** and the three phosphors turn every colour a program draws into a shade of one colour, by its brightness, keeping a little of its own hue so red and blue still differ, and that includes programs such as `btop` that draw with millions of colours. **Vaporwave** replaces the theme's sixteen colours with neon ones; colours a program chooses beyond those sixteen keep their own.
- **Text Glow**, from **No glow** to **Strong glow**: a soft glow around the text.
- **Glow Color**, once there is a glow: **Text Color** (the starting setting), **Coding Agent's Color**, **Green**, **Amber**, **Pink**, **Cyan** or **Purple**. **Coding Agent's Color** is the colour of the agent running in each terminal, or the text's where none runs.

## Where a look applies

- Every tab in the window, local terminals on a Mac included, and a tab moved into the window takes its look.
- A look is saved with the window's other settings: it comes back after a relaunch, and **On Mac**, **Save Workspace as Workgroup…** keeps it with the Workgroup. The picture itself stays on the device where you chose it.
- A window opened from a Workgroup starts with the Workgroup's look. Changing it in **This Window** changes that window only; edit the Workgroup to change the look it opens with.
- Each part has a ↺ beside its name once set; choose it to go back to none. **Reset This Window** removes the whole look with the window's other settings.
- **On Mac**, **Show All Windows** and **Terminal Overview** show each window's look, standing still, around the pictures of its terminals.
