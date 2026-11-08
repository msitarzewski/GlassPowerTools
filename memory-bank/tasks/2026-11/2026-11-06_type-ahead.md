# Type-ahead in terminals (D102) — plan, 2026-11-06

**Asked:** "Can we build some form of type ahead into our terminal sessions using session history? What other
sources should we tap?", then, after the recommendation, "write up the plan, then begin the build of all of it."
**Status:** Approved (his words above), in progress. Nothing committed.

## What it does

While someone types at a shell prompt, the terminal offers the rest of the command:

- **Mac:** grey text after the cursor. → at the end of the line takes all of it, ⌥→ one word. Typing past it, or
  anything else, leaves it alone; it never reaches the shell until taken.
- **iPhone and iPad:** up to three chips in the keyboard bar; a tap types the rest of that command.
- **Vision Pro:** the same chips in the window's bottom toolbar.
- Nothing is offered on the alternate screen (vim, less, an agent's UI), at a password prompt, or while the line
  can't be read with confidence.

## Knowing the line (the hard part)

The shell owns the line being edited; the app sees only the bytes it sends and the screen that comes back.

1. **Shell integration, where installed.** The shell marks its prompt and command with the codes iTerm2, Ghostty,
   Kitty and WezTerm use (OSC 133: `A` prompt, `B` input begins, `C` command runs, `D;<status>` finished) and VS
   Code's command line (OSC 633 `E;<command>`), plus OSC 7 for the folder. Those that already use iTerm2's, VS
   Code's or Ghostty's integration are understood too.
   - SwiftTerm already decodes OSC 133 and tags cells as prompt, input or output (`Terminal.swift:2461`). The app
     listens through `parser.oscHandlers` (checked before SwiftTerm's own, `EscapeSequenceParser.swift:560`) and
     passes 133 on to SwiftTerm, whose handler is made public for it (patch **S3**, `Packages/SwiftTerm/PATCHES.md`).
   - From `B` the app knows where the input starts; the line is the screen from there to the cursor. On `C` the
     command that ran is `E`'s text, or else the input cells. `D` gives its exit status.
2. **Without it: the typed line, checked against the screen.** The keys sent since the last Enter, kept only
   while they are plain characters and backspace; an arrow, Tab or ⌃ key drops it. It counts only if the screen
   shows exactly those characters just before the cursor, which also keeps out anything typed with echo off (a
   password). Enter with a confirmed line records it.

**Installing the integration.**
- This Mac's own zsh terminals: automatic. The pane starts zsh with `ZDOTDIR` pointing at the app's small
  start-up folder, which restores the person's own `ZDOTDIR`, reads their files as usual, then adds the hooks
  (as VS Code and Ghostty do). Terminals in tmux get it through the session's environment.
- Servers: offered once per machine, never silent. Installing writes `~/.config/glasspowertools/shell-integration.<zsh|bash|fish>`
  over SFTP and adds one marked `source` line to `~/.zshrc`, `~/.bashrc` or fish's `config.fish`. Settings shows
  each machine's state and can remove both again.
- The scripts emit only in an interactive shell on a terminal, keep `$?`, add their marks without replacing
  someone's prompt (powerlevel10k, starship and oh-my-zsh themes keep working), and stand aside where another
  integration already marks prompts.

## Sources

Each source offers whole-command candidates for what's typed; the engine ranks them and keeps the best one for
the grey text and the top three for chips.

1. **Commands run on this machine,** recorded by the app (integration's `C`, or a confirmed line's Enter).
   Ranked by recency and count, and higher when run in the same folder, with the same first word, or after the
   same previous command. Per machine (the library's identity; "This Mac" for local terminals).
2. **The machine's own shell history,** read once over SFTP when first connected after the person allows it
   (`~/.zsh_history`, `~/.bash_history`, fish's `fish_history`; zsh's extended and metafied formats, bash's
   timestamps), and again when asked. Local: the same files on this Mac.
3. **Snippets,** by their `useCount` and `lastUsed`.
4. **The library:** machine names for `ssh`, `scp`, `sftp`, `rsync`, `mosh` and `ping`, with user and port where
   they differ from the defaults; database names for `psql`, `mysql`, `mongosh` and `redis-cli` on the machine the
   terminal is on (from the database tool, given to the terminal by the app).
5. **The folder:** git branches and remotes after `git checkout`, `switch`, `merge`, `rebase`, `push` and `pull`;
   file and folder names for path arguments (`cd` takes folders only); `package.json` scripts after `npm run`,
   `yarn` and `pnpm`; Makefile and justfile targets after `make` and `just`. Read over SFTP or the local file
   system, cached per folder, refreshed on `C`.
6. **Common tools:** subcommands and flags for about forty CLIs (git, docker, kubectl, npm, brew, systemctl,
   journalctl, ssh, tar, cargo, swift, gh, tmux, apt, …), written for this app as data files, not copied.
7. **The screen:** words printed above the prompt that fit the argument being typed (hashes, container IDs,
   paths, hosts), as iTerm2's ⌘; does.
8. **On-device AI:** a likely next command from the last few commands, the folder and the repository, using the
   on-device model the AI Assistant already uses. Off by default; only when the other sources have nothing; never
   leaves the device.

## Privacy

- History stays on the device: one file per machine in Application Support, complete file protection, excluded
  from backup, at most 5,000 commands each. No iCloud sync in this version.
- Not recorded: anything the integration didn't mark as typed input or the screen didn't echo; the alternate
  screen; commands that look like they carry a secret (`*TOKEN*=`, `*PASSWORD*=`, `-p<pass>` to mysql,
  `Authorization:` headers, `--password`, URLs with `user:pass@`, AWS keys, private-key blocks); a line starting
  with a space (zsh's and bash's own convention).
- Imported history goes through the same filter.
- Settings ▸ Terminal ▸ Suggestions: on or off, each source, per-machine history (count, Forget, Forget All),
  import a server's history, the shell integration's state per machine (install, remove), the AI suggestion.

## Others' suggestions

zsh-autosuggestions and fish draw their own grey text. When text appears after the cursor at a prompt the app
didn't draw, the app's own grey text stands aside for that terminal (chips still show). Settings can turn the
app's grey text off.

## Where the code goes

| Part | Where |
|---|---|
| Prompt marks, the line, the typed-line check, the cursor's cell, taking a suggestion from outgoing keys | `Sources/GlassTerminalEmulator/TerminalPromptTracker.swift` (new), wired in `SwiftTermHostView.swift` |
| SwiftTerm's 133 handler made public | `Packages/SwiftTerm` (S3) |
| History store, engine, ranking, sources | `Sources/GlassTerminal/TypeAhead/` (new) |
| History file parsers, secret filter | `Sources/GlassTerminal/TypeAhead/` (new) |
| Shell integration scripts, local start-up folder, server install and removal | `Sources/GlassTerminal/ShellIntegration/` (new) |
| Common tools' data | `Sources/GlassTerminal/Resources/CommandSpecs/*.json` (new), reader in `TypeAhead/` |
| Grey text (Mac), chips (iPhone, iPad, Vision Pro) | `Sources/GlassTerminal/TypeAhead/` views, placed in `MacLocalTerminalPaneView` and `TerminalWindowView` |
| Database names | given by the app target (`App/`), which imports both tools |
| Settings page | `GlassTerminalSettingsPages.swift` |

## Order of work

1. **Foundation:** S3; the prompt tracker and the typed-line check; the history store and secret filter; the engine
   with recorded history and snippets; grey text and → / ⌥→ on the Mac, local and remote; zsh integration on
   this Mac.
2. **Every device:** chips on iPhone, iPad and Vision Pro; bash and fish integration; installing on servers; server
   history import.
3. **Context:** library and database names; the folder (git, files, package scripts, make and just targets).
4. **Knowledge:** common tools' data; words on screen; the on-device AI suggestion.
5. **Settings and the others' suggestions.**

Leaf parts are built in parallel by helper agents, each owning only its new files: the history parsers and
secret filter; the shell integration scripts and installers; the common tools' data and its reader. The
coordinating session owns everything else and the memory bank.

## Validation

- Unit tests for each parser, the filter, the engine's ranking, the tracker against recorded byte streams.
- Live: real zsh and bash in a PTY with the integration (the marks, `$?` kept, prompts unchanged, a password
  read with echo off never recorded); in tmux control mode (do the marks pass through `%output`?); a server
  install and removal against the test VM only.
- Each test proven to fail with its fix removed.
- The real app: grey text and → on the Mac in the macOS VM; chips in the iPhone and Vision Pro simulators.

## Progress

- 2026-11-06: plan written; build started.
- **S3** in `Packages/SwiftTerm` (PATCHES.md): `oscSemanticPrompt` public, `Terminal.scrollInvariantCursorRow`,
  `TerminalView.cursorCellFrame`.
- **Emulator:** `TerminalPromptTracker` (133/633 marks passed on to SwiftTerm; the typed line checked against the
  screen), `TerminalTypeAhead.swift` (suggestion, the keys that take it, the grey text view). Wired in all three
  engines (`promptTracker`, `onOutputRead`, `showTypeAheadGhost`, `typeText`), the two coordinators' `send` and the
  Mac local engine's `sendUserInput`; the host model's type-ahead section (`onTypeAheadLine`, `setTypeAhead`,
  `takeTypeAheadChoice`, `typeAheadOutgoing`, `drawsTypeAheadGhost`, `typeAheadOwner`).
- **Capability:** `TerminalCommandHistory` (per machine, on device), `TerminalTypeAheadEngine` (ranking),
  `TerminalTypeAheadController` (+ settings), attached in `TerminalWindowView.configureTypeAhead` and the Mac local
  pane's onAppear. `TypeAheadPendingTypes.swift` is a TEMPORARY stand-in until the history agent's files land
  (its secret check refuses everything, so nothing is kept meanwhile).
- **Tests:** `TypeAheadTrackerTests` 11, `TypeAheadEngineTests` 6, all passing; each rule bitten (8 bites).
- **Then:** chips (`TerminalTypeAheadChips`, above the keyboard bar on iPhone/iPad while it's up; Vision Pro
  whenever there are choices; system glass, `glassBackgroundEffect` on Vision Pro); Settings ▸ Suggestions
  (`TerminalTypeAheadSettingsView`); sources: library (`TerminalTypeAheadLibrary`), folder
  (`TerminalTypeAheadFolder`, local and SFTP readers, one SFTP client per terminal), common tools (the agent's
  `CommandSpecs`, also deciding the folder's argument kinds), screen (`TerminalTypeAheadScreen`), on-device AI
  (`TerminalTypeAheadAssistant`, off by default, after a 600 ms pause). All wired in `TerminalWindowView` and the
  Mac local pane. GlassTerminal builds for macOS, iOS and visionOS.
- **Tests now:** tracker 11, engine/library/screen/assistant 10, folder 6 (`TypeAheadFolderTests`). The assistant's
  answer test waits on the real secret filter (the stand-in refuses everything).
- **Measured:** tmux 3.8's control mode passes OSC 133 and 633 marks through `%output` unchanged
  (`~/Software/glass/tmp/resize-probe/tmux-osc133.sh`), so tabs in tmux see the shell's marks.
- **Written against the agents' APIs:** history import (`TerminalHistoryImport`, Settings ▸ Import per machine),
  this Mac's zsh integration (`TerminalLocalShellIntegration`, via `MacLocalTerminalConfiguration.environment(from:
  shell:)`, its own Settings switch; never writes into Application Support from a test process), server install
  and removal (`TerminalShellIntegrationInstaller`, Settings ▸ "Shell integration on your machines").
  `ShellIntegrationPendingTypes.swift` is a TEMPORARY stand-in until the shell-integration agent's file lands.
- **Agents:** common tools done (69 tools, 1,410 subcommands, 4,591 options, 607 KB JSON loading in 9 ms; 12 tests,
  16 bites). The history parsers and filter landed with both stand-ins gone. The shell integration's file landed,
  and its report is still to come.
- **Live, this Mac:** `LiveTypeAheadTests` runs the real local pane with `/bin/zsh -l` and this Mac's integration
  from a temporary folder, in a window. The person's `.zshrc` runs, the exact command line is kept, its start
  typed again offers the rest, and the grey text is drawn. 3 bites: integration not loaded, the line change not
  reported, the grey text not drawn.
- **History store:** `TypeAheadHistoryTests` 5, with 5 bites (leading space, folder, limit, backup exclusion, a
  seen command counted again).
- **Server install, live against the test VM** (`LiveShellIntegrationInstallTests`, gated): install added one line and
  the script; a new login shell sent A, B, `633;E` with the exact command, and `D;0`. **Removal didn't give the file
  back byte for byte:** the test VM's `.bashrc` ended without a newline, and install added one before its line that
  removal kept. The test VM restored by hand (3,807 bytes, ending `esac`); the empty `~/.config/glasspowertools` the
  install made removed; the agent asked for a reversible pair with a round-trip test. The installer now also
  removes its emptied folder. (The test VM's clock reads 4 days behind: file times there mislead.)
- **macOS VM (real app):** the grey text showed after the cursor and → took it. Found there: each terminal's first
  command kept twice (counted at Enter before any mark, then again by the integration's C); fixed with
  `countedAtEnter`, bitten.
- **2026-11-06, the owner: "No surprises for users."** What that changed:
  - **Another program's input is never offered over or kept.** Without the shell's marks, a line typed into Claude
    Code, Python or mysql is echoed exactly like one at a prompt. The typed-keys fallback now needs
    `TerminalPromptTracker.shellIsInForeground`: only this Mac's own terminal answers it (`tcgetpgrp` on the PTY
    equals the shell it started; never for tmux). An SSH terminal whose shell marks nothing gets no suggestions
    and keeps nothing until its machine has the integration (as VS Code's terminal suggestions need theirs).
    Live test in `cat` (`LiveTypeAheadTests.otherProgramsInput`), bitten.
  - **fish 4's own marks** (the integration agent's report): its `C` names the command (`cmdline_url`) and arrives
    before the app's `E`; an `E` after a `C` names it only when the `C` couldn't (`awaitingCommandLine`); a prompt
    (`A`/`B`) inside a running command (fish marks `read`'s) is ignored, so its `D` still ends the command. Three
    tests, all bitten (the stale-`E` case only with all three of its overlapping guards removed).
  - **zsh names a leading-space command in its `E`:** the history keeps it out itself; checked live, bitten.
  - **A paste never takes a suggestion,** and the tracker follows pastes in both SSH engines (`commitPaste`).
  - **Start-up files on servers:** install only appends (as iTerm2's installer does), checked and read back;
    removal uses the Files editor's verified save (`SFTPBrowserView.uploadRemoteEditorBytes`: written beside, renamed
    over, only if unchanged since read); a linked start-up file (dotfiles) is changed where it lives and stays a link;
    a non-UTF-8 file is refused; a file left empty that the install made is removed. The agent's line ending: a file
    without a final newline gets a marked line (`markerAfterAddedLineBreak`) that ends with one, so a later
    `echo … >> ~/.bashrc` is its own line, and removal still restores the file byte for byte.
  - Live against the test VM (`LiveShellIntegrationInstallTests`, 3 tests): install/remove byte for byte; a line appended
    after the install runs at login and survives removal; a linked `.bashrc` keeps its link. The link handling bitten
    (removal refused: the editor's guard). The test VM's `.bashrc` checked afterwards through Parallels: 3,807 bytes, a
    regular file, no leftovers.
- **A picture pasted on a Mac terminal** (the owner's example of a surprise, 2026-11-06). ⌘V read text alone on the
  Mac, in both panes, since glas.sh (an independent search of every ref, worktree and glas.sh's history agrees:
  it never did anything, and right-click Paste was greyed out). Now `MacTerminalPastedPicture` (macOS) takes a
  clipboard holding a picture and no text or file (a screenshot, Copy Image), as PNG (TIFF redrawn), and sends it
  where a dropped one goes: an SSH pane uploads it and types the host's path (`TerminalRemoteDrops`, as iPhone and
  Vision Pro since 0.4.526); a local pane writes it to `TerminalDroppedPaths.inbox()` and types its path. Text beside
  a picture (Excel, Numbers, Word copy both) is pasted as text, a Finder file as before. Other terminals send an
  empty bracketed paste and leave Claude Code to read this Mac's clipboard; a path works over SSH too. Both Mac
  views' `paste` ask `pasteFiles` first; right-click Paste is enabled for a picture (types only, no paste prompt).
  `MacTerminalPastedPictureTests` (private pasteboards, never the person's): the rules, and ⌘V in a real local zsh
  typing a PNG's path, not run. 4 bites. Not tried: an SSH pane's paste end to end (the upload is W14's).
- **Full suite, settled:** one run failed a live tmux pane test (its command typed before tmux was ready never
  showed in 30 s). Full runs had gone from 16 s (this morning) to 29–47 s. Sampling the main thread
  (`~/Software/glass/tmp/stalls/sample-run-1106.zsh`, `main-thread-1106.py`): `ShellHistoryFileTests.largeFiles()`
  and `TerminalCommandSecretsTests.speed()` held it for seconds each (the test target defaults to MainActor). Made
  `nonisolated` (the code they test already is): 1,224 tests in 15.5 s, twice, the tmux test 7.8 s, at load
  averages of 24–35. The two macOS VMs, idle, were stopped.
- **Simulators, first runs:** chips test passes on both, but drawn at a phone's width on Vision Pro the chips cut
  their text in the middle ("git st…h list"), and the iPhone picture was blank (SwiftUI's image renderer doesn't
  draw Liquid Glass, so that test proves only the strip's height). The chips now scroll sideways at their own width,
  each at most 280 pt (`TerminalTypeAheadChipWidth`: a frame alone clips in a scroll view), a long one losing its
  start (what was typed) rather than its end.
- **A line typed before type-ahead attaches** offered nothing until the next key (a window opened on a terminal
  typed into; the demo). `offerForCurrentLine()` after the sources are added, on every platform. Live test, bitten.
- **`--demo-open terminal-typeahead`** (DEBUG): three git commands run with shell marks, then "git st" typed. Every
  demo replay keeps its commands in a history of its own, in memory (`TerminalSession.demoTypeAheadHistory`), never
  the device's.
- **Simulator test fixes (both agents' tests):** the shell integration's privacy check looked for an empty user
  name ("//", in every `file://`) on simulators: it now takes the Mac's from `SIMULATOR_HOST_HOME` and refuses to run
  without one (bitten on the Mac with a user name in a script). The history speed test failed on the iPhone simulator
  only with the suite beside it (28× against 27; alone it passes): timed by the thread's own running time
  (`CLOCK_THREAD_CPUTIME_ID`) and the splitting over 16 passes; a doubled zsh parse still fails it (38×).
- **Defect found by the real app: no SSH terminal ever offered anything.** The demo on the Vision Pro simulator
  showed the line and no chips; a privacy-safe log (`sh.glas`/`type-ahead`, lengths and counts only) showed the
  controller attached and then heard nothing. The host model has two `attach`es: SSH engines (iPhone, iPad, Vision
  Pro, a Mac's SSH pane) use the one with a delegate's owner, and type-ahead was wired into the other (the Mac's own
  shell) alone. Both now call `followPrompt(of:)`. `TypeAheadSSHTerminalTests` (the Mac's SSH engine, fed marked
  output): passes, fails without the fix. Every earlier live check had used a local pane. After the fix the log read
  three commands run and kept, the line, three choices, and the chips drew.
- **Where the chips go (his choice, D102 amended):** above the keyboard's bar on iPhone and iPad
  (`TerminalTypeAheadChipRow`, a `safeAreaInset` under the terminal, 40 pt, standing while the keyboard is up and
  type-ahead is on: `SwiftTermHostModel.offersTypeAheadChips`); an ornament under the toolbar on Vision Pro for the
  terminal in front (`TerminalWindowView.typeAheadChipsShown`).
- **Checked on the new code (2026-11-06, evening):** the Vision Pro demo draws the chips as an ornament under the
  toolbar, text whole, clear of the terminal. `GlassTerminalTests`: Mac 1,226 (16.9 s), iPhone simulator 832, Vision
  Pro simulator 832, all passing. A live test's race fixed (it read the output the moment the shell marked the
  command run, before the output came); its check bitten (the person's `.zshrc` not run).
- **Not checked:** the iPhone/iPad row in the app (it stands only with the on-screen keyboard up, which the demo
  doesn't raise; its rules and height are tested); an iPad with a hardware keyboard (is `keyboardAccessoryShown` true
  there? if not, no chips); a real server's SSH terminal end to end (the engine's path is tested and the demo runs
  it); the headset itself.
- **Next:** his look at it; committing waits on his word.
- **2026-11-06 22:22, installed at his word ("install this build on the Mac, iPhone"):** 0.4.607 (Release,
  development signed) on the Mac (read back from `/Applications`, running) and the iPhone (devicectl reads
  0.4.607); not the headset (0.4.606). No new crash reports; his 26 tmux sessions intact.
- **2026-11-06, his "I'm not seeing any auto complete at all" (0.4.607): no tab in tmux was ever offered anything.**
  Every one of his tabs is in tmux. Measured on his Mac (read-only): his tmux server dates from 2026-11-04 and its
  global environment has no ZDOTDIR; `update-environment` doesn't carry it; the claim's `new-session -d` passed
  none. tmux gives a new session's shell the server's environment, not the client's, so the integration handed to
  the tmux client reached no shell; and the typed-keys fallback was "never for tmux". Every check had used a tab not
  in tmux (lesson added to the verification-scope memory). Fixed:
  - **The session's own environment:** `tmuxLaunch` splits the integration's variables off
    (`TerminalLocalShellIntegration.tmuxEnvironment`, `TerminalShellIntegration.tmuxSessionVariables`) into
    `MacLocalTmux.Launch.sessionEnvironment`, passed as `new-session -e` by the claim and the pane's own
    `new-session -A` (tmux 3.2+, CHANGES "Add -e flag for new-session"; `takesSessionEnvironment`). The server
    and clients get the rest, with the person's own ZDOTDIR back, so a server started by the app no longer hands
    the app's folder to sessions made from another terminal.
  - **The first prompt:** zsh draws it, marks and all, before the tab attaches, and the client drops a pane's
    output while it re-reads it, so a new tab knew nothing until a first Enter. A tab in tmux now asks whether the
    pane's shell reads its keys, as a plain tab does: the client asks `#{pane_pid}` with the pane
    (`TmuxControlClient.panePID`), and `MacLocalProcessEngine.shellReadsItsTerminal` reads the process table
    (`proc_pidinfo` `PROC_PIDTBSDINFO`: a shell name and `e_tpgid == pbi_pgid`). That also covers his open tabs,
    whose shells will never mark.
  - Probe (`~/Software/glass/tmp/typeahead-tmux/probe.zsh`, a private server): with `-e`, zsh in the session sent
    A/B/C/D and `precmd_functions` held `__glass_si_precmd`.
  - Tests: `LiveTypeAheadTests.inTmux` (a server started without the integration, the app's claim, a tab on pipes
    typed into at once: followed, kept once with its status, offered, grey text), `inTmuxWithoutIntegration` (his
    open tabs: offered and kept at the prompt; `cat`'s input neither), `tmuxSplit`, `claimGivesSessionEnvironment`,
    `TmuxControlClientTests.panePID`. Four bites (the `-e`, the foreground check, the split, the PID), each restored
    and compared. `LiveTypeAheadTests` moved under `LocalTmuxServerSuites`: it swaps `baseFolder`, and two launch
    tests beside it took the swapped folder into their tmux arguments. Mac `GlassTerminalTests` 1,231 passing.
  - **Limit found (all tabs whose shell marks nothing, not new):** after a ⌃ key (⌃D ending `cat`, ⌃A, ⌃R) the keys
    no longer say what the line holds, so nothing is followed until the next Enter.
  - **His answers:** add the commands on PATH as a source ("Yes, add PATH"); the accept key unanswered (→ kept).
- **2026-11-07, programs on the machine (source 9, his "Yes, add PATH"):** `TerminalTypeAheadCommands` offers the
  word in a command's place (the line's first, after `|` `;` `&&` `||` `(`, `FOO=1`, or `sudo`/`time`/`env`/…) from
  the usual PATH folders (Homebrew's, MacPorts', the system's, `/snap/bin`), the folders `/etc/paths` and
  `/etc/paths.d` add (as `path_helper`), `~/.local/bin`, `~/bin`, `~/.cargo/bin`, and the shell's own commands.
  Not the shell's own PATH, which only its start-up files make. Read once per machine a run through the terminal's
  reader (this Mac's files, or the server's SFTP, home-relative there); score 0.5, a tool `CommandSpecs` knows 0.6,
  below history, snippets, folder and tools; nothing for an empty word. Settings ▸ Suggestions: "Programs on the
  machine". Each kind of terminal now gets its word sources from one function (`addThisMacSources`,
  `addServerSources`), and `TypeAheadCommandsTests.everySourceAttached` checks every word source is in both. Tests:
  `TypeAheadCommandsTests` 6 (place, read, words and once-per-machine, ranking, attached, this Mac's real folders);
  5 bites (the separators, `/etc/paths`, the cache, each attachment). Mac `GlassTerminalTests` 1,237 passing.
- **0.4.608** (Mac and iPhone): the first 0.4.608 build started before the PATH edits and was not installed;
  rebuilt from the settled tree. Installed 2026-11-07 00:03, read back on both. His word on it: "Looking really
  good", with a screenshot of `cd ~/Software/gl` offering nothing.
- **2026-11-07, typed paths:** a word with a slash had been left alone on purpose ("names inside a subfolder are a
  later step"). Now `TerminalTypeAheadFolder` lists the folder a typed path names (`folder(of:in:home:)`: `~/` is the
  terminal's home, dropped on a server whose SFTP paths start there; `/…` as is; relative in the shell's folder;
  escapes undone; nil for `~user/` and quotes) and offers its names after what was typed, a folder with its slash.
  Only names are read for those (no git, scripts or targets), 48 folders kept, all marked stale after any command.
  Hidden names now only once the dot is typed, here and in the shell's folder, as zsh completes them (so `cd ` no
  longer offers `.git/` first). `addFolder` takes `home` (this Mac's, or "" for a server). Tests: `pathFolders`,
  `hiddenNames`, `localPaths` (his line on a real folder: `cd ~/Software/glass/` chosen), `macHome` (through the
  controller); 4 bites. Mac `GlassTerminalTests` 1,241 passing. 0.4.609 built for the Mac and iPhone.
- **2026-11-07, his check of 0.4.609 on the Mac:** "Looks friggin amazing now", and Scale Text still works in tmux.
  Still open for him: the accept key (→ as built, or Tab), commit, the headset install.
