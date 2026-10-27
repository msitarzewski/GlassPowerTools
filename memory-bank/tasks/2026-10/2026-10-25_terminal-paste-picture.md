# 2026-10-25 — A picture pasted in a terminal goes to the machine

## Objective and authorization
The owner, on Vision Pro: "please make sure that paste into the terminal on visionOS works as expected. I tried to
paste an image but it didn't paste." His request authorizes the fix, its tests and a build for his devices.

## Cause
The UIKit terminal's `paste(_:)` (`Sources/GlassTerminalEmulator/SwiftTermHostView.swift`, `ReviewingTerminalView`)
read `UIPasteboard.general.string` and nothing else. A picture on the clipboard has no string, so a paste did nothing
and said nothing. The same view is used on iPhone and iPad. A Mac pane reads `NSPasteboard` text only too; it was not
asked about and is unchanged.

## Reuse
A dropped picture already goes to the host and has its path typed (W14, `TerminalRemoteDrops`,
`TerminalRemoteDrop.swift`): verified no-clobber upload into `~/.cache/glass-power-tools/dropped/<day>/`,
HEIC to JPEG, escaped paths typed as a paste. A paste now uses that pipeline instead of a second one.

## Built
- `SwiftTermHostModel.pasteFiles`: asked first on a paste; true when the clipboard held pictures or files.
- `ReviewingTerminalView.paste`: calls it, then types text as before; logs `terminal-paste event=paste`.
- `SFTPIncomingDrop(pasted:)`: keeps the clipboard items that are files (`isPastedFile`):
  - a picture, whatever else the item carries;
  - otherwise one file with no text beside it (a PDF);
  - text, web links and undeclared types stay text.
  A pasted item is read for its content, never a file URL it names. A nameless picture goes up as `Pasted.<ext>`.
  Any item offering a picture is read as the picture (`fileType(in:)`), drops included.
- `TerminalRemoteDrops.receive(pasted:on:insert:)`: logs the clipboard's kinds (never contents) as `paste-text` or
  `paste-files`; a picture on a disconnected terminal says so rather than falling through to text.
- `TerminalWindowView` (not Mac) sets the hook from `UIPasteboard.general.itemProviders`.
- Wording: the retry messages said "drop again"; they now say "try again", true of both.

## Validation
- `TerminalRemoteDropTests` 13 (2 new) and `TerminalDropTypingTests` pass. The new ones failed when the picture was
  not preferred, when a picture with text was taken as text, and when a disconnected paste fell through to text
  (each seen, source restored byte for byte).
- `TerminalPasteUITests.testAPictureIsSentToTheMachine` (new, visionOS and iOS): a PNG on the clipboard, Paste from
  the terminal's menu; the demo terminal has no SFTP channel, so it shows "Couldn't upload Pasted.png: the
  connection ended. Reconnect, then try again." Passes on the visionOS simulator and fails there with the hook
  removed; passes on the iPhone simulator with `testAWrappedReplyIsJoinedWhenPasted` (text paste unchanged).
- The simulator log read the clipboard as `public.png` and sent it to the upload.
- ⌘V from the runner's synthesized keyboard never reached the terminal's `paste` on the visionOS simulator (nothing
  logged), though SwiftTerm leaves ⌘ keys to UIKit. The test uses the menu; a real keyboard's ⌘V is the owner's to
  try on the headset.
- 0.4.526 installed on the Mac, iPhone and Vision Pro (versions read back; no new crash report).
- Not yet tried on the headset or against a real host from a paste; the upload itself is the W14 path the iPhone
  proved with a photo dropped from Photos.

## Open
- A Mac SSH pane still pastes text only.
- Copied rich text whose items include a picture would paste the picture: no case seen.
