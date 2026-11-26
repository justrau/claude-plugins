---
name: changes
description: 'Behaviour-preserving cleanup of your changes: by default the local work (uncommitted and staged changes plus the commits on the branch against its base); or a named PR, branch or commit range, optionally narrowed to a path. Applies small simplifications that tests guard and proposes the rest; cleanups of committed code go into their own commit, cleanups in uncommitted files stay uncommitted. Use only when the user asks to tidy or clean up their changes, branch or a PR ("tidy my changes", "tidy this PR", "clean up my branch", "/tidy:changes"); prefer it over the built-in /simplify for this. Never start it on your own after implementing, before opening a PR, or as part of another task.'
argument-hint: "[PR number, URL, branch, range or path] [report]"
---

# Tidy your changes

Make the code in scope simpler to read and change without changing what it does. This is not a bug hunt and not a style pass. Run it only because the user asked: a cleanup nobody asked for is churn.

The user's request is the authorisation. Apply what is safe without asking again, and propose the rest. With the word `report`, change nothing and propose everything.

## 1. Resolve the scope

Run `git fetch origin` first. Then resolve the scope in this order, and state it in one line before you edit anything:

1. **A PR.** Read `gh pr view <n> --json number,url,state,author,baseRefName,headRefName,headRefOid,isCrossRepository`. The scope is `git diff origin/<baseRefName>...<headRefOid>`. Edit only when all of these hold; otherwise report only:
   - the PR belongs to this checkout's repository (`gh repo view --json nameWithOwner`) and is open;
   - the checked-out branch is `headRefName` and `git rev-parse HEAD` equals `headRefOid`;
   - the PR's author is the current user (`gh api user --jq .login`), or the user said they maintain it. Never push to someone else's PR.
2. **A branch or range.** The branch against the base of its open PR, else against the default branch, always as `origin/<base>`, never a local base branch that may be behind and never `@{upstream}`. Edit only when the branch, or the end of the range, is what is checked out.
3. **Nothing named:** the current branch as in 2, plus staged and unstaged changes and new files.
4. **A path** narrows any of the above to that path. Lines the scope changes there follow the normal rules. The rest of the path is report-only: its findings are Proposed.

An empty diff means nothing to tidy. Say so in one line and stop. Do not fall back to the last commit or to the whole repository.

Edit only lines the scope adds or changes, plus what such an edit cannot be separated from (the enclosing expression, an import, a call site of a symbol the scope renamed). Read callers and unchanged code freely, but never edit unchanged code for its own sake; propose it.

Leave out: generated and vendored files, lockfiles, migrations that may already have run, documentation and other prose, and code the branch moves, copies or ports from elsewhere, because a port keeps its shape.

**Uncommitted work is in scope, and it is the user's.** A *user file* is any file with staged or unstaged changes, or any untracked file, that this run did not create. Before the first edit:
- Run `git status --porcelain`, then save a recovery point: `R=$(git stash create)`; if that prints nothing (a clean tree), use `R=$(git rev-parse HEAD)`. The command changes no file, no index entry and no stash list.
- Copy every untracked user file to a scratch directory outside the repository (`mktemp -d`); the recovery point does not hold them.

In a user file:
- never run `git restore`, `git checkout --`, `git stash`, `git reset` or `git add` on it; undo a change by reversing your own edit;
- never stage or commit it: the cleanup stays in the working tree next to the user's work. A file the user had fully staged then shows your cleanup as an unstaged change on top; say so in the report;
- a logical change that touches or depends on a user file stays wholly uncommitted, including its pinning test and any edit in other files.

The report gives R, the scratch directory, and for each tracked user file the commands that bring it back: `git restore --source=<R> --worktree -- <file>`, plus `git restore --source=<R>^2 --staged -- <file>` when R came from `git stash create`. R is an unreferenced commit, so `git gc` may prune it after about two weeks.

## 2. Read before you judge

- Read the project instructions (`CLAUDE.md`, `AGENTS.md`, and those in the folders of changed files). The project's conventions beat taste.
- For each change, read the enclosing function and its callers. Before you remove anything, find out why it is there (`git log -L`, blame, the PR description). If you cannot tell, keep it.
- Find the tests that cover each changed file, and note the files that have none.

## 3. Find

Look at the scope from these angles. For each finding, say what it costs and who pays for it.

- **Reuse:** new code that re-implements a helper, framework feature or standard-library call the project already uses. Name the existing symbol.
- **Simpler form:** state that can be derived, copy-paste with small differences, nesting three or more levels deep, dead code the change left behind, a parameter or setting that only one caller uses or that nothing varies, an abstraction with one implementation and no testing need, compatibility code for a shape that never shipped.
- **Wasted work:** repeated queries or calls, N+1 queries, independent calls made one after another, work added to start-up or a hot path, loading everything to use one item.
- **Depth:** a branch for one case added to shared code. Name the general fix in the shared code instead.
- **Dependencies:** a dependency the change added for one or two small things. Name the few lines of local code that would replace it.

