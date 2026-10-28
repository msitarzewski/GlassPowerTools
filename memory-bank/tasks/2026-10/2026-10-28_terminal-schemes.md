# 2026-10-28 — Terminal color schemes from Terminal profiles, first class (D90)

## Objective and authorization
The owner, 2026-10-28, with a zip of 148 macOS Terminal profiles from a user: "Let's make these work, first class style!
It's a user request." Then: "Highlight colors, etc. I don't think we have highlight/text customization on the 'looks'
we built." The request authorizes the feature, its tests and builds for his devices. Not committed until he says so.

## What there was (reused)
- `TerminalTheme` already carries text, cursor, selection (the highlight), background and the sixteen; the Themes
  editor (`ThemeEditorView`) edits all of them on every device. The looks (D84) sit over the theme: backdrops, glow,
  phosphor palettes.
- `TerminalThemeImportService` (from glas.sh): Mac only (`NSKeyedUnarchiver` + `NSColor`), one file at a time from
  the Themes editor, the profile's background dropped (only its light/dark kept), into the synced theme library,
  which holds at most 64 themes in one iCloud key-value entry (384 KB) beside workgroups, projects and favorites
  under iCloud's 1 MB per app. 148 don't fit, and growing that entry risks the others.

## Built (0.4.546)
- **`TerminalProfileReader`** (all platforms): the profile's property list, and each archived `NSColor`/`NSFont`
  read by a class of its own (`NSKeyedUnarchiver.setClass`, secure coding): calibrated RGB/white as Generic RGB/Gray
  (by name: Swift hides the constants), device as sRGB, a colour with its own ICC profile from it; out-of-range
  numbers refused (CoreGraphics would clamp them silently). Nothing else in a profile is read. Errors say the fix.
  `TerminalThemeImportService` is now a thin wrapper on it, on every device.
- **Checked against AppKit:** every colour of the 148 schemes and Apple's 12 profiles (3,189) equals `NSColor`'s sRGB
  exactly (a throwaway test, removed); the committed test does Apple's profiles on any Mac.
- **A scheme comes in whole:** background (now honored; the window's opacity still says how much shows), text,
  selection, cursor (follows the text when the profile has none), the sixteen (Clear Dark's when it has none, as
  Terminal does); the canvas's light/dark from its background. Its font isn't taken: schemes are colours, your font
  stays (the Themes editor's import still takes a profile's font; Apple's SF Mono Terminal is SF Mono). Its bold
  colour is read but not drawn: SwiftTerm draws bold in the text's colour or bright, with no bold colour.
- **`TerminalSchemeLibrary`**: iCloud Drive ▸ Glass Power Tools ▸ Terminal Themes (`Documents/Terminal Themes`, every
  platform; this device's Application Support without iCloud Drive), watched like the Focus environments, every file
  fetched (a few KB each), read off the main thread and cached by modification date. Import copies profiles, or a
  folder's, each read first; the same name again replaces it (the identifier stays). Delete removes the file
  everywhere.
- **Identifiers:** a name-based UUID from the file's name (SHA-256, NFC first, so a Finder-decomposed name matches),
  the same on every device. A window stores it as its theme (`terminal.theme`, a UUID as before, so older builds keep
  it and draw All Terminals'); All Terminals' choice is `SettingsManager.terminalScheme`, synced as
  `ICloudPortableTerminalPreferences.terminalScheme` (empty for your theme; absent from older devices, which leaves
  it be). `allTerminalsTheme` is the scheme in your theme's font while this device has it, else your theme; the
  window profile, Settings and This Window read it.
- **Choose Theme** (`TerminalThemeChooserView`, Settings ▸ Terminal ▸ Theme ▸ Choose…): your themes and the schemes,
  each drawn small in its colours (background, a prompt, a highlighted word, the sixteen), search, Import… (files or
  folders, every platform), and per scheme Copy to Your Themes (to edit its colours) and Delete…. Choosing a theme
  of yours, or saving the Themes editor, clears the scheme. This Window's picker lists the schemes in a section.
- **Opened with the app** (Open With on the Mac, AirDrop, Files): `GlassWidgetRequest.importTerminalThemes`; the Info.plist
  declares `com.apple.terminal.settings` (imported type, so iPhone and Vision Pro know `.terminal`) and the app as an
  Alternate viewer. One file becomes All Terminals' scheme; a Mac selection of many comes in as one import with one
  summary alert.
- **Found on the way:** Settings ▸ Theme had Choose… and Edit Theme in one form row; on iPhone and Vision Pro a tap there
  pressed both (the editor opened behind the chooser). Each is its own button now (`.borderless`).

## Validation
- Unit: `TerminalProfileReaderTests` (6), `TerminalSchemeLibraryTests` (5), `GlassOpenedURLTests` +1, the importer's
  older tests updated for the honoured background; terminal 1054, widget data 25. Seen failing with: calibrated read
  as sRGB, the background dropped, names not composed, windows ignoring schemes, re-import not replacing, the
  opened-file route removed.
- UI (visionOS simulator, `--demo-terminal-schemes` writes three profiles and imports their folder):
  `TerminalSchemesUITests.testAnImportedSchemeIsChosenForAllTerminals` — listed, read, chosen (marked), Settings names
  it, back to Glass Terminal, This Window offers them and takes one. Fails with choosing disabled and with This
  Window's section removed. Captured: the chooser's rows in their colours; the terminal behind turned Demo Paper.
- Not seen: the headset, the iPhone, the Mac's chooser; Open With and AirDrop (built, not exercised); the 148 in iCloud.
