# Removed code: what it was, and where it still lives in git

Code that only had historical value comes out of the tree (docs/design/refactor-plan.md, bucket 1), and this file keeps
its story. Each entry says what the code did, what replaced it and why, and the commit that removed it.

Getting any of it back: `git show <removal commit>^:<path>` prints a removed file as it was just before removal, and
`git checkout <removal commit>^ -- <path>` restores it. `git log --diff-filter=D --stat -- <path>` finds the removal
commit if you only know the path.

Entries are grouped by the wave that removed them. Newest first.
