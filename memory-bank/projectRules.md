# Project rules

These sit on top of the four core rules in [AGENTS.md](../AGENTS.md) and apply to the merge.

1. **Move, do not rewrite.** Capability code arrives as modules. Rewriting working functionality to
   make it fit the new shell is how a merge turns into a rewrite and loses a year.
2. **Draw the shell boundary before the second capability.** Otherwise the first capability's
   assumptions silently become the boundary.
3. **The source apps keep building until parity.** They are the working software. Nothing in
   `../glas.sh`, `../glassdb` or `../glassDT` is deleted, moved or reset as part of this work.
4. **One capability reaches parity at a time**, with its own validation, before the next starts.
5. **Never present a moved capability as working because it compiles.** Parity means its own tests
   and native workflows pass here.
6. **The shell depends on no capability**, and capabilities do not depend on each other.
7. **Protocol engines never depend on the shell.** They stay independently testable, and remain
   candidates for process isolation later.
8. **Preserve user data.** The bundle identity, App Group and Keychain group decisions are made once,
   proven on a test build, and recorded. No silent migration or reset.
9. **Public repositories are not touched** without explicit instruction, including archiving,
   redirecting or renaming.
10. **No Git initialisation or commits** as an incidental part of any task.
11. **UI tests capture elements, never the screen.** `XCUIScreen.main.screenshot()` on a
    multi-display Mac captures other applications' windows. Use `element.screenshot()`; on the
    visionOS simulator, where in-test captures are 1×1, use `simctl io screenshot` outside the test.
    (Found 2026-09-10; the offending captures were deleted.)
12. **Superseded 2026-09-11.** The "never sheet-on-sheet on macOS" rule came from a crash that W4
    bisected to the SSH Key row's accessibility label (an `.accessibilityElement(children: .ignore)`
    label over a text-and-button stack), not to nested sheets. Nested sheets are allowed; modal
    editors follow rule 15.

13. **Layered panels declare their role.** `GlassLayeredPanel(role:)` is `.presented` for a sheet,
    popover or secondary window (paints theme + frost on every platform) and `.embedded` for a
    column or region inside a `GlassLayeredWindow` (paints only on visionOS, where panels float;
    pass-through on Mac, iPad and iPhone, whose window already paints edge to edge). Never nest a
    painting panel inside a layered window on the Mac: it double-paints the theme, clips the
    detail's action bar into a lighter band and exposes the window corner (observed 2026-09-10).

14. **No ornaments for controls inside visionOS sheets.** A `TabView`'s ornament and a hand-built
    `.ornament` both vanish from the accessibility hierarchy when their host is a sheet on visionOS
    (element trees captured 2026-09-11 show only the page content; no tab bar in any window).
    Section pickers and similar controls presented in a sheet live inside the surface — the
    settings sections use a leading column of vertical tabs there.

15. **Apple HIG patterns by default.** Unless the user explicitly asks otherwise, every surface uses
    the platform's native pattern. Modal editors (server form, SSH key, host, service) are sheets
    with a title header, a grouped `Form`, and the standard bottom bar with Cancel and the primary
    action bottom-trailing — the "Add Terminal to <host>" sheet is the reference. No custom
    title-bar buttons, no columns-style forms in windows for what is a save/cancel editor.
