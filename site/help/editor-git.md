# Use Git in the Editor

When a project's folder is in a git repository, the Editor shows what changed and does the rest of git too: staging a whole file, a hunk or single lines; committing and amending; pulling, pushing and fetching; branches, the history, stashes and tags; merges and rebases, with the conflicts they stop on; who changed each line; and cloning a repository.

The Editor runs git where the folder is: this Mac's own git for a folder on this Mac, and the server's git, over the project's SSH connection, for a folder on a server — with that machine's keys and remotes. So a server's project has all of this on iPhone, iPad and Apple Vision Pro too. If git isn't installed there, the Editor says so and how to install it. It needs Git 2.16 or later; with an older one, it says so, and to update it there.

> [!NOTE]
> A folder on an iPhone, iPad or Apple Vision Pro itself shows no git: there is no git on those devices for the app to run.

## Open Source Control

The foot of the file list shows the branch and how many files differ from the last commit. The file list marks each changed file: **M** modified, **A** added, **D** deleted, **R** renamed, **U** new and not yet added to git, **!** a conflict.

- A staged file's letter is drawn on its color, as a badge. A dot beside the badge means the file has changed again since it was staged: a commit takes the staged version.
- An orange dot marks a folder with a changed file somewhere inside it, and a red dot a folder with a conflict.
- Files and folders git ignores, from `.gitignore`, are dimmed.
- Hold the pointer over a mark, or on Vision Pro look at it, to read what it means. A renamed file's says where it came from.

Choose the branch to open **Source Control**, a tab in the editor window. Right-click the branch, or pinch and hold it, for **Show History**, **Show Branches**, **Pull**, **Push** and **Fetch**. **On Mac:** the **Git** menu has each part of Source Control (**Show Changes** is ⌃⇧G), **Pull**, **Push**, **Fetch**, **New Branch…**, **Stash Changes…**, and **Blame** and **File History** for the file in front.

Along the top of Source Control:

