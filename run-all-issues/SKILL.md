---
name: run-all-issues
description: Serially drain all pending issues in the current .matt/ workspace by dispatching one general-purpose subagent per issue (each running /run-next-issue → /tdd → /finalize). Main loop handles preflight, feature-branch setup, per-issue commits, and fail-fast termination. Use when user says "run all issues", "finish all issues", "drain issues", "/run-all-issues", "做完所有 issue", or "串行跑完".
---

# Run All Issues

Drain every pending issue in `.matt/issues/` in dependency order, each in its own subagent for context isolation. Main loop is deterministic; subagent text is logged but never drives decisions.

## Preconditions (user must arrange before calling)

- `.matt/` workspace is already loaded (`/load-feature <slug>` was run).
- `.gitignore` change adding `.matt/` (if any) is already committed on `origin/main` or an ancestor of the current branch — otherwise the `.matt/`-must-be-ignored preflight will fail.
- Working tree is clean.
- Current branch is `main` or `feiyue/<slug>`.

## Preflight (any failure → stop immediately, print `❌ Preflight: <reason>`)

Run these in order:

1. `git rev-parse --is-inside-work-tree` returns `true`.
2. `.matt/CLAUDE.md` exists and first line matches `^# Feature: (.+)$` — capture `SLUG`. `.matt/issues/` has at least one `.md` file. Every filename in `.matt/issues/` matches `^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$`. After stripping the optional `done-` prefix, the `NN-<slug>` portion must be unique — both `03-foo.md` and `done-03-foo.md` present is a conflict.
3. `git check-ignore -q .matt` exits 0. (Run BEFORE the dirty check so that untracked content inside `.matt/` does not surface as a false dirty signal.)
4. `git status --porcelain` is empty.
5. `git fetch origin main:refs/remotes/origin/main` exits 0. (Explicit refspec forces update of the remote-tracking ref — plain `git fetch origin main` does not.)
6. Current branch (`git rev-parse --abbrev-ref HEAD`) is `main` or `feiyue/<SLUG>`.

## Branch setup

- Already on `feiyue/<SLUG>` → reuse, do nothing.
- On `main`:
  - If local branch `feiyue/<SLUG>` already exists (`git rev-parse --verify --quiet refs/heads/feiyue/<SLUG>`) → fail-fast: `❌ Preflight: feiyue/<SLUG> already exists; checkout it manually and re-run`.
  - Otherwise: `git checkout -b feiyue/<SLUG> origin/main`.
- Other branch → already rejected in preflight step 6.

