# A later round on a PR you already reviewed

The fix round is a bounded diff against findings you already hold. Run the same reviewers on it, briefed with the ledger, not a blank slate.

1. **Rebuild the ledger before reading code:**
   - the original review body: `gh api repos/<owner>/<repo>/pulls/<N>/reviews/<id> --jq .body`;
   - every inline comment: `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate`;
   - the author's PR-level replies, which are on `repos/<owner>/<repo>/issues/<N>/comments`, not pulls;
   - the reviewed range `old-head`, from the original summary, and the new head.
2. **Use a fresh local branch and worktree** (`pr-<N>-rereview`). Diff `old-head..new-head`, but keep the whole-PR files available: fixes splice into context the hunk does not show. Exclude commits that only merged the base branch in (`git log old..new ^origin/<base>`).
3. **Verify each fix as a claim.** For each original finding, find the fix, then ask what wrong implementation the new test would still pass. A fix that calls an external service and was never tested against it deserves a re-read of the provider's docs against the exact request the code builds.
4. **Re-check the author's pushback independently.** If the original finding was wrong, say so in the summary.
5. **Re-run the base-branch drift check:** merge conflicts (`git merge-tree --write-tree origin/<base> <head>`), migration-graph forks, new required settings.
6. **Grade and post the same way** (`posting.md`). Re-review items are often not new findings ("worth a close look", a sequencing ask); ask the user how to frame each. The event follows the same rule: `APPROVE` once nothing Blocking remains.
7. **After posting, resolve the old threads whose fixes you verified**, in one GraphQL request with aliased `resolveReviewThread` mutations (about 30 per request at most). Keep threads that still wait on someone open.
