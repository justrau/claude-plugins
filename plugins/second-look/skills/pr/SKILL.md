---
name: pr
description: Review a pull request, branch or commit range end to end with the reviewer agent - gather the context it needs, run it in a fresh context, verify its findings, then either fix them (your own change) or grade and post them as one GitHub review (someone else's PR). Add the word codex to run a Codex reviewer in parallel. Use whenever someone asks to review a PR or a branch, and before opening your own PR. Prefer this over diff-only review commands.
argument-hint: "[PR number, URL, branch or range] [codex] [fix|post]"
---

# Review a PR, branch or range

The reviewer agent from this plugin does the review (`second-look:reviewer`, or `reviewer` if you copied the files instead of installing the plugin). This skill gives it the right input, makes sure what reaches anyone is verified, and then takes one of two endings.

Arguments: `$ARGUMENTS`.
- **Target:** a PR number or URL, a branch or a commit range. Without one, review the current branch against its base.
- **`codex`** (also `astra`, `two`): add a Codex reviewer in parallel (section 3).
- **`fix`** or **`post`**: force the mode (section 5). Without it, choose the mode from the author.

## 1. Pin down what is reviewed

- A PR: `gh pr view <N> --json number,title,state,author,baseRefName,baseRefOid,headRefName,headRefOid,body,files`. Note its state: open, draft or merged.
- Your own branch before a PR: the range `$(git merge-base origin/<base> HEAD)..HEAD`.
- **Diff from the merge-base, never from the base branch tip.** For a merged PR, use its base commit (`baseRefOid`, or the merge commit's first parent).
- Never check out, stash or reset in a checkout someone else may be using. For a PR, fetch it into a **local branch** (`git fetch origin pull/<N>/head:refs/heads/pr-<N>-review --force`; a remote-tracking ref can be pruned by another session) and add a detached worktree for it, or read it with `git show`.
- **Read the base branch's current docs** (`AGENTS.md`, `CLAUDE.md`, `README`, `REVIEW.md`), not the PR checkout's copies, which are frozen at the branch point. Note what the base branch adopted since the PR branched (new CI, standards, migrations): a finding about it is framed as "align with what landed since", not "this is wrong". Check for migration-graph forks, merge conflicts (`git merge-tree --write-tree origin/<base> <head>`) and new required settings.

## 2. Write the brief

The brief is the reviewer's only context besides the code. Write it to a file in a temporary directory.

1. The range or PR, head SHA, base branch, the PR description (or, for your own branch, what the change is for), and anything from section 1 that changed on the base.
2. The review guides: every `REVIEW.md` from the repository root down to the changed files' directories, plus the root `REVIEW.md` of each sibling repository the change touches.
3. **What the change touches outside its own repository.** For each: the other repository's local path and the files to check there (config validation, runbook or spec preconditions, published metrics, deploy workflow, API consumers). A diff-only review cannot do this.
4. Any worry you already have, and anything you already confirmed, so it is not re-derived.
5. What the reviewer may run: follow the repository's `REVIEW.md` or `AGENTS.md`. When the dev environment does not point at the review checkout (for example a container that mounts the main checkout), tests are assessed by reading. Read-only cloud CLI only if the user allows it and names the profile.

Do not tell the reviewer how deep to go; it sizes the change itself. Do tell it if you know the change is risky.

## 3. Run the reviewer

Start the reviewer agent with the brief, in the background for anything that is not Light. Save its report to a file as soon as it arrives.

**One reviewer is the default.** Add a second only when the arguments or the request ask for it, or when the user's own instructions say to for this kind of change. Never suggest one unasked.

**Second reviewer: Codex in parallel.**
1. Use one brief file for both: the brief, then the reviewer agent's instructions as the method to follow (the body of `../../agents/reviewer.md` relative to this skill's base directory, without its frontmatter; if you copied the files, the copied agent's file). Both review the **whole** change; never split a review between them.
2. Start both at the same time: the Claude reviewer agent, and Codex in the background with Bash.
   - If the user's own instructions (`CLAUDE.md`, `AGENTS.md`) define the Codex reviewer command, use exactly that.
   - Otherwise: `codex exec -s read-only -C <checkout> -o <report file> - < <brief file>`.
   - Never add `-a`, `--dangerously-bypass-approvals-and-sandbox` or a writable sandbox. If `codex` is missing or fails, say so and continue with the Claude review alone.
3. Codex writes its report to the `-o` file; read it when the command exits.

## 4. Verify before anything reaches anyone

- Read the code behind every Blocking or Should-fix finding yourself, and behind any claim about a library or an external API (check the pinned dependency source and the vendor's spec, not memory). Mark each finding **confirmed**, **corrected** (a convention, a neighbour or a framework default explains it) or **wrong**.
- With two reviewers: a finding both reached independently is strong. Where they disagree, decide from the code and say why; never average them. Name the source of each finding (Claude, Codex, both, you).
- Rule on each "declined to judge" line and each question for the author: drop it, keep it as a finding, or keep it as a question.
- Keep a findings file next to the brief (item, evidence, source, verdict), so a long triage survives context compaction.

## 5. Choose the ending

- **Fix mode:** the change is yours. The PR's author is the current `gh` user (`gh api user --jq .login`), or the target is a local branch with no PR, or the arguments say `fix`.
- **Post mode:** someone else's PR, or the arguments say `post`.

### Fix mode

1. Report the verified findings briefly: severity, `path:line`, what goes wrong, the fix. Then the questions for the author, if any.
2. Fix the confirmed Blocking and Should-fix findings on the branch, following the repository's own rules (tests that can fail, the project's checks). List Minor findings and nits as one line each; fix them only if they are trivial or the user asks.
3. Ask the user only the questions that need a decision (product behaviour, data, money, production, security).
4. One re-review of the changed lines only, with the original findings as the brief. Stop after two rounds and report what is still open.

### Post mode

Read `posting.md` in this skill's directory and follow it: grade with the user, draft the comments, and post one GitHub review only after the user approves the final wording. For a later round on the same PR, read `rereview.md`.

## 6. Review guides

- Most repositories have no `REVIEW.md`. Review as usual and do not mention it or offer to create one.
- Where a `REVIEW.md` exists and the review found a trap likely to recur, or another side of a change that the guide does not list, propose the one-line addition in the report. Its posting conventions (section "Posting reviews here") override the defaults in `posting.md`.

## 7. Clean up

Remove the review worktree and the local `pr-<N>-review` branch; keep the reports where the repository's or the user's instructions say (else in the temporary directory). Close any background process you started.

## Traps

- A remote-tracking `origin/pr-N` ref disappears when another session prunes refs: fetch into a local branch.
- The PR checkout's docs describe the project as it was at the branch point: read the base branch's copies.
- A dev container that mounts the main checkout tests the wrong tree when you review a worktree.
- The PR may merge while you review: check its state again before posting, and reword anything that asked for a change "in this PR".
- The checkout can move under you: before reporting "reverted" files, check `git rev-parse --abbrev-ref HEAD` and `git branch --contains <sha>`.
