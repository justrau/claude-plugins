# claude-plugins

Claude Code plugins I use myself and share with my team.

## second-look

A second pair of eyes for your code before it merges. It adds a code reviewer to Claude Code that:

- **looks harder where it matters.** A CSS tweak gets a few minutes; a change to sign-in, payments, data, background jobs or infrastructure gets a full review.
- **checks what's missing, not only what's wrong.** A missing alarm, test, setting or migration counts, even when every changed line is fine.
- **looks at the other side.** When a change configures or calls another repository or service, it checks that side too.
- **only reports what it verified.** Every finding comes with the file and line, what goes wrong and how to fix it.

You also get two commands: one to review a whole pull request, and one to write a short `REVIEW.md` that tells reviewers where to look in a project.

### Install

In Claude Code:

```
/plugin marketplace add justrau/claude-plugins
/plugin install second-look@justrau
```

Updates: run `/plugin marketplace update justrau`, or turn on auto-update for this marketplace under `/plugin` → Marketplaces.

### Don't want to install a plugin?

That's fine. Everything here is plain Markdown. Point your own Claude Code session at this repository and ask it to copy the reviewer agent and the skills into your setup. Then you own the files and can change them as you like:

> Copy the second-look reviewer agent and skills from https://github.com/justrau/claude-plugins into my ~/.claude setup. Follow the "For agents" section of its README.

### Use

- Ask "review this PR" or "review my branch", or run `/second-look:pr <PR URL or number>`.
  - **Your own change:** it verifies the findings and fixes them on your branch.
  - **Someone else's PR:** it grades the findings with you, drafts the comments, and posts one GitHub review after you approve the wording. A project's `REVIEW.md` can set its own grade labels and posting rules.
  - Add `codex` to run a Codex reviewer in parallel, for example `/second-look:pr 133 codex`.
- Ask "write a REVIEW.md for this repo", or run `/second-look:guide`.
- Claude can also start the reviewer by itself, for example before opening a pull request.

## tidy

A cleanup pass for a pull request that only runs when you ask for it. It makes the code a branch adds simpler to read and change, without changing what it does:

- **stays in scope.** It edits only lines the PR or branch adds or changes (a path narrows that). Problems in older code, and files with your uncommitted edits, are proposed, not edited.
- **keeps behaviour.** Outputs, errors, side effects and their order, public contracts, queries and user-visible text stay the same. It never removes a safety check.
- **lets tests guard it.** It runs the narrowest tests after each change, adds a test that pins today's behaviour where none exists and proves it can fail, and never edits a test to get a pass.
- **applies the safe part, proposes the rest.** Small, test-guarded simplifications go into their own `Tidy:` commit; performance, design and contract changes come back as numbered proposals you pick from.

It is not a bug hunt (use a reviewer for that) and not a style pass.

### Install

```
/plugin marketplace add justrau/claude-plugins
/plugin install tidy@justrau
```

### Use

- Ask "tidy this PR" or "clean up my branch", or run `/tidy:pr [PR, branch, range or path]`.
- Add `report` to change nothing and get proposals only, for example `/tidy:pr 42 report`.
- Pick proposals afterwards with "apply 2, 4" or "apply all".
- It commits the cleanup on your branch (never on the default branch), has it reviewed by your reviewer agent if you have one (for example `second-look:reviewer`), and pushes and adds one line to the PR description only when you ask for a push or your instructions say to push.
- Its description tells Claude to start it only when you ask. Claude Code's built-in `/simplify` is a different command: it applies fixes to the diff directly, without the test and scope rules above.

Credits for the ideas and phrasing it borrows are in [plugins/tidy/CREDITS.md](plugins/tidy/CREDITS.md).

---

## For agents

### Layout

```
.claude-plugin/marketplace.json          marketplace "justrau"
plugins/second-look/
  .claude-plugin/plugin.json
  agents/reviewer.md                     subagent; installed as second-look:reviewer
  skills/pr/SKILL.md                     skill; installed as /second-look:pr
  skills/pr/posting.md                   grading and posting a review of someone else's PR
  skills/pr/rereview.md                  a later round on an already-reviewed PR
  skills/pr/check_anchors.py             checks a review payload's inline anchors before posting
  skills/guide/SKILL.md                  skill; installed as /second-look:guide
plugins/tidy/
  .claude-plugin/plugin.json
  skills/pr/SKILL.md                     skill; installed as /tidy:pr
  CREDITS.md                             sources the skill borrows from, with their licences
```

### Copying instead of installing

When a user asks you to copy these files rather than install the plugin:

1. Copy `plugins/second-look/agents/reviewer.md` to `~/.claude/agents/<name>.md`. Pick a name that does not clash with an agent the user already has (for example `second-look-reviewer`), and set the `name:` field in its frontmatter to match.
2. Copy `plugins/second-look/skills/pr/` and `plugins/second-look/skills/guide/` to `~/.claude/skills/<name>/`. The names `pr` and `guide` are too generic outside the plugin's namespace, so rename them, for example to `second-look-pr` and `second-look-guide`. Set each `name:` field to match.
3. In the copied `pr` skill, replace the reviewer agent's name (`second-look:reviewer`) with the name you chose in step 1, and the `guide` skill's name with the one you chose in step 2.
4. The reviewer's frontmatter pins `model: claude-opus-5-5` and `effort: xhigh`. Keep them unless the user says otherwise.
5. For one project only, copy into that project's `.claude/agents/` and `.claude/skills/` instead of `~/.claude/`.
6. Tell the user the final names and how to call them.

These steps are for `second-look`. To copy `tidy`, copy only `plugins/tidy/skills/pr/` to `~/.claude/skills/tidy-pr/`, with `plugins/tidy/CREDITS.md` next to its `SKILL.md`. Set the `name:` field to `tidy-pr` and replace `/tidy:pr` in its description and text with `/tidy-pr`. Do not name it `simplify`: Claude Code has a built-in skill of that name.

### How the reviewer works

- **Size up first.** It reads the change, the project's `CLAUDE.md` / `AGENTS.md`, and every `REVIEW.md` from the repository root down to the changed folders. Then it picks Light, Standard or Deep from the risk of the change.
  - **Light:** styling, copy, docs, tests, static assets, isolated markup.
  - **Standard:** ordinary logic, stateful UI, refactors, dependency bumps.
  - **Deep:** auth, sessions, crypto; money; data writes and migrations; concurrency, queues, schedules; external APIs and webhooks; infrastructure, CI/CD, secrets; public contracts; switching a feature on in production.
- **Method.** It verifies every finding in the code (CONFIRMED or PLAUSIBLE) and tries to refute it first. It treats the PR description as claims to prove, follows the callers of changed shared code, and asks what is missing and what happens on deploy, rollback and switch-on.
- **Checklist.** A 13-area checklist at Standard and Deep, with "n/a" for areas that don't apply.
- **Report.** Depth and the guides read; findings with severity, `path:line`, a failure scenario and a fix; clean bills; questions for the author; "declined to judge"; nits; a one-line verdict.
- **Read-only.** It never edits, commits, pushes or posts.

### REVIEW.md

An optional file of at most about 80 lines in a repository's root. It says where to look: sibling repositories, where things run, which changes have another side, known traps, and what a reviewer may run. It never repeats the rules in `AGENTS.md` / `CLAUDE.md`. Most repositories don't need one. `/second-look:guide` writes it on request.

## License

MIT
