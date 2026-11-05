# Languages, Find and the Status Bar

The Editor colors code with a grammar for each supported language. This page lists the languages, explains how a file's language is chosen and changed, and covers the status bar, Go to Line, and Find and Replace.

## Supported languages

| Language | Chosen for these file extensions |
|---|---|
| C | `.c`, `.h` |
| Go | `.go` |
| HTML | `.html`, `.htm`, `.xhtml`, `.vue`, `.svelte`, `.hbs`, `.handlebars`, `.ejs`, `.njk` |
| JavaScript | `.js`, `.mjs`, `.cjs`, `.jsx`, `.ts`, `.tsx`, `.mts`, `.cts` |
| JSON | `.json`, `.jsonc`, `.geojson`, `.webmanifest` |
| Markdown | `.md`, `.markdown`, `.mdown` |
| PHP | `.php`, `.phtml` |
| Python | `.py`, `.pyw`, `.pyi` |
| Rust | `.rs` |
| Shell | `.sh`, `.bash`, `.zsh` |
| SQL | `.sql`, `.mysql`, `.ddl` |
| Swift | `.swift` |
| TOML | `.toml` |
| XML | `.xml`, `.plist`, `.svg`, `.xib`, `.storyboard`, `.xcscheme`, `.entitlements`, `.xsd`, `.xsl`, `.xslt`, `.rss`, `.atom`, `.pom` |
| YAML | `.yml`, `.yaml` |
| Plain Text | everything else |

TypeScript and JSX files are colored with the JavaScript grammar.

A file named only `.bashrc`, `.zshrc` or `.profile` has no extension, so its language comes from its contents, as below: it is Plain Text unless it starts with a `#!` line. Choose **Shell** from the status bar to color it.

## How a file's language is chosen

The file's extension decides first. When the extension says nothing — a `Makefile`, a script named `deploy`, a file with no extension — the Editor looks at the start of the file:

- A `#!` line names the language: Python, JavaScript (`node`, `deno`, `bun`), PHP, Swift or Shell. Any other interpreter is treated as Shell.
- `<!DOCTYPE html>` or `<html` means HTML. `<?xml` or another `<!DOCTYPE` means XML.
- A file that starts with `{` or `[` and reads as valid JSON is JSON.

Anything else stays Plain Text. A new, unsaved document is Plain Text until you save it with an extension.

## Change the language

1. In the status bar at the bottom of the window, choose the language name.
2. Choose a language from the menu.

The file is colored again with the new grammar straight away. The choice applies while the document is open; it does not rename the file. Choosing Markdown or HTML also gives the file **Show Preview**; see [Preview and viewers](editor-preview-and-viewers.md).

## The status bar

The status bar shows, from left to right:

- **Line** and **Column** of the cursor. Choose it to go to a line.
- The language.
- The file's line endings: **LF**, **CRLF** or **CR**. A file that mixes them shows **Mixed** with the most common one in brackets. The Editor keeps a file's line endings as they are when you save.
- **Highlighting off — large file** when a file is too large to color. Very large files (roughly two million characters or more) are shown as plain text so the Editor stays responsive.
- **On Apple Vision Pro:** the project and its folder, or the folder of a file opened on its own — what a Mac shows as the window's subtitle.
- **Edited** while there are unsaved changes.

**On iPhone and iPad:** a keyboard button at the end of the bar shows or hides the on-screen keyboard. The bar above the on-screen keyboard also has a button to hide it.

## Go to a line

1. Choose the **Line, Column** position in the status bar. **On Mac** you can also choose Text ▸ **Go to Line…** (⌥⌘L).
2. Type a line number and choose **Go**.

A number past the end of the file goes to the last line.

## Find and replace

**On Mac:** choose Edit ▸ Find ▸ **Find…** (⌘F). **On iPhone, iPad and Vision Pro:** choose **Find** (the magnifying glass) in the toolbar, or press ⌘F with a keyboard. A find bar opens above the text, ready to type in.

1. Type in **Find** and press Return, or choose the next and previous arrows. The Editor selects the match and scrolls to it, and the search wraps around the end of the document. The bar shows how many matches there are, for example **3 matches**, or **No matches**. **On Mac**, Edit ▸ Find ▸ **Find Next** (⌘G) and **Find Previous** (⇧⌘G) move between matches too, with the bar closed or open.
2. Turn on **Aa** to match case, or **.\*** to search with a regular expression. An invalid expression shows **Invalid pattern**. A regular expression that takes longer than a second is stopped, and the Editor says why; nested repeats such as `(a+)+` are the usual cause.
3. To replace, type in **Replace**. **Replace** (or Return in that field) replaces the selected match and selects the next one; **All** replaces every match and reports how many, for example **Replaced 3 matches.** Each can be undone (**Undo Replace**, **Undo Replace All**). With a regular expression, `$0` in **Replace** stands for the whole match and `$1` for the first group.
4. Choose **Done** to close the bar.

The rest of TextEdit's Find keys work too: **Find and Replace…** (⌥⌘F) opens the bar with the keyboard in **Replace**, **Use Selection for Find** (⌘E) puts the selected text in **Find**, and **Jump to Selection** (⌘J) scrolls back to the selection. On Mac they are in Edit ▸ Find. On iPad, iPhone and Vision Pro, with a keyboard, they work as keys, along with **Find Next** (⌘G), **Find Previous** (⇧⌘G), **Go to Line** (⌥⌘L) and the text size keys (⌘+, ⌘−, ⌘0); hold ⌘ on iPad to see them listed.

## The rest of the Edit menu on Mac

As in TextEdit, the Edit menu has **Paste and Match Style** (⌥⇧⌘V), and:

- **Spelling and Grammar**: **Show Spelling and Grammar** (⌘:), **Check Document Now** (⌘;), and the switches **Check Spelling While Typing**, **Check Grammar With Spelling** and **Correct Spelling Automatically**.
- **Substitutions**: **Show Substitutions**, and the switches **Smart Copy/Paste**, **Smart Quotes**, **Smart Dashes**, **Smart Links**, **Data Detectors** and **Text Replacement**.
- **Transformations**: **Make Upper Case**, **Make Lower Case** and **Capitalize**, for the selected text.
- **Speech**: **Start Speaking** and **Stop Speaking**.

**On iPad, iPhone and Vision Pro**, select text and open its menu (touch and hold, or pinch and hold on Vision Pro) for **Transformations**: **Make Upper Case**, **Make Lower Case** and **Capitalize**. The spelling and substitution switches are in **Settings ▸ Editor ▸ Spelling and Substitutions** on every device (on Mac also in the Edit menu); off the Mac they are spelling, autocorrection, smart quotes, smart dashes and smart copy/paste.

The spelling and substitution switches are off until you turn them on, because in code a straight quote is part of the language and most words aren't English. They apply to every Editor window and are remembered. They never apply to a database's SQL editor, where a smart quote would break a query.

## Text size on Mac

The Text menu also has **Increase Text Size** (⌘+), **Decrease Text Size** (⌘−) and **Actual Size** (⌘0). These change the Editor's default size for every window; in a window that keeps its own **Text Size**, they change that window's size. See [Editor settings](editor-settings.md).
