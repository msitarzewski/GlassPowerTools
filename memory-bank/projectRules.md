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
