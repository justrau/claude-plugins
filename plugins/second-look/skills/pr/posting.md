# Post mode: grade, draft, post

For someone else's PR. Nothing is posted, and no issue is opened, until the user has approved the final wording. Grading an item is not approval to post it.

The defaults below apply unless the repository's `REVIEW.md` has a "Posting reviews here" section, or the user's own instructions say otherwise; those win.

## 1. Prepare one triage item per finding

Each item carries:
- An ID (`T1`, `T2`, …), the finding in one line, `path:line`, the failure scenario, the fix, confirmed or plausible, and its source (Claude, Codex, both, you).
- **A draft of the comment's first line** in house style (section 4).
- **A proposed destination with one line of why:** a review comment when the finding is within the PR's task; a separate issue when it is outside it but surfaced by the PR, or when it is about the whole repository rather than this PR; the repository's client-questions document when `REVIEW.md` names one and the point is a product or client question.
- **A recommendation:** the grade you propose and why. The reviewer's severity is only a proposal; grade from the code. Compare with how the user graded the same kind of point before when their own records or triage tool hold past grades (or an earlier round on this PR); otherwise leave the comparison out.

Also add:
- One item per **question for the author**, with the draft question.
- One item per **question someone asked in the PR conversation**, a person or a bot: a draft reply of a few lines that answers it and links the comment or issue holding the detail. These get their own reply, not a line buried in the summary. Note whether the question is in an inline review thread or at PR level; the reply goes to the same place (section 7).
- In a later round, one item per **author pushback you re-checked**, with your ruling (the decline stands, or the point is raised again).
- One item per **point another reviewer raised that is worth attention** (a developer, a bot or an AI review tool): a draft reply in its thread that says whether it is correct and important (with evidence, or what to add), or why it is wrong. Routine points that need no answer get no item. Never post a new comment that repeats an existing point; reply to it instead.
- One item for the **review event** (section 5) and the summary.

## 2. Grade with the user

- **Where:** if the user's own instructions name a triage tool, page or skill, use it (load the skill). Otherwise triage in chat: present the items in severity order, each with the grade choices on one line, and let the user answer with item ID and grade.
- **Default grades:** 1 Blocking · 2 Should fix · 3 Minor · 4 Minor, to think about · 5 Skip. Skip means not posted.
- Label items with their IDs, never a Markdown ordered list that starts mid-way: renderers renumber `4. 5. 6.` to `1. 2. 3.`, and the user's "6" then means another item.
- **Expect a design question instead of a grade** ("why not serve it from the CDN?"). Answer it from the code, then ask again. One decision can make other items moot; record those as "not posted, made moot by T1".
- The user's note on an item overrides your draft wording.
- Record every decision and wording instruction in the findings file as it happens.

## 3. Close triage

Give the counts (posted, skipped, moot, issues), show the **final wording** of every comment, issue and reply, and the review event. Ask once whether to post. Post only after a clear yes.

## 4. Comment shape and tone

- **First line, bold:** the grade label and the claim, for example `**Should fix: the retry loses the original error.**`. The verb carries the kind: "Confirm …", "Consider …". When the repository's `REVIEW.md` defines its own label or tag (for example `**[BLOCKING]**`), it **replaces** the grade label. A reply that asks for a change carries a grade label too; a reply that only agrees or answers does not.
- Then prose with the concrete failure scenario, the neighbouring code that already does it right (`path:line`), and the suggested fix.
- *Italic asides* for context that is explicitly not a request.
- Neutral and factual: no "please", no softening, no exclamation marks. Credit what is right in the summary.

## 5. Review event

- Any **Blocking** item → `REQUEST_CHANGES`. It is sticky until a later review, so never use it for Should fix.
- No Blocking item → `APPROVE`, with the findings as comments and one summary line on what the approval covers ("nothing blocking; the should-fix points can land here or in a follow-up PR").
- A draft, merged or closed PR, or a review that only asks questions → `COMMENT`.
- Approve only the head commit you reviewed. If the head moved, review the new commits first.

## 6. Summary body

1. Who reviewed it, and the range `base..head` (a later round needs it). Name every reviewer by agent and model as it actually ran, and who verified the findings, for example: "Reviewed `30bc148..87ab5f3` by the second-look reviewer (Claude Opus 5.5) and Codex (`gpt-6-astra`, xhigh), each over the whole change; Claude Opus 5.5 checked every finding against the code." When one model did everything, say so ("Reviewed by Claude Opus 5.5 alone"). Take the names from what ran (the agent definition's model, the Codex command's `-m`, your own model), never from memory, and never write "two agents" without naming them. Keep this one line even when the repository's `REVIEW.md` fixes the summary's headings, and in every later round.
2. What is right, unless the repository's `REVIEW.md` says not to list it. In a later round, the round-1 points whose fixes you verified go in one clause under the findings.
3. What changed on the base branch under the PR, if anything, and one line on the other reviews: which points you confirm and which you disagree with (the detail is in the thread replies).
4. The shape of the findings: counts, and how many edits they really collapse into.
5. Follow-ups on our side, so the author does not act on them.
6. Questions that need a decision rather than a code change.
7. The issues opened for out-of-scope findings, one line each with its link.

Answers to questions from the PR conversation are replies in that conversation, not part of the summary.

## 7. Post

**Order, so every link exists when it is written:**
1. Open the out-of-scope issues (`gh issue create`). Title states the problem; body has the failure scenario and fix in the same short form as a comment, and a line "Found while reviewing [PR #N](url)". No assignee or labels unless the user names them. Note their numbers.
2. Post the review: one request, so it is one notification.
3. Post each conversation reply where the question was asked: a PR-level question on `repos/<owner>/<repo>/issues/<N>/comments`; a question in an inline review thread as a reply in that thread (`POST repos/<owner>/<repo>/pulls/<N>/comments/<comment id>/replies`). Link the inline comment or issue from steps 1–2; the new inline comments' URLs come from `gh api repos/<owner>/<repo>/pulls/<N>/comments --jq '.[] | select(.pull_request_review_id == <review id>) | .html_url'` after step 2.

**Mechanics:**
- Build the payload with a script (triple-quoted strings and `json.dump`); hand-escaped JSON is where this goes wrong. Payload: `{commit_id, event, body, comments: [{path, line, side: "RIGHT", body}]}`.
- `commit_id` is the head you reviewed (for a merged PR, its last head commit).
- `line` is a line the diff adds at head. Check every anchor with `check_anchors.py` in this skill's directory before posting: `python3 check_anchors.py <repo> <base> <head> review.json` (it prints each anchored line and exits 1 if one is outside the diff). A finding about an unchanged line is anchored at the changed line that causes the problem, with the target `path:line` named in the comment's first line; if no changed line is related, it goes in the summary.
- `gh api repos/<owner>/<repo>/pulls/<N>/reviews --method POST --input review.json --jq '"\(.state) id=\(.id) \(.html_url)"'`, then check `gh api repos/<owner>/<repo>/pulls/<N>/comments --jq length`.
- PR-level comments live on the issues endpoint; `pulls/<N>/comments` returns only inline comments.
- A merged PR can still take a review: ask for follow-ups in a new PR instead of changes "in this PR". Removing something from history after a merge means a rewrite and a force push; say so instead of asking for it lightly.

Then record what was posted (the review URL, the issue numbers) where the user's or the repository's instructions say; if nothing says, in the findings file next to the brief.
