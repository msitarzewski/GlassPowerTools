# 2026-10-19 — A paste of wrapped text is joined again

**Objective.** Copying a reply from Claude Code or Codex brings a newline wherever the window ended,
and the terminal sends each newline as Return. The owner, 2026-10-19: "Can we reliably (and
algorithmically) detect and fix that? … We recognize the pattern and (persisted with a checkbox in
that modal) automatically repair the text." He gave an example: three lines at 134 columns, the second
padded to the margin.
**Owner.** The coordinating agent. **Authorization:** the request; local work only. Committing waits
for his "commit".

## How it's detected (`Sources/GlassTerminal/TerminalWrappedPaste.swift`)

A break is joined only when three tests all hold:
1. **A width.** The text's widest line, trailing spaces counted, is at least 40 columns. The width is
   counted in terminal columns: two for wide CJK characters and emoji, none for combining marks.
2. **The wrap rule.** The line, a space and the next line's first word are wider than that width. A
   greedy wrapper breaks only there.
3. **The hanging indent.** The next line starts exactly under the first line's text, past its indent
   and its bullet ("• ", "⏺ ", "⎿  ", "- ", "12. "), and doesn't start an item of its own.

**Never joined:**
- a line with neither indent nor bullet, which is how commands look;
- across a blank line;
- inside a code fence;
- at a table's border (box drawing, "|");
- after a line ending in `\`.

**Other rules:**
- A copy that began inside a paragraph, past its indent, takes the next line's indent and counts it
  back for the wrap rule.
- A link broken at the margin is joined without a space.
- Joined text loses its lines' trailing spaces.

**Known limit:** two lines under a bullet where the first is the widest in the paste always look
wrapped, because the width can only be read from the widest line. The review shows the result, and
the checkbox puts the lines back.

## Where it shows (`Sources/GlassTerminal/TerminalPasteReviewSheet.swift`)

- **One sheet now.** The connection terminal's review (it was private in `TerminalWindowView.swift`)
  and the Mac local shell's (`MacTerminalPasteReviewSheet`) differed only in wording.
- **The checkbox.** "Join Wrapped Lines" appears only when the paste looks wrapped. A line under it
  says the width and the line count ("Joined, 3 lines become 1").
- **Its setting.** It's `SettingsManager.joinsWrappedPastes`: on by default, remembered on this
  device, and outside the portable iCloud preferences.
- **Turning it on or off** replaces the editor's text with the joined or the original text, so any
  edit made in between is lost.
- **The review still appears.** Joining doesn't skip the review; the owner may want the sheet skipped
  when the joined text is a single line. That's offered, not built.

## Validation

- `TerminalWrappedPasteTests` (14 tests, 33 cases), all passing:
  - the owner's example becomes his one line;
  - wrapped at 48, 72, 80 and 134 columns, under six bullets and indents, a paragraph comes back
    whole;
  - paragraphs and list items stay apart, and a copy begun mid-paragraph is joined;
  - lines short of the margin, commands, `\`, fences, tables and anything under 40 columns aren't
    joined;
  - a broken link joins without a space;
  - widths, CRLF and a final newline are handled.
- `PortableSettingsSyncTests`: the setting is on by default, persists, and doesn't travel. Passing.
- `UITests/TerminalPasteUITests` (iOS) pastes the example into the demo terminal with ⌘V and checks:
  - the checkbox is on and the text is one line;
  - off brings back three lines;
  - the next paste opens with it off.
  - The run results, with and without the change, are below.
