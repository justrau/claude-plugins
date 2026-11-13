---
name: guide
description: Create or update a project's REVIEW.md, the short guide that tells code reviewers where to look - sibling repositories, where things run, which changes have another side, known traps, what a reviewer may run. Use only when someone asks to write or update one, or to add a trap a review just found to an existing one.
---

# Create or update REVIEW.md

`REVIEW.md` sits in the repository root. It says **where to look**, not how to review: the reviewer agent already knows how. It must not repeat `AGENTS.md` / `CLAUDE.md`; point at them instead. Keep it under about 80 lines, so it is read in full every time.

A nested `REVIEW.md` in a subfolder is only worth it when that folder is a different world from the rest (a monorepo's frontend, backend and infra). One root file is the default.

## Find the facts (read; do not guess)

1. The repository's own docs: `AGENTS.md`, `CLAUDE.md`, `README`, `docs/` (ADRs, runbooks, specs).
2. Where it runs and how it ships: CI and deploy workflows (`.github/workflows/`, `bitbucket-pipelines.yml`, `Makefile`, deploy scripts), Dockerfiles, which branch deploys where.
3. Its neighbours: `git remote -v`; sibling checkouts in the parent folder; repository names, hostnames and service URLs in config, env examples (`.env.example`, not `.env`), IaC, docs; webhooks sent and received; shared packages.
4. Which changes need a change elsewhere: settings read from the environment and where they are set; queues, jobs and schedules and what runs them; metrics and the alarms on them; API, webhook and event contracts and their consumers; code duplicated with another repository.
5. Known traps: the guard tests named in `AGENTS.md`; recurring findings in past review comments (`gh api repos/<owner>/<repo>/pulls/comments --paginate`, skim the last few months); incidents the docs mention.
6. What a reviewer may run safely: the test command, and whether the dev container mounts the main checkout (a worktree's tests would then test the wrong tree); read-only cloud access, if any.

Never read `.env` or other secret-bearing files. Never write secret values, hostnames of internal-only systems that are not already in the repository, or personal names into the guide.

## Write it

```markdown
# Review guide: <repo>

## The system in one minute
<table: repo | what it is | talks to>; local paths of the siblings; where it runs; which branch deploys where.

## Where a change usually has another side
- <kind of change> → <where the other side is, file or repo>

## Known traps
- <trap>: <how it shows up>

## What a reviewer may run here
- <commands, or "read only, because …">
```

Then add one line to `AGENTS.md` (or `CLAUDE.md` if that is the project's file): "Code reviews: read `REVIEW.md`." Propose the change as a small PR of its own, following the repository's PR rules.

## Update it

When a review finds a trap likely to recur, or another side of a change the guide does not list, add one line in the right section. Remove lines that are no longer true. Keep the 80-line budget: merge or drop before adding.
