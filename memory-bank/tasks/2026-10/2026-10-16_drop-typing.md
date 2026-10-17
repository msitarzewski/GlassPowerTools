# 2026-10-16: a screenshot dropped on a terminal "just disappears"

**State:** fixed in the code that could do it (the owner's check of his running app was never made; 0.4.467
restarts the app).

The owner (0.4.466, Mac): "Can't drag into the middle of a terminal... for some reason, with a screen shot drag. It
just disappears."

**Evidence (his Mac's log, 16:25):** the screenshot's floating thumbnail gave its file promise; the app received it
(file coordination claim granted); `screencaptureui` logged "Drag completed with copy/move" (so the thumbnail went);
the file landed in `~/Library/Caches/com.glasspowertools/Dropped/2D4379D3…/Screenshot … 4.25.05 PM.png` (only
`MacWorkspaceView.receiveDrop` writes there). Nothing was typed, and nothing was logged: every step after the copy
failed in silence. Claude Code was idle at its prompt then. Drops at 14:51 and 16:10 had typed their paths; the app
read the general pasteboard at 16:11:45 (a ⌘V).

**The likeliest cause, and the fix whatever it was:** `SwiftTermHostModel.requestPaste` turned away every paste and
drop while a review was pending (`guard pendingPasteReview == nil`), with no word. A multi-line paste whose review
sheet never showed would leave a pane refusing everything after it. Now the newest paste or drop takes the old
review's place (logged, `terminal-paste`), since a review on screen takes the keys and its window no drops.
`insertDroppedText` says what became of the text (typed, awaiting review, no terminal, refused); the Mac pane's drop
logs every step (`sh.glas` / `terminal-drop`: types, files received, typed or why not) and beeps when nothing was
typed. Next time it happens, `/usr/bin/log show --predicate 'subsystem == "sh.glas" AND category == "terminal-drop"'`
says why.

**Tests:** `TerminalDropTypingTests` 3 — a path typed and reported; a review left waiting gives way to a newer drop,
which is typed (fails with the old guard); no terminal reported.