- **The branch**, as a menu: choose another branch to switch to it, **New Branch…** to make one, or **Show Branches**.
- **Pull**, **Push** and **Fetch**, with how many commits are waiting each way (see [Pull, push and fetch](#pull-push-and-fetch)).
- **Changes**, **History**, **Branches**, **Stashes** and **Tags**: the parts of Source Control.
- **Diff Options** (the sliders): **Unified** or **Side by Side**, how many lines around each change (**3**, **10** or the **Whole File**), and **Ignore Whitespace**. They apply to every diff.

Diffs also follow the window's **Wrap Long Lines** (see [Editor settings](editor-settings.md)). With it off, each line stays on one line, and each hunk's lines scroll sideways together under its bar.

Source Control keeps itself up to date while it is open. When git can't do something, the line under the top says why and what to do; choose its close button to dismiss it.

### Show only changed files

**Show Only Changed Files**, the filter button beside the branch at the foot of the file list, shows only the files git sees as changed and the folders that hold them, every folder open until you close it. Deleted files and folders are listed too, struck through; choose one to see it in **Changes**. The **Filter** field still applies. When nothing has changed, the list says **No Changed Files**. Choose the button again, now **Show All Files**, to see every file.

## Changes

**Changes** lists every changed file with its lines, in one scroll. Files are in up to three lists:

- **Conflicts**: files a merge, a rebase, a cherry-pick or a stash stopped on (see [Resolve conflicts](#resolve-conflicts)).
- **Staged Changes**: what the next commit holds, against the last commit. This list appears once something is staged.
- **Changes**: what isn't staged yet, against what is staged, with new files in full.

A file staged and then changed again is in both lists. A renamed file shows **from** and the path it had. Choose a file's name to fold its lines away, its open button to open it, or a line to open the file at that line. Changed words inside a changed line are highlighted. Right-click a file for **Stage**, **Unstage**, **Discard Changes…**, **Open**, **Blame**, **File History**, **Open on GitHub** and **Copy Path**.

### Stage files, hunks and lines

- **A whole file:** choose the box beside its name. An empty box stages the file; a ticked box, in Staged Changes, takes it back out. The file itself isn't changed. **Stage All** and **Unstage All** do every file.
- **A hunk:** each run of changes has a bar above it with **Stage Hunk** and **Discard Hunk** in Changes, or **Unstage Hunk** in Staged Changes.
- **Single lines:** choose the line numbers of the added or removed lines you want. They're marked, and the bar's buttons read **Stage 2 Lines** (or **Unstage**, **Discard**) and act on those lines only. **Clear** chooses none again. Right-click one line to stage, unstage or discard just that line.

Hunks and lines can be staged in a file that changed, not in a file that's new, deleted, renamed or binary, which is staged whole. While **Ignore Whitespace** is on, lines can't be staged one at a time: the hunks no longer match the file.

### Discard changes

**Discard Changes…** on a file, **Discard Hunk** and **Discard Lines** throw away changes that aren't staged: the file goes back to what is staged, or to the last commit. A new file is deleted. **Discard All…** does every file in Changes. Each asks first, because none of it can be undone; what is staged is kept.

### Commit

Type a message in **Message** and choose **Commit**, or press ⌘↩. When nothing is staged the button reads **Commit All** and stages every file in the list first. After the commit, Source Control says which commit it made.

Choose **Amend** to replace the last commit instead: its changes and what is staged now go into one commit, with the message. The message starts as the last commit's; leave it empty to keep that one.

If the project is a folder inside its repository, files staged elsewhere in the repository would be committed too, and **Changes** doesn't list them. Source Control names them and asks first. If git won't commit, it says why, for example when git doesn't yet know your name and email on that machine, or when a hook stopped the commit.

## Pull, push and fetch

- **Pull** with a count, when the remote has commits this branch doesn't. A pull only ever moves the branch forward. Open files the pull changed are read again; one with unsaved edits keeps them, the Editor says so, and saving it asks which version to keep.
- **Push** with a count, when this branch has commits the remote doesn't.
- **Fetch** asks the remote what's new, so the counts are current.
- **Publish Branch**, in place of these, when the remote doesn't have this branch yet: it pushes the branch and makes it follow the remote's.

While one runs, Source Control says **Pulling…**, **Pushing…** or **Fetching…**. When git can't go ahead it says why and what to do: the remote has commits this branch doesn't (pull first); the remote's host key isn't known yet, or a key or password isn't set up (connect, or run the command once, in a terminal on that machine); there's no remote. When the branch and the remote have both moved on, merge or rebase them from **Branches**. A pull, push or fetch that takes longer than ten minutes is stopped.

## History

**History** lists the commits, newest first, with lines showing how they branch and merge, and the branches and tags at each. Choose **All Branches** or just the branch you're on. The list reads more as you scroll.

Choose a commit to see its message, author, date, hash and parents, and its changes. Choose a parent to go to it. **Actions**, or right-clicking a commit, has:

- **Copy Hash**, **Copy Message**, and **Open on GitHub** (or the remote's own site).
- **New Branch Here…** and **New Tag Here…**.
- **Check Out This Commit…**: the files become that commit's, on no branch.
- **Cherry-Pick**: the commit's changes, made again as a new commit on this branch.
- **Revert…**: a new commit that undoes it.
- **Amend…** on the last commit, which opens Changes with **Amend** on.
- **Reset to Here**: moves the branch back to the commit, keeping the changes since staged (**Soft**), keeping them unstaged (**Mixed**), or throwing them away (**Hard**). Each asks first.

A file's own history: right-click it in the file list and choose **File History**, or choose **Git ▸ File History** on a Mac. It opens in a tab of its own, follows the file across renames, and shows each commit with that file's changes first.

## Branches

**Branches** lists this repository's branches, then each remote's. The one checked out is ticked. Each shows the branch it follows, how far ahead (↑) and behind (↓) it is, and its last commit. Type in **Filter** to find one. Double-click a branch to switch to it, or right-click it for:

- **Switch To**, or **Check Out as** for a remote's branch, which makes a local branch that follows it.
- **Merge into** the branch you're on, or **Rebase** the branch you're on **onto This**.
- **New Branch from This…**, **Rename…**, **Push** (or **Publish**).
- **Open on GitHub**, and **Create Pull Request** (on GitLab, **Create Merge Request**), which opens the remote's page for it.
- **Delete…**, or **Delete on origin…** for a remote's branch. A branch whose commits are on no other branch asks again before it's deleted.

Switching branches, like merging, rebasing and every other change git makes to the files, reads open files again: one with unsaved edits keeps them, and saving it asks which version to keep. Git won't switch when your uncommitted changes would be overwritten; Source Control says so, and you commit or stash them first.

## Resolve conflicts

When a merge, a rebase, a cherry-pick, a revert or a stash's changes collide with yours, git stops and Source Control shows a bar with what is under way — **Merging**, **Rebasing** (with how far it has got), **Cherry-picking** or **Reverting** — and how many files have conflicts.

In **Changes**, under **Conflicts**, choose **Resolve…** beside a file. Each conflict shows **Ours** (the branch you're on) beside **Theirs** (what came in). For each, choose **Use Ours**, **Use Theirs**, or in **Use**, both in either order. Then choose **Save and Mark Resolved**. To settle the whole file one way, choose **Take** ▸ **Take Ours** or **Take Theirs**. To resolve it by hand, open it, edit it, save it, and choose **Take** ▸ **Mark as Resolved**.

When no conflicts are left, choose **Continue** in the bar to finish: a merge makes its merge commit. **Skip** leaves out the commit a rebase or a cherry-pick stopped on. **Abort** puts everything back as it was before it began.

## Stashes

**Stash Changes…** (in **Stashes**, or the Git menu) puts your uncommitted changes away and takes the files back to the last commit. Give it a message if you like, then choose **Stash**, or **Stash Including New Files** to put away files git doesn't know yet too.

**Stashes** lists them, newest first. Choose one to see its changes. **Apply** brings them back and keeps the stash; **Pop** brings them back and drops it; **Drop…** deletes it.

## Tags

**Tags** lists the repository's tags, newest first. **New Tag…** tags the commit you're on (History tags any commit); give it a message to make an annotated tag. Double-click a tag to see its commit in History, or right-click it for **Check Out…**, **New Branch Here…**, **Push**, **Open on GitHub**, **Delete…** and **Delete on origin…**.

## Blame

Right-click a file in the file list and choose **Blame**, or **Git ▸ Blame** on a Mac, to see who last changed each line and in which commit. Each run of lines from one commit is labelled once with its commit, author and when; newer commits are shaded darker, and lines not committed yet are marked. Choose a commit to see it in History, or double-click a line to open the file there.

## Clone a repository

- **On Mac:** choose File ▸ **Clone Repository…**, paste the repository's address (as its Clone or Code button gives it, such as `git@github.com:owner/repo.git` or `https://github.com/owner/repo`), and choose the folder to clone it into. It opens as a project when it's done.
- **Anywhere, on any machine:** right-click a folder in a project's file list and choose **Clone Repository Here…**. A project on a server clones on the server, with its keys.

## Marks beside the lines

An open file in a git project marks its changed lines beside the line numbers:

- **Green**: lines added since the last commit.
- **Amber**: lines changed.
- **Red wedge**: lines removed at that point.

The marks follow what you type before you save, and clear once the change is committed. A file git doesn't track yet is marked green throughout. With line numbers turned off, a narrow strip keeps the marks.
