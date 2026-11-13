#!/usr/bin/env python3
"""Check a GitHub review payload's inline anchors before posting.

Usage: python3 check_anchors.py <repo> <base> <head> <review.json>

Every comment's `line` must be a line the diff `<base>...<head>` adds to
`path` (an added line is always inside a hunk, so GitHub accepts it). Prints
each anchor with the text of that line at <head>, so you can see that the
comment sits where you meant. Exits 1 if any anchor is outside the diff or the
payload lacks commit_id, event or body.
"""
import json
import subprocess
import sys


def added_lines(repo: str, base: str, head: str, path: str) -> set[int]:
    diff = subprocess.run(
        ["git", "-C", repo, "diff", "-U0", f"{base}...{head}", "--", path],
        capture_output=True, text=True, check=True,
    ).stdout
    lines: set[int] = set()
    for row in diff.splitlines():
        if row.startswith("@@"):
            new = row.split("+", 1)[1].split(" ", 1)[0]
            start, _, count = new.partition(",")
            first = int(start)
            lines.update(range(first, first + (int(count) if count else 1)))
    return lines


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    repo, base, head, payload_path = sys.argv[1:]
    with open(payload_path, encoding="utf-8") as fh:
        payload = json.load(fh)
    ok = True
    for key in ("commit_id", "event", "body"):
        if not payload.get(key):
            print(f"MISSING {key}")
            ok = False
    if payload.get("commit_id") and not head.startswith(payload["commit_id"][:7]) and not payload["commit_id"].startswith(head[:7]):
        print(f"commit_id {payload['commit_id']} is not the reviewed head {head}")
        ok = False
    for comment in payload.get("comments", []):
        path, line = comment.get("path"), comment.get("line")
        if comment.get("side", "RIGHT") != "RIGHT":
            print(f"NOT RIGHT SIDE: {path}:{line}")
            ok = False
        if line not in added_lines(repo, base, head, path):
            print(f"OUTSIDE DIFF: {path}:{line}")
            ok = False
            continue
        text = subprocess.run(
            ["git", "-C", repo, "show", f"{head}:{path}"],
            capture_output=True, text=True, check=True,
        ).stdout.splitlines()[line - 1]
        print(f"ok {path}:{line}: {text.strip()[:100]}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