These are not findings: style the linter or conventions do not state, renames to taste, line count, comment rewording, and correctness bugs. List suspected bugs under **Separate defects** and leave them for a review; do not fix them here.

## 4. Behaviour you must keep

A change is safe only when all of these stay the same:

- outputs, return values, serialised formats and error types, including when an error is raised;
- side effects and their order: writes, calls, events, jobs, logs and metrics that someone reads;
- public contracts: exported signatures, routes, payloads, database schema, config keys, CLI flags;
- queries and calls: never add one; never reorder results;
- user-visible text, accessibility, focus and layout.

Never simplify away authorisation, validation, escaping, data-loss guards (transactions, locks, idempotency keys, bounded retries), rollback and recovery paths, compatibility that something still needs, deliberate duplication the project instructions or a plan pin, compiler or tool directives, licence headers, and comments that explain a constraint the code cannot show.

If you cannot show that a change keeps all of this, do not apply it. Propose it with "equivalence not shown".

## 5. Apply or propose

| Group | Rule |
|---|---|
| **Applied** | Reuse and simpler-form findings in production code inside the editable scope, whose equivalence you can show and that a test covers. A test covers lines only if breaking those lines makes it fail. For a removal (dead code, an unused parameter), the evidence is instead a project-wide search, including dynamic calls and framework conventions, plus a passing build or type check. |
| **Applied after a test** | The same, but no test covers the lines. First add a new test that pins today's behaviour and passes on the current code. Prove it can fail: break the code on purpose, watch it fail, put your own edit back and `touch` the file (build and bytecode caches can keep the broken version when the restore lands within the same second), and watch it pass again. Then apply. If such a test would cost more than the cleanup is worth, propose instead. |
| **Proposed** | Wasted-work, depth and dependency findings; anything touching a public contract; test code, including tests the branch added; report-only files and paths; judgement calls; everything in `report` mode. |
| **Skipped** | False positives and findings not worth their cost, with one line why. |
| **Separate defects** | Suspected bugs found on the way. |

Never edit, weaken, rename or delete a test, including tests the branch added, and never update an expected value. The only test change is adding a new pinning test.

Apply one logical change at a time. After each, run the narrowest tests that cover it (the test file, or the named tests). If one fails, reverse your own edit and move the finding to Proposed with the failure. Do not stage anything while you work.

## 6. Verify, commit, review

- At the end, run the project's formatter in check mode on user files, and on the other touched files only, never on the whole repository; then its linter and type checker, the targeted tests of every touched file, and any guard tests the project instructions list. Run a full suite only when a change reaches shared code that targeted tests cannot cover. If the project has no tests or checks, say so.
- **Where to commit.** Cleanup in user files, and any logical change that touches or depends on one, is never committed (section 1). On the default branch, a protected branch or a release branch, never commit or push: leave the changes uncommitted and report. Elsewhere, commit the rest in one or a few commits that start with `Tidy:`, on the same branch, with a pathspec so the user's staged work stays out: `git commit -m "Tidy: …" -- <files this run changed>`, after `git add -- <new files this run created>`. Never `git add -A` or a plain `git commit`. Check `git show --stat HEAD` lists only your files. If the cleanup would read better as its own PR, propose that; do not create one unasked.
- **Review.** Always, whether or not anything is committed or pushed, have every edit this run made reviewed for behaviour changes by the code reviewer agent the user's setup uses (for example `second-look:reviewer`). Give it `git diff <R>` (only this run's edits to tracked files, committed or not, without the user's earlier work) plus the new files this run created. When it confirms a behaviour change, revert that change and move it to Proposed; do not patch it, because a patch is a new, unreviewed change. If no reviewer agent is available, say the review was skipped.
- **Push** only when the user asked for it or their instructions say to push work on their PRs, and only to the PR's head branch, never with force. Then read the PR's current description and append one line, such as "Tidy pass: 5 cleanups, no behaviour change." Without a push, stop at the local commits, or at the uncommitted cleanup, and say so.

## 7. Report

Open with one line: the scope (base and head, or the path), the number of findings per group, the test result, what was committed and what stays uncommitted, and whether the edits were reviewed and pushed. Then give the recovery point and restore commands from section 1. Then number every finding:

| # | Location | Cost | Change | Kept behaviour | Evidence | Group |
|---|---|---|---|---|---|---|

Group related findings under the one change that removes them. End with how to apply proposals: "apply 2, 4" or "apply all".

"Apply" picks only Proposed items, never Skipped or Separate defects. Before applying a pick, check it against the current code again, and skip it with a reason if the code changed. Take a new recovery point first. A picked item still follows sections 4 to 6: the test gate, a `Tidy:` commit where section 6 allows one, and the review. A picked change to a public contract is named in the commit message and in the PR line.

If the user's instructions say how to report or ask questions, follow them; do not open a question dialog to ask which proposals to apply.

## Not in this version

Deleting comments or tests, tidying whole repositories or folders as they stand, architecture passes, parallel reviewer agents, running automatically after implementation, and language-specific rules (the project's conventions cover those).
