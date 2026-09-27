# One-and-done host and service setup — W8, 2026-09-11

Worker W8. Requirement (user, paraphrased): setup should be one and done. Show only the
basic, required fields and put the advanced options behind an Advanced disclosure; adding a host
should offer to add its services right then. There is no legacy; plan for the first-run
experience. Tabs `[ Terminal | Database | Desktop ]` under the machine fields,
each with an "Add <kind> to this host" toggle. Not committed (coordinator commits).

## Design

- **Capability contract** (`Sources/GlassShell/GlassCapability.swift`): `GlassServiceDraft`
  (kind, `serviceDisplayName(hostName:)`, `requiredFields()`, `advancedFields()`,
  `validate(address:)`, `focusFirstIssue`, `commit(endpointID:host:address:)`, `rollback`),
  `GlassSetupIssue`, and on `GlassCapability`: `makeSetupDraft()`, `setupDraft(for:host:)`,
  `removeService(_:host:)`. Defaults hand back `GlassUnavailableServiceDraft`, which says so in the
  sheet and blocks Save, so a capability without the contract cannot create a half-made service.
  Removed: `needsSetup`, `GlassShellAddressRequest`, `GlassShellPlaceholderRequest/Session`.
- **One sheet** (`Sources/GlassShell/GlassShellSetup.swift`): `GlassShellSetupMode`
  (`addHost`, `editHost`, `addService(host, kind)`, `editService(host, service)`),
  `GlassShellSetupModel` (fields, `tabOrder = [.ssh, .database, .rdp]`, enable/validate/save) and
  `GlassShellHostSetupSheet` (Machine section: Name, Address; Services: segmented tabs, toggle
  `setup-enable-<kind>`, the draft's required fields, an Advanced row `setup-advanced-<kind>`; an
  "Also known as & Collections" row `host-editor-organize` with the two tag fields; bottom
  Cancel/Save). Disclosures use `GlassFormDisclosureStyle` (a plain button row with a chevron):
  the stock macOS disclosure triangle ignored synthesized clicks, so it was untestable.
  Save order: host (create or update address), then each enabled draft in tab order — capability
  commit first, then the link under that endpoint id; on a failure the services this save created
  are removed through their capabilities, the failed draft rolls back, and a host created by this
  save is deleted. `GlassShellEditors.swift` (host editor, service picker, W7's address prompt) is
  deleted; `GlassShellModel.addService` takes the endpoint id; `removeService` unpairs then asks the
  capability to delete its configuration; Connect on a kind without a capability sets an error
  message instead of a placeholder session.
- **Terminal** (`Sources/GlassTerminal/ServerFormViews.swift`): `TerminalServiceDraft` (an
  `@Observable` conforming to `GlassServiceDraft`; validation, persistence through
  `ServerManager.addServerOrThrow/updateServerOrThrow`, in-memory-testable),
  `TerminalRequiredFields` (Username, Method, Password / SSH Key with the nested Add SSH Key sheet),
  `TerminalAdvancedFields` (Name, Port, legacy algorithms, routing, terminal size, colour tag),
  and glas.sh's standalone `ServerFormView` rebuilt from the same two views (keeps its Host field;
  Tailscale import and command palette unchanged). `GlassTerminalCapability` implements the
  contract; `SetupRequest`, the setup sheet, `needsSetup`, the needs-address view, `Set Up…` and
  the terminal's own Edit/Delete row actions are gone (Edit and Remove are the shell's).
  `Request.showFailure` shows the connect flow's alert for a link with no server behind it.
- **Detail** (`GlassShellLibraryView.swift`): "Add a service…" → `.addService(host, .ssh)`; a
  service row has Connect, Edit (`host-service-edit-<kind>`) and the capability's actions (or an
  overflow menu); an unset address reads "Not set"; Edit Host → `.editHost`.
- Accessibility: every form row's content is one control and validation text is its own row;
  `TerminalRequiredFieldLabel` no longer folds its texts. The macOS accessibility recursion
  reappeared once in this work (`AccessibilityNode.accessibilityLabel`, crash 09:00:42) with a
  `LabeledContent` over a stacked content; gone after the change.

## Changed files

`Sources/GlassShell/{GlassCapability,GlassShellSetup (new),GlassShellModel,GlassShellLibraryView}.swift`,
`Sources/GlassShell/GlassShellEditors.swift` (deleted),
`Sources/GlassTerminal/{ServerFormViews,GlassTerminalCapability,GlassTerminalLibraryEntries,TerminalConnectFlow}.swift`,
`Tests/GlassShellTests/{GlassShellSetupTests (new),GlassShellHostAddressTests,GlassShellModelTests,GlassShellSecurityFixTests}.swift`,
`Tests/GlassTerminalTests/{TerminalServiceDraftTests (new),glas_shTests}.swift`,
`UITests/{GlassShellLibraryUITests,GlassShellTagFieldUITests,GlassTerminalUITests}.swift`.

## Verification

| Check | Result |
|---|---|
| `swift test --build-system native` (whole package, scratch `build-w8`) | **483 tests / 30 suites passed** (`scratchpad/w8-swift-test-3.log`; earlier runs caught a tab-order assumption in a new test) |
| App builds: macOS (test host), iOS Simulator, visionOS Simulator | passed (`w8-build-*.log`) |
| macOS UI, all suites, real host env (`results-mac-w8g.xcresult`) | **12 / 12 passed**: library 5 (incl. the new one-sheet add-host-with-terminal test, Database tab disabled), tag field 1 (fields under the organise row), terminal: add-service-collects-address, **real host through the one sheet (live shell, 60 s)**, edit-terminal-with-Advanced, chrome, settings pages; smoke |
| iPhone 17 Pro Max UI, all suites, real host env | see below (filled in when the run completes) |
| visionOS UI, all suites | see below |
| Screenshots (own window only), `scratchpad/shots-w8/` | `mac-add-host-terminal-tab-filled.png` (Add Host, ✓ Terminal tab, username/key), `mac-add-host-database-tab-disabled.png`, `mac-edit-terminal-advanced.png` (Edit Terminal on editable, Advanced expanded), `mac-add-service-collects-address.png`, `mac-add-key-sheet-over-host-sheet.png`, `mac-detail-after-one-sheet.png`, `mac-terminal-live.png` |

## Remaining

- Database and Desktop tabs are disabled until Stages 3 and 4 register a capability with the
  contract (the sheet then composes their drafts with no shell change).
- A link another family app recorded without a saved server: Connect shows an alert, Edit says the
  service has nothing behind it; the user removes and re-adds it.
- `GlassUnavailableServiceDraft` is the honest default for a capability that has not adopted the
  contract; no production capability uses it.
