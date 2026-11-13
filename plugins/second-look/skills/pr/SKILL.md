---
name: pr
description: Review a pull request, branch or commit range end to end with the reviewer agent - gather the context it needs (PR body, project review guide, sibling repositories), run it in a fresh context, verify its findings, and report or post them. Use whenever someone asks to review a PR or a branch, and before opening your own PR. Prefer this over diff-only review commands.
---

# Review a PR, branch or range

The reviewer agent from this plugin does the review (`second-look:reviewer`, or `reviewer` if you copied the files instead of installing the plugin). This skill makes sure it gets the right input, and that what reaches the author is verified.

## 1. Pin down what is reviewed

- A PR: `gh pr view <N> --json number,title,state,baseRefName,headRefName,headRefOid,body,files`. Note its state (open, draft, merged).
- Your own branch before a PR: the range `$(git merge-base origin/<base> HEAD)..HEAD`.
- Always diff from the merge-base, never from the base branch tip.
- Never check out, stash or reset in a checkout someone else may be using. For a PR, fetch it into a local branch (`git fetch origin pull/<N>/head:pr-<N>-review`) and read it with `git show` / `git diff`, or add a worktree.

## 2. Gather the context the reviewer cannot guess

Write a short brief. It is the reviewer's only context besides the code.

1. The range or PR, head SHA, base branch, and the PR description (or, for your own branch, what the change is for).
2. The review guides: list every `REVIEW.md` from the repository root down to the directories of the changed files, plus the root `REVIEW.md` of each sibling repository the change touches, and name them in the brief. The reviewer looks for them too; naming them makes sure.
3. **What the change touches outside its own repository.** For each: the other repository's local path and the files to check there (config validation, runbook or spec preconditions, published metrics, deploy workflow, API consumers). This is the step that a diff-only review cannot do.
4. Any worry you already have, and anything you already confirmed, so it is not re-derived.
5. What the reviewer may run: targeted tests only if the project's dev environment points at this checkout; read-only cloud CLI only if you allow it and name the profile.

Do not tell the reviewer how deep to go; it sizes the change itself. Do tell it if you know the change is risky.

## 3. Run the reviewer

Start the reviewer agent with the brief, in the background for anything that is not Light. One reviewer is the default. For a Deep change (auth, money, data, infrastructure), a second independent reviewer on the whole change is worth it; never split one review across two agents.

## 4. Verify before you relay

Read the code behind every Blocking or Should-fix finding yourself. Mark each as confirmed, corrected (explained by a convention or a neighbour) or wrong. Where two reviewers disagree, decide and say why. Rule on each "declined to judge" line: drop it, add it as a finding, or note it as a follow-up.

## 5. Report

- To the person who asked: the verified findings, most severe first, with `path:line`, the failure scenario and the fix; the clean bills; the verdict.
- To post on GitHub: only after the person approves. One review (`gh api repos/<owner>/<repo>/pulls/<N>/reviews`) with inline comments anchored inside diff hunks, `commit_id` pinned to the reviewed head. Event: any blocking item → REQUEST_CHANGES; none → APPROVE with the findings as comments; draft, merged or closed PR, or questions only → COMMENT. Neutral tone.
- If the user's own instructions describe a triage step, a second reviewer or a posting style, follow them.

## 6. Review guides

- Most repositories have no `REVIEW.md`. Review as usual and do not mention it or offer to create one.
- Where a `REVIEW.md` exists and the review found a trap likely to recur, or another side of a change that the guide does not list, propose the one-line addition in the report.

## 7. Fix rounds

After fixes, review only the new commits plus the files they touch, with the original findings as the brief. At most two rounds; then report what is still open.
