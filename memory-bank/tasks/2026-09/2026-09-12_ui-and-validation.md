# UI corrections and record-editor validation, from using the app

Owner `/root`. 2026-09-12, builds 0.3.56 → 0.3.67, each installed and the version read back from
the installed bundle (rule 16). Every item below came from the user running the app, not from a
test. Not committed.

## The Release-only link failure that made the first build fail

`ToolbarContentBuilder.buildLimitedAvailability` undefined at link time, referenced from
`GlassTerminal.o`. Cause: the `visibilityPriority` availability guard had been extracted into
`GlassLayers` so the database capability would not add a third copy (W-floor's recommendation).

**An `if #available` inside a `@ToolbarContentBuilder` cannot be shared across a module boundary.**
The compiler emits `buildLimitedAvailability`, whose opaque type descriptor does not resolve in the
client. Debug built clean all day; 592 unit tests passed; three platforms built. `@inlinable` did
not rescue it. The guard now lives in **each** module that uses it —
`Sources/GlassTerminal/TerminalToolbarVisibility.swift` and
`Sources/GlassDatabase/DatabaseToolbarVisibility.swift` — with a comment saying the duplication is
deliberate, because it looks exactly like something to tidy away.

Also note: the failing build reported **exit code 0**, because the command was piped to `tail`.
Only reading the log caught it.

## UI corrections

| Change | Why |
|---|---|
| The terminal canvas no longer insets 3 pt with its own 18 pt corners on macOS | Against Apple's own rounded glass edge it read as a second, redundant border. The window's edge is now the only edge. Retires `TerminalCanvasMetrics.macOuterMargin` |
| "Paint Theme Color" removed | It only ever gated the Opacity slider, and `SettingsManager` already kept them in step (`paintsTheme = value > 0`). Opacity alone now says whether the theme is painted. **Migration:** a stored `paintsTheme: false` zeroes the opacity on load, so an upgrade changes nothing on screen; the retired key is read, never written |
| Service tabs are the choice: no per-tab toggle, no `✓` | Also fixed a reported bug — in `Add Service → Database` the **Terminal** tab was still togglable, so turning it on (expecting "use this machine's terminal") enabled a second draft demanding fresh SSH credentials. The tunnel switch inside the Database tab is the real control |
| One new service per sheet | Choosing another tab replaces the choice |
| Adding a machine requires a service; editing one adds none | The user: "Adding a machine without a service doesn't make sense." A "None" segment was added first and removed on their correction |
| Colour menus show real swatches | `Label(_:systemImage:).foregroundStyle(_:)` loses its tint inside a macOS menu — every dot rendered grey. Now `GlassColorTagRow` in `GlassLayers`, shared by both forms, hollow dot for None |
| `Set to NULL` and `Use Column Default` moved into the column's tool row | Each took a full row under the field; on a tall JSON editor that pushed the next column off screen |
| Database name is **optional** | Connecting without naming one opens the server and the browser lists what is there. This also unmasked a bug: the missing-address and missing-database messages shared the `.database` key, so the database check overwrote the address message |

## The sidebar toggle: a regression I caused and then failed to find

The `»` overflow began rendering a full blue "Toggle Sidebar" button. `MacWorkspaceView` had **two**
`.toolbar(removing: .sidebarToggle)` lines; one was deleted as an apparent copy-paste duplicate
while restructuring, and a later revert of the restructure did not restore it.

One removal is not enough to suppress the system toggle on that `NavigationSplitView`. The comment
directly above the line described the exact symptom. Restored, with a comment recording that it was
deleted as redundant and the symptom returned within the hour.

**The process failure is the point:** an investigation was run into macOS re-homing collapsed-column
toolbar items, and the conclusion reported was "still open, needs watching" — when `git diff` on the
file would have answered it immediately. A failing test (`workspaceUsesNativeTitle`, which collapses
the sidebar deliberately) was pointing straight at it and was read as "an intentional decision I
would be overwriting".

## Record-editor validation

Live per-field validation already existed and gates Save (`RecordEditorView.swift:330-338, 492-496`).
What was missing was the metadata — and one type was simply read wrong.

**`Sources/GlassDatabase/ColumnTypeConstraint.swift`** — what a value must *fit*. Parsed from the
**declared type** (`varchar(40)`, `decimal(10,2)`), which is already on screen beside the field.
Deliberately not from result-set metadata: MySQL reports `columnLength` in **bytes**, so a
`varchar(40)` in utf8mb4 comes back as 160 and a limit built on it would be wrong by 4×;
PostgreSQL reports no length at all. Covers character length, binary **bytes**, bit counts, integer
range by width and signedness (`Decimal`, so an unsigned 64-bit maximum is exact), and DECIMAL
precision and scale. A live counter appears within ten characters of the limit.

**`Sources/GlassDatabase/ColumnValueFormat.swift`** — whether a value is *well formed*. Temporal
columns previously accepted **any string at all** and failed at the server. Dates must be real days
(`2026-02-30` rejected, `2028-02-29` accepted, MySQL's zero date accepted). `TIME` honours its being
a duration as well as a clock (`-838:59:59` valid). Datetimes take a space or ISO `T` with an
optional zone. Also `enum(...)` and `set(...)` validated against their **declared members**,
including members containing commas or doubled quotes, and `uuid`.

Both run where the value is built, so a malformed value cannot be committed.

### The `tinyint` bug — the one that could have lost data

`isBool` matched a **bare `tinyint`**. That is backwards: `tinyint(1)` is MySQL's boolean
convention; plain `tinyint` is an integer from −128 through 127. A user's `human_impact_score
tinyint` rendered as a toggle reading "False", **and saving would have written `0` over the real
score**. MySQL 8.0.19+ drops display widths, so `tinyint(4)` reports as plain `tinyint` while
`tinyint(1)` keeps its width *because* it means boolean — the old check treated the one form that
is not boolean as the boolean case.

## Verification

| Check | Result |
|---|---|
| `swift test` | **615 tests / 48 suites**, 1 known issue (D13) |
| Release build, macOS | BUILD SUCCEEDED; installed at 0.3.67, version read back from the bundle |
| macOS UI suite (at 0.3.56) | 18 passed, 1 failed — the pre-existing tag-vocabulary test |
| The user, in the running app | confirmed the border, the tabs, the colour menus, the tunnel and the `tinyint` fix |

## Not done

`text`/`blob` byte limits (MySQL's `TEXT` is 65,535 bytes, not carried in the declared type),
PostgreSQL array formats, and the dead `TransportPlan.tunnelRemoteHost` field. All in the plan's
re-planned R8.
