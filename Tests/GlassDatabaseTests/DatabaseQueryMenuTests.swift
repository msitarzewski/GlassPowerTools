import Testing
@testable import GlassDatabase

/// B-X11: on a table tab the Query menu offered Run and nothing else, though the tab's own SQL pane
/// formats and takes a query from History or Saved Queries as a SQL document does. And the menu's
/// verbs went to the session, so a second window on the same connection answered them too.
@Suite
struct DatabaseQueryMenuTests {
    @Test("a table tab's pane: Format with SQL in it, connected or not; History and Saved Queries always; no Explain")
    func tableTab() {
        let empty = DatabaseQueryMenuAvailability.table(SQLRunAvailability())
        #expect(!empty.canExecute && !empty.canFormat && !empty.canExplain)
        #expect(empty.canUseQueryLibrary, "History fills an empty pane")

        let offline = DatabaseQueryMenuAvailability.table(SQLRunAvailability(canRun: false, hasText: true))
        #expect(offline.canFormat, "formatting needs no connection")
        #expect(!offline.canExecute)

        let ready = DatabaseQueryMenuAvailability.table(SQLRunAvailability(canRun: true, hasText: true))
        #expect(ready.canExecute && ready.canFormat && ready.canUseQueryLibrary)
        #expect(!ready.canExplain, "a table tab has no Explain")
    }

    @Test("a SQL document keeps its rules: Run, Format and Explain together, its library always")
    func document() {
        let ready = DatabaseQueryMenuAvailability.document(SQLRunAvailability(canRun: true))
        #expect(ready.canExecute && ready.canFormat && ready.canExplain && ready.canUseQueryLibrary)
        let notReady = DatabaseQueryMenuAvailability.document(SQLRunAvailability(canRun: false))
        #expect(!notReady.canExecute && !notReady.canFormat && !notReady.canExplain)
        #expect(notReady.canUseQueryLibrary)
    }

    @Test("nothing to run in front: everything off")
    func nothing() {
        let none = DatabaseQueryMenuAvailability.none
        #expect(!none.canExecute && !none.canFormat && !none.canExplain && !none.canUseQueryLibrary)
    }

    @Test("the active table tab's pane wins over the hidden tabs' defaults, with SQL in it and no connection too")
    func activePaneWins() {
        var value = SQLRunAvailabilityKey.defaultValue
        SQLRunAvailabilityKey.reduce(value: &value) { SQLRunAvailability(canRun: false, hasText: true) }
        SQLRunAvailabilityKey.reduce(value: &value) { SQLRunAvailability() }
        #expect(value.hasText, "a hidden tab after it does not hide the active one's SQL")
    }
}