After branch setup, re-run `git check-ignore -q .matt`. If it fails (the new branch's ref base may not contain the `.matt/` ignore), fail-fast: `❌ Preflight: .matt/ not ignored on feiyue/<SLUG>`.

## Blocker parsing (deterministic)

For an issue file:

1. Locate the line matching `^##[ \t]+Blocked by[ \t]*$` (case sensitive). If absent → no blockers.
2. Take all lines from there to the next `^##[ \t]` heading or EOF as the section body.
3. Extract every `\b[0-9]{2,}\b` sequence from the body as blocker numbers.
4. If the body contains no digits but matches `(?i)none` → no blockers.
5. A blocker number `NN` is "done" iff `.matt/issues/done-NN-*.md` exists.
6. If any blocker number references an issue that does not exist (no `NN-*.md` or `done-NN-*.md` in the directory) → fail-fast: `❌ Issue <ISSUE_NN> references nonexistent blocker <NN>`.

## Title parsing

For an issue file, take the first line matching `^#[ \t]+(.+?)[ \t]*$` — the captured group is the title. If no such line → fall back to the filename with `done-` prefix and `.md` suffix removed.

## Main loop

Before the loop:

- `PENDING_COUNT` = number of files in `.matt/issues/` whose name does NOT start with `done-`.
- `MAX = PENDING_COUNT + 5`.
- `ROUNDS = 0`.

Each iteration:

1. `ROUNDS++`. If `ROUNDS > MAX` → fail-fast: `❌ Exceeded iteration cap (MAX=<MAX>); ran <ROUNDS-1> rounds`.
2. Snapshot `BEFORE` = sorted list of `done-*.md` filenames in `.matt/issues/`.
3. Build `PENDING` = sorted list of pending issue files (no `done-` prefix).
   - If `PENDING` is empty → normal exit: `✅ Done: <N> issues completed` followed by the numbered list of done- files.
4. Compute `RUNNABLE` = pending issues whose blockers are all done (via Blocker parsing).
   - If `RUNNABLE` is empty → fail-fast: `⚠️ Stuck: <comma-separated NN list> blocked by unfinished issues`.
5. Pick `EXPECTED` = the issue in `RUNNABLE` with the smallest `NN`. Parse its title (Title parsing). Store `EXPECTED_NN`, `EXPECTED_TITLE`.
6. Dispatch one subagent with the Agent tool:
   - `subagent_type: general-purpose`
   - `description: run next issue`
   - `prompt`: exactly the block below.

   ```
   You are running inside an autonomous "run all issues" loop. Treat the issue file(s) under .matt/issues/ and their acceptance criteria as already pre-approved by the user.

   In the current working directory (do NOT cd into .matt/), invoke the Skill tool with /run-next-issue. It will pick the next executable issue and drive /tdd → /finalize to completion.

   Hard rules for this subagent:
   - NEVER ask the user a question. NEVER wait for confirmation.
   - Skip /tdd's planning-confirmation prompt and any "ready to proceed?" gates by proceeding with your best judgment.
   - Do NOT run git push, /push, or anything that creates a PR.
   - The expected next issue number is <EXPECTED_NN> ("<EXPECTED_TITLE>"). If /run-next-issue selects a different one, still let it complete — the main loop will reconcile.
   - When fully done, output exactly ONE line in this format and nothing else:
     RESULT issue=<NN> title="<TITLE>" finalize=<pass|fail>
   ```

7. After the subagent returns, snapshot `AFTER` = sorted list of `done-*.md` filenames.
8. Integrity checks (before commit):
   - `BEFORE - AFTER` must be empty. If not → fail-fast: `❌ Done file removed: <list>`.
   - Re-run the filename-shape + no-duplicate-NN invariant from preflight step 2. Any violation → fail-fast: `❌ Invariant broken: <details>`.
9. Compute `DELTA = AFTER - BEFORE`.
   - If `|DELTA| == 0` → fail-fast: `❌ Failed at issue <EXPECTED_NN> "<EXPECTED_TITLE>" (no done file produced; /tdd or /finalize failed; working tree may be dirty — run \`git status\` to inspect)`.
   - If `|DELTA| >= 2` or the single delta's `NN` ≠ `EXPECTED_NN` → fail-fast: `❌ Unexpected done-set change: expected <EXPECTED_NN>, got <actual list>`.
10. Commit:
    - `NN` = `EXPECTED_NN`; `TITLE` = title parsed from the new `done-NN-*.md` file (Title parsing). If parsing somehow fails on the renamed file, fall back to `EXPECTED_TITLE` captured before dispatch.
    - Run exactly:
      ```bash
      git add -A && printf '%s: %s\n' "$NN" "$TITLE" | git commit -F -
      ```
      - `git add -A` (not `git commit -a`) so untracked files produced by /tdd or /finalize are included.
      - `git commit -F -` (stdin) so titles with quotes/backticks/newlines are not interpolated through the shell.
    - If `git commit` exits non-zero → fail-fast: `❌ Commit failed at issue <NN>: <last line of stderr>`. Leave the working tree as-is for inspection; do NOT revert the `done-` rename.
11. Post-commit isolation check: `git status --porcelain` must be empty. If not → fail-fast: `❌ Post-commit dirty after issue <NN>: <porcelain output>`.
12. Log one line and continue: `· <NN> "<TITLE>" finalize=<pass> commit=<short-sha>` (using `git rev-parse --short HEAD`).

## Selection contract (drift policy)

The main loop computes `EXPECTED` with this skill's deterministic blocker parser. `/run-next-issue` has its own (looser) parsing and is out of scope to change here. If the two disagree and the resulting `DELTA` does not match `EXPECTED`, the loop fails fast at step 9 — drift is treated as a real signal, not a false positive. Do not try to reconcile by editing `/run-next-issue` or by skipping the subagent and renaming files directly.

## Termination report formats

Print exactly one of these as the final line(s):

- `✅ Done: <N> issues completed` + list of `done-NN: <title>` lines.
- `⚠️ Stuck: <NN-list> blocked by unfinished issues`.
- `❌ Failed at issue <NN> "<title>" (...)`.
- `❌ Unexpected done-set change: expected <NN>, got <list>`.
- `❌ Done file removed: <list>`.
- `❌ Invariant broken: <details>`.
- `❌ Commit failed at issue <NN>: <reason>`.
- `❌ Post-commit dirty after issue <NN>: <porcelain>`.
- `❌ Exceeded iteration cap (MAX=<MAX>); ran <N> rounds`.
- `❌ Preflight: <specific reason>`.

## Out of scope

- `git push` / PR creation (commit-behavior.md).
- Parallel issue execution.
- Editing `/run-next-issue`, `/tdd`, or `/finalize`.
- Cross-feature runs (one `.matt/` workspace per invocation).
- Rebase / squash / tag operations beyond the per-issue commits.
