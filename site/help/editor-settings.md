# Editor Settings

The Editor has three settings — text size, line numbers and line wrapping — at three levels: the Editor's defaults, a project, and a single open file. This page explains where each level is and which one wins.

## The three levels

A file's settings come from the most specific level that says something:

1. **The file** — the gear in the editor window's toolbar.
2. **The project** — **Project Settings** at the foot of the project's file list.
3. **The Editor's defaults** — **Settings ▸ Editor**.

Each level stores only what you change. Anything left on **Default** follows the level above it, so when you change the Editor's defaults, every project and file that never disagreed follows the change.

## Change the Editor's defaults

1. Open the app's Settings and choose **Editor**.
2. Under **Text**, turn **Show Line Numbers** and **Wrap Long Lines** on or off.
3. Under **Size**, use **Smaller** and **Larger** to change **Text Size**, or **Actual Size** to return to 13 pt.

These apply to every open document and to documents opened later, in every editor window. Text size ranges from 8 pt to 32 pt.

**On Mac:** you can also open Settings with ⌘, and change the default text size from the Text menu: **Increase Text Size** (⌘+), **Decrease Text Size** (⌘−) and **Actual Size** (⌘0).

## Change a project's settings

1. With the project open, choose **Project Settings** (the gear) at the foot of its file list.
2. Under **Text**, choose **Default**, **Show** or **Hide** for **Line Numbers**, and **Default**, **Wrap** or **Don't Wrap** for **Wrap Long Lines**.
3. Use **Smaller** and **Larger** for **Text Size**, or **Default** to follow the Editor's size again.
4. Choose **Done**.

The text changes as you choose. A project's settings are stored with the project in the **Projects** list, so they follow the project to your other devices.

The same sheet is where you rename the project and choose **Refresh Files**.

## Change one file's settings

1. With the file in front, choose **Text Settings** (the gear in the toolbar).
2. Choose the same controls as for a project.
3. Choose **Done**.

A file's settings last while the file is open. When you close it, it goes back to following its project or the Editor's defaults.

The footer of each sheet says what **Default** follows: **the editor's defaults**, or the project's settings when the project has its own.

If no file is open, the toolbar gear shows the project's settings instead.

> [!TIP]
> A file with a line longer than 100,000 characters — typically a minified or exported file — opens with wrapping turned on for that file, because laying out such a line unwrapped is very slow. You can turn it off in **Text Settings**.

## Appearance

The Editor's colors follow the system's light or dark appearance. There is no separate setting for them.
