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
| Shell | `.sh`, `.bash`, `.zsh`, `.bashrc`, `.zshrc`, `.profile` |
| SQL | `.sql`, `.mysql`, `.ddl` |
| Swift | `.swift` |
| TOML | `.toml` |
| XML | `.xml`, `.plist`, `.svg`, `.xib`, `.storyboard`, `.xcscheme`, `.entitlements`, `.xsd`, `.xsl`, `.xslt`, `.rss`, `.atom`, `.pom` |
| YAML | `.yml`, `.yaml` |
| Plain Text | everything else |

TypeScript and JSX files are colored with the JavaScript grammar.

## How a file's language is chosen

The file's extension decides first. When the extension says nothing — a `Makefile`, a script named `deploy`, a file with no extension — the Editor looks at the start of the file:

- A `#!` line names the language: Python, JavaScript (`node`, `deno`, `bun`), PHP, Swift or Shell. Any other interpreter is treated as Shell.
- `<!DOCTYPE html>` or `<html` means HTML. `<?xml` or another `<!DOCTYPE` means XML.
- A file that starts with `{` or `[` and reads as valid JSON is JSON.

Anything else stays Plain Text. A new, unsaved document is Plain Text until you save it with an extension.

## Change the language

1. In the status bar at the bottom of the window, choose the language name.
2. Choose a language from the menu.

The file is colored again with the new grammar straight away. The choice applies while the document is open; it does not rename the file.

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

**On Mac:** choose Text ▸ **Find in Document…** (⌥⌘F). A find bar opens above the text.

1. Type in **Find** and press Return, or choose the next and previous arrows. The search wraps around the end of the document. The bar shows how many matches there are.
2. Turn on **Aa** to match case, or **.\*** to search with a regular expression. An invalid expression shows **Invalid pattern**.
3. To replace, type in **Replace** and choose **All**. The Editor reports how many matches it replaced.
4. Choose **Done** to close the bar.

## Text size on Mac

The Text menu also has **Increase Text Size** (⌘+), **Decrease Text Size** (⌘−) and **Actual Size** (⌘0). These change the Editor's default size for every window; in a window that keeps its own **Text Size**, they change that window's size. See [Editor settings](editor-settings.md).
