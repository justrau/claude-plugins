# A later round on a PR you already reviewed

The fix round focuses on what changed since your last review, but it is judged in the context of the whole PR and of every review on it. Detect it before any reviewer starts (`SKILL.md` section 1) and brief the reviewers with the ledger, not a blank slate: the new commits to focus on, the whole PR as context, and every review and comment since your last one (other developers', bots', the user's). One review of the whole PR that carries the ledger is enough; do not run a separate bounded review as well.

1. **Rebuild the ledger before reading code:**
   - the original review body: `gh api repos/<owner>/<repo>/pulls/<N>/reviews/<id> --jq .body`;
   - every inline comment: `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate`;
   - the author's PR-level replies, which are on `repos/<owner>/<repo>/issues/<N>/comments`, not pulls;
   - the reviewed range `old-head`, from the original summary, and the new head;
   - every review and comment by others since your last review, and which of your points they discussed;
   - the user's own record of the earlier round, when their instructions or the repository keep one: what was graded, skipped or made moot, so skipped points are not raised again.
2. **Use a fresh local branch and worktree** (`pr-<N>-rereview`). The author's own commits since the last round are `git log --no-merges <old-head>..<new-head> ^<baseRefOid>` (use the PR's base commit, not `origin/<base>`, which already contains a merged PR). Review each merge of the base into the branch with `git show --remerge-diff <merge>`, which shows only the conflict resolution, not the base's own commits. Run it yourself and name the output file in the brief: it writes temporary objects, which a read-only reviewer cannot. Keep the whole-PR files available: fixes splice into context the hunk does not show.
3. **Verify each fix as a claim.** For each original finding, find the fix, then ask what wrong implementation the new test would still pass. A fix that calls an external service and was never tested against it deserves a re-read of the provider's docs against the exact request the code builds.
4. **Re-check the author's pushback independently.** If the original finding was wrong, say so in the summary.
5. **Re-run the base-branch drift check:** merge conflicts (`git merge-tree --write-tree origin/<base> <head>`), migration-graph forks, new required settings.
6. **Grade and post the same way** (`posting.md`). Re-review items are often not new findings ("worth a close look", a sequencing ask); ask the user how to frame each. The event follows the same rule: on an open PR, `APPROVE` once nothing Blocking remains; a merged, closed or draft PR gets `COMMENT` (`posting.md` section 5).
7. **After posting, resolve your own old threads whose fixes you verified** (leave other reviewers' threads to them unless the user says otherwise), in one GraphQL request with aliased `resolveReviewThread` mutations (about 30 per request at most). Keep threads that still wait on someone open.
