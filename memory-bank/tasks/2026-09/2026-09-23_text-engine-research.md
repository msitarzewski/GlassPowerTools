# Text engine research — why the state of the art is faster, 2026-09-23

The user asked why established Mac text editors open and scroll a huge file so much faster than
ours, and what we could learn without using their code. The state of the art in native Mac editors
was researched — read for approach, nothing copied — and the difference measured here.

## What the fast editors do

- **TextKit 1 for the editing surface**, with **non-contiguous layout** (`NSLayoutManager.
  allowsNonContiguousLayout = true`): lay out only what is shown, even inside one enormous line.
- **Syntax colour as layout-manager temporary attributes**, never in the text storage, so a
  highlight pass changes no characters and invalidates no layout.
- **Highlighting off the main thread, by range**: invalid ranges collected, a short debounce, a
  copy parsed in the background, only the returned range applied; the first pass colours the
  opening few thousand characters, then the rest.

## Measured here (the user's 14.6 MB one-line SVG)

Bare AppKit text views, none of our code (`TextKitComparisonTests`, release, offscreen):

| Engine | Open + layout | Scroll median | Frames over 16.7 ms |
|---|---|---|---|
| TextKit 1, non-contiguous, wrapped | 0.30 s | < 0.1 ms | 0 / 200 |
| TextKit 2, wrapped | 0.98 s | 30 ms | 200 / 200 |
| TextKit 1, non-contiguous, unwrapped | 0.20 s | < 0.1 ms | 0 / 200 |

In real windows with real scroll-wheel events (the user away): a throwaway TextKit 1 app scrolled
the logo through its base64; a TextKit 2 one had not shown its window after 7 s; **our editor
(TextKit 2, 0.4.216) took ~5 s to open the logo and did not move under 300 scroll events** — ~90 % of
main-thread samples drawing wrapped pieces of the one paragraph. An ordinary 10,000-line file
scrolls in our editor after today's finite-container fix.

## Why

TextKit 2's unit is the paragraph: a 14.6 M-character line is one layout fragment, and per frame
TextKit 2 re-measures content height across all its line fragments and walks the paragraph's
attributes to draw each wrapped piece. TextKit 1's non-contiguous layout works below the paragraph.

## Against our own record

The engine's D-001 (`../GlassEditorKit/memory-bank/decisions.md`) chose TextKit 2 for transparency,
with reversal criteria and a `GlassEditorEngine` protocol "partly to make reversal cheap". Large-file
performance was not among the criteria. TextKit 1 draws over a clear background too, so
transparency alone does not force TextKit 2 on the Mac. **D36 — approved by the user 2026-09-23
("Let's test it … build the new editor").**

## Built — D36, 2026-09-23 (0.4.217, uncommitted)

`GlassTextView.makeTextKit1()`: `NSTextStorage` → `NSLayoutManager` (`allowsNonContiguousLayout`)
→ `NSTextContainer`; `textSystem` fixed at construction; `glassTextStorage` the one storage accessor;
`assertOnItsTextSystem()` the per-system tripwire. `GlassEditorAppKitEngine(model:textSystem:)`
defaults to `.textKit1`. The gutter: `GlassLineNumberGutter.labels(for:model:verticalRange:)`
dispatches; `textKit1Labels` asks the layout manager for the band's glyphs only and numbers a line
fragment only where it starts a logical line; the extra line fragment is the trailing empty line.
`GutterLineNumbers.draw(_:in:offsetY:model:)` draws for both. Colours still go through the text
storage (not yet temporary attributes). iOS/visionOS (UIKit) unchanged, on TextKit 2.

Tests: every gutter test in `AppKitEngineTests` runs on **both** systems through the gutter's own
label function (a TextKit 2-only helper had been returning `[]` on a TextKit 1 view — silent
passes); the pen tests' lookup counter reaches the TextKit 1 path. 113 editor-UI tests pass.

| The user's 14.6 MB SVG in the running app | TextKit 2 (0.4.216) | TextKit 1 (0.4.217) |
|---|---|---|
| window appears | ~5 s | 1.9 s |
| main thread busy while scrolling | ~90 %, did not move | 25 %, scrolled into the base64 |
| ordinary 10,000-line file, busy while scrolling | 65 % | 50 % |

Open: re-wrapping the logo after a resize takes ~1.7 s offscreen; colours as temporary attributes
and background highlighting (the fast editors' other practices); iPad and Vision Pro not measured.

