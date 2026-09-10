# The one failing terminal test — root cause and fix

Worker fork, 2026-09-10. **Status: fixed in `Sources/GlassTerminal/Models.swift` and
`Tests/GlassTerminalTests/glas_shTests.swift`; not committed (coordinator commits).**

## Test

`localSSHSubstitutionIsDeviceLocalAndInvalidatedWhenSourceChanges` (`glas_shTests.swift:580`)
expected `replacement.intent.startupCommand == "cd -- '/srv/it'\\''s a project' && {\npwd\n}"` and
got `nil`.

## Path traced

- `WorkgroupSSHSubstitution.intent` (`Models.swift:1768-1773` before the fix) built
  `"cd -- <quoted path> && {\n<script>\n}"` — a **multi-line** string — and passed it to
  `LayoutPreset.SessionIntent.init(serverID:label:startupCommand:)`.
- That initializer stores `Self.normalizedCommand(startupCommand)` (`Models.swift:1862`), which is
  `TerminalStartupCommandTicket(command:)?.command` (`:1896`).
- `TerminalStartupCommandTicket.init?` (`Models.swift:298-315`) returns `nil` for any command that
  contains `"\n"` or `"\r"` (`:308-309`), because startup commands are written to the PTY as one
  line and a newline would execute the fragments as separate commands.
- So every substitution with a non-empty script produced `startupCommand == nil`. The multi-line
  form could never survive the initializer.

## Which side glas.sh changed — the evidence

Diffs of the moved files against `../glas.sh/glas.sh/Models.swift` and the test file were empty
for every line on this path: the move is faithful. In glas.sh itself:

| Piece | State in `../glas.sh` | Evidence |
|---|---|---|
| Ticket rejects `\n`/`\r` | **committed** | `git show HEAD:glas.sh/Models.swift` lines 404-409; introduced by `f3f00c3` 2026-07-20 "Add terminal workgroups and lifecycle polish (#28)" (`git log -L`) |
| `SessionIntent.init` normalises through the ticket | **committed** | `HEAD:glas.sh/Models.swift:2902, 2922`; same commit `f3f00c3` |
| `WorkgroupSSHSubstitution.intent` multi-line builder | **uncommitted** (working tree only) | `git diff -- glas.sh/Models.swift` adds the `quotedPath` / `&& {\n…\n}` / `return .init(…)` lines |
| The test and its expectation | **uncommitted** | `git diff -- glas.shTests/glas_shTests.swift` adds the whole test including the `{\npwd\n}` expectation |

glas.sh's working tree is dirty for `Models.swift`, `SettingsManager.swift` and `glas_shTests.swift`
— the user's unmerged PR. That PR added a builder emitting a form that the committed initializer
rejects, plus a test asserting that form. **The test cannot pass in glas.sh either; the failure is
inherited from the unmerged PR, not a move regression.** No glas.sh build was needed to prove it:
the rejection is a deterministic guard on the string.

## Fix (per glas.sh's evident intent: substitution = change directory, then run the script)

`WorkgroupSSHSubstitution.intent` now emits a **single-line group command**:
`cd -- '<path>' && { <script>; }` — valid POSIX (a group needs `;` or a newline before `}`), keeps
the script's exit status, no subshell, and passes the ticket. A trailing `;` or `&` on the script
is not doubled. Empty script → `cd -- '<path>'`; empty path → the script alone (unchanged).
`script` is already single-line in practice: `WorkgroupEditorView.swift:130` validates the command
through the same ticket before it can be saved.

`Models.swift` change (10 lines replacing 2) with a comment stating why one line. The test's
expectation becomes `"cd -- '/srv/it'\\''s a project' && { pwd; }"`, and a new test
`sshSubstitutionStartupCommandIsAlwaysASingleLineTheTicketAccepts` covers trailing `;`, trailing
`&`, directory-only, command-only, and asserts every result is accepted by
`TerminalStartupCommandTicket`.

## Results

`swift test --build-system native --filter "localSSHSubstitution|sshSubstitutionStartupCommand"`:
**2 tests passed.** Full-suite result is in the coordinator's run.

## Note for the glas.sh PR

The same fix applies to glas.sh's unmerged branch (`glas.sh/Models.swift`, the substitution
builder, and the test). Nothing in `../glas.sh` was edited by this work.
