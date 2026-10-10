# Editor Settings

The Editor has three settings — text size, line numbers and line wrapping — at four levels: the Editor's defaults, an editor window, a project, and a single open file. An editor window can also keep its own glass. This page explains where each level is and which one wins.

## The four levels

A file's settings come from the most specific level that says something:

1. **The file** — **This File** in the editor window's **Settings** (the gear in its toolbar).
2. **The project** — **Project Settings** at the foot of the project's file list.
3. **The window** — **This Window** in the editor window's **Settings**.
4. **The Editor's defaults** — **Settings ▸ Editor**, also shown as **All Editors** in an editor window's **Settings**.

Each level stores only what you change. Anything left on **Default**, or that a window hasn't changed, follows the level above it, so when you change the Editor's defaults, every window, project and file that never disagreed follows the change.

**On iPhone:** there are no windows, so there is no **This Window** level, and **Settings** opens on **This File**.

## Change the Editor's defaults

1. Open the app's Settings and choose **Editor**.
2. Under **Text**, turn **Show Line Numbers** and **Wrap Long Lines** on or off.
3. Under **Size**, use **Smaller** and **Larger** to change **Text Size**, or **Actual Size** to return to 13 pt.

These apply to every open document and to documents opened later, in every editor window that doesn't keep its own. Text size ranges from 8 pt to 32 pt. The same controls are under **All Editors** in an editor window's **Settings**.

**On Mac:** you can also open Settings with ⌘, and change the default text size from the Text menu: **Increase Text Size** (⌘+), **Decrease Text Size** (⌘−) and **Actual Size** (⌘0). In a window that keeps its own **Text Size**, these change that window's size instead.

## Give an editor window its own settings

1. In the editor window, choose **Settings** (the gear in the toolbar). It opens on **This Window**.
2. Under **Appearance**, change **Opacity**, **Glass** and **Material**.
3. Under **Text**, change **Text Size**, **Show Line Numbers** and **Wrap Long Lines**.
4. Choose **Done**.

Each setting follows **All Editors** (or **Appearance**) until you change it here. Once you do, a small ↺ appears beside its name; choose it to follow again. Its tooltip says what it returns to: hold the pointer over it, or on Vision Pro look at it. **Reset This Window**, at the end, returns every one. Every document in the window changes at once. A project's or a file's own text settings still apply over the window's.

**On Apple Vision Pro:** the gear is in the row of controls below the window, and **Appearance** has **Opacity** only. A Vision Pro window's glass is the system's own, so an editor window has no **Glass** or **Material** of its own there.

The window keeps its settings with its project, on this device. Close the window and open the project again — after quitting the app too — and they're back. They don't sync to your other devices: the Editor's defaults and **Appearance** they stand in for are kept on each device too, and a project's own settings are what travel with it. A window with no project keeps its settings until you close it.

## Change a project's settings

1. With the project open, choose **Project Settings** (the gear) at the foot of its file list.
2. Under **Text**, choose **Default**, **Show** or **Hide** for **Line Numbers**, and **Default**, **Wrap** or **Don't Wrap** for **Wrap Long Lines**.
3. Use **Smaller** and **Larger** for **Text Size**, or **Default** to follow the window's or the Editor's size again.
4. Choose **Done**.

The text changes as you choose. A project's settings are stored with the project in the **Projects** list, so they follow the project to your other devices.

The same sheet is where you rename the project and choose **Refresh Files**.

## Change one file's settings

1. With the file in front, choose **Settings** (the gear in the toolbar), then **This File**.
2. Choose the same controls as for a project.
3. Choose **Done**.

A file's settings last while the file is open. When you close it, it goes back to following its project, its window or the Editor's defaults.

The footer of each section says what **Default** follows: **the editor's defaults**, **this window's settings** when the window keeps its own text settings, or the project's settings when the project has its own.

If no file is open, the section is **This Project** and shows the project's settings instead.

> [!TIP]
> A file with a line longer than 100,000 characters — typically a minified or exported file — opens with wrapping turned on for that file, because laying out such a line unwrapped is very slow. You can turn it off in **This File**.

## Appearance

The Editor's colors follow the system's light or dark appearance. There is no separate setting for them, for every window or for one.
