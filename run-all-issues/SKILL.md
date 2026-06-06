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

1. **YOLO mode check.** Subagents must run unattended; only safe in `bypassPermissions` mode. Claude Code does not expose `permission_mode` to skills (hooks-only) — must ask. `/permissions` cannot switch INTO yolo mid-session; only `--dangerously-skip-permissions` at launch works. `AskUserQuestion` with: `1. 已在 yolo` (continue) / `2. 继续（不在 yolo）` (continue, may stall) / `3. 中止` (fail: `❌ Preflight: not in yolo mode, user aborted` — suggest relaunch with `claude --dangerously-skip-permissions`).
2. `git rev-parse --is-inside-work-tree` returns `true`.
3. `.matt/CLAUDE.md` exists and first line matches `^# Feature: (.+)$` — capture `SLUG`. `.matt/issues/` has at least one `.md` file. Every filename in `.matt/issues/` matches `^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$`. After stripping the optional `done-` prefix, the `NN-<slug>` portion must be unique — both `03-foo.md` and `done-03-foo.md` present is a conflict.
4. `git check-ignore -q .matt` exits 0. (Run BEFORE the dirty check so that untracked content inside `.matt/` does not surface as a false dirty signal.)
5. `git status --porcelain` is empty.
6. `git fetch origin main:refs/remotes/origin/main` exits 0. (Explicit refspec forces update of the remote-tracking ref — plain `git fetch origin main` does not.)
7. Current branch (`git rev-parse --abbrev-ref HEAD`) is `main` or `feiyue/<SLUG>`.
8. **Dry-parse every pending issue's `## Blocked by`.** For each `.matt/issues/<file>.md` whose name does NOT start with `done-`, run the full **Blocker parsing (deterministic)** algorithm below (parse + existence check). On the first failure, fail-fast with `❌ Preflight: <filename>: <Blocker parsing message, leading ❌ stripped>` — e.g. `❌ Preflight: 10-cleanup.md: Issue 10 has unparseable Blocked by line: - **Phase 4 production rollout signal** ...`. This catches malformed sections and bad references before branch setup or any subagent dispatch — never mid-drain.

## Branch setup

- Already on `feiyue/<SLUG>` → reuse, do nothing.
- On `main`:
  - If local branch `feiyue/<SLUG>` already exists (`git rev-parse --verify --quiet refs/heads/feiyue/<SLUG>`) → fail-fast: `❌ Preflight: feiyue/<SLUG> already exists; checkout it manually and re-run`.
  - Otherwise: `git checkout -b feiyue/<SLUG> origin/main`.
- Other branch → already rejected in preflight step 7.

After branch setup, re-run `git check-ignore -q .matt`. If it fails (the new branch's ref base may not contain the `.matt/` ignore), fail-fast: `❌ Preflight: .matt/ not ignored on feiyue/<SLUG>`.

## Blocker parsing (deterministic)

Strict bullet-by-bullet form. Every non-blank line in the section must either be a `none` shortcut or a bullet whose **first token after the bullet marker** is an issue reference in one of the two accepted shapes below. Anything else fails fast — silently dropping a line means a non-code blocker (release-window signal, manual sign-off, "1 week telemetry gate") could pass unnoticed and the loop would dispatch an issue whose human gate is unmet.

For an issue file:

1. Locate the line matching `^##[ \t]+Blocked by[ \t]*$` (case sensitive). If absent → no blockers.
2. Take all lines AFTER that heading up to (not including) the next `^##[ \t]` heading or EOF as the section **body**.
3. If the body has no non-blank lines → no blockers.
4. If the body's only non-blank content matches `^[ \t]*[Nn]one\b.*$` on a single line (with anything after `none`, e.g. `None - can start immediately.`) → no blockers. This shortcut is rejected if any other non-blank line is present (no mixing `None` with bullets).
5. Otherwise, iterate the body's non-blank lines in order. Every non-blank line MUST match exactly one of:
   - **Backtick form**: `^[ \t]*[-*+][ \t]+\x60(done-)?([0-9]{2,})-[a-z0-9-]+\.md\x60.*$` — the backtick-wrapped filename is the entire first token; the closing backtick is required, but any trailing characters after it (spaces, full-width punctuation, prose) are permitted and ignored.
   - **Hash form**: `^[ \t]*[-*+][ \t]+#([0-9]{2,})\b.*$` — the `#NN` is the entire first token; `\b` enforces a non-word-char boundary so `#10x` is rejected. Trailing characters after the boundary are permitted and ignored.

   The captured 2+ digit run is the blocker number `NN`. Bullet marker may be `-`, `*`, or `+`. Leading whitespace (spaces or tabs) is allowed.
6. Any non-blank line that does NOT match one of the two shapes — non-code prose (`- **Phase 4 production rollout signal** ...`), bare filename without backticks (`- 09-foo.md`), single-digit `NN` (`- \x609-foo.md\x60`), embedded reference where backtick is not the first token (`- see \x6003-foo.md\x60 for context`), unicode bullet markers (`•`, `・`, `–`), HTML comments, code fences, stray prose — → fail-fast: `❌ Issue <ISSUE_NN> has unparseable Blocked by line: <verbatim line>` (preserve the offending line exactly, including leading whitespace). This forces the human to move non-code gates OUT of `## Blocked by` — into a separate `## Hold` section, into the issue body, or out of `.matt/issues/` entirely.
7. The **blocker number list** is the de-duplicated set of `NN` values extracted in step 5, ordered by first occurrence.
8. A blocker number `NN` is "done" iff `.matt/issues/done-NN-*.md` exists.
9. If any blocker number references an issue that does not exist (no `NN-*.md` or `done-NN-*.md` in the directory) → fail-fast: `❌ Issue <ISSUE_NN> references nonexistent blocker <NN>`.

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
   - If `PENDING` is empty → exit main loop and proceed to **Post-drain verification** below. Do NOT print the `✅ Done` line yet — it is printed only after verification converges.
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
   - Re-run the filename-shape + no-duplicate-NN invariant from preflight step 3. Any violation → fail-fast: `❌ Invariant broken: <details>`.
9. Compute `DELTA = AFTER - BEFORE`.
   - If `|DELTA| == 0`:
     - If this iteration's dispatch was the **first attempt** for `EXPECTED_NN`: log one line `↻ retry issue <EXPECTED_NN> "<EXPECTED_TITLE>" (no done file produced on first attempt)`, then **re-dispatch the same subagent prompt once** (go back to step 6 for this same issue). Do NOT increment `ROUNDS` for the retry — the retry counts as part of the same iteration.
     - If this iteration's dispatch was the **retry attempt** and DELTA is still 0 → fail-fast with the full diagnostic block below. Run these three commands and embed their output verbatim:
       ```bash
       git status --porcelain
       git diff --stat
       git diff --stat --cached
       ```
       Format:
       ```
       ❌ Failed at issue <EXPECTED_NN> "<EXPECTED_TITLE>" after retry (no done file produced).
       --- git status --porcelain ---
       <output>
       --- git diff --stat ---
       <output>
       --- git diff --stat --cached ---
       <output>
       ```
   - If `|DELTA| >= 2` or the single delta's `NN` ≠ `EXPECTED_NN` → fail-fast: `❌ Unexpected done-set change: expected <EXPECTED_NN>, got <actual list>` (no retry — this is a state corruption signal, not a flake).
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

## Post-drain verification loop

After all issues are drained (PENDING empty), run a fix-verify loop. Cap iterations at `VERIFY_MAX = 5` (`VERIFY_ROUNDS = 0`).

Each iteration:

1. `VERIFY_ROUNDS++`. If `VERIFY_ROUNDS > VERIFY_MAX` → fail-fast: `❌ Verification did not converge after <VERIFY_MAX> rounds`.
2. **Run full UT suite.** Detect the project's test command from `.matt/CLAUDE.md`, `package.json`, `Makefile`, `pyproject.toml`, etc. If you cannot determine it deterministically, ask the user once via `AskUserQuestion` and remember the answer for subsequent rounds.
3. **Run `/e2e-verify`** via the Skill tool in the main agent.
4. Collect failures from both steps. If both clean → break out of the loop with success.
5. **Fix.** For each distinct failure:
   - Prefer dispatching a `general-purpose` subagent per independent failure (parallel where they touch disjoint files) with a prompt that:
     - States the failing test / scenario and the observed output.
     - Instructs the subagent to invoke `/tdd` to drive the fix.
     - Forbids creating any new issue file under `.matt/issues/`.
     - Forbids `git push` / `/push` / PR creation.
     - Forbids asking the user questions; proceed with best judgment.
     - Requires output of exactly one line: `RESULT fix="<short description>" status=<pass|fail>`.
   - If failures are tightly coupled or trivially small, fix directly in the main agent using `/tdd` instead.
6. After fixes, `git status --porcelain` may be non-empty. Commit with:
   ```bash
   git add -A && printf 'verify round %s: fix %s\n' "$VERIFY_ROUNDS" "<short summary>" | git commit -F -
   ```
   Skip the commit if the working tree is clean (a subagent already committed).
7. Loop back to step 2.

On successful convergence (step 4 clean), print the original termination line: `✅ Done: <N> issues completed` + the `done-NN: <title>` list, followed by `✅ Verification: UT + e2e-verify clean after <VERIFY_ROUNDS> round(s)`.

Hard constraint for this loop: **never create new issue files**. The drain phase is over; fixes are surgical.

## Selection contract (drift policy)

The main loop computes `EXPECTED` with this skill's deterministic blocker parser. `/run-next-issue` references the same `## Blocker parsing (deterministic)` rules, so both sides should agree on every well-formed file (preflight step 8 guarantees every pending file IS well-formed). If they still disagree and the resulting `DELTA` does not match `EXPECTED`, the loop fails fast at step 9 — drift is treated as a real signal, not a false positive. Do not try to reconcile by editing `/run-next-issue` or by skipping the subagent and renaming files directly.

## Termination report formats

Print exactly one of these as the final line(s):

- `✅ Done: <N> issues completed` + list of `done-NN: <title>` lines.
- `⚠️ Stuck: <NN-list> blocked by unfinished issues`.
- `❌ Failed at issue <NN> "<title>" after retry (no done file produced).` followed by `git status --porcelain` / `git diff --stat` / `git diff --stat --cached` blocks.
- `❌ Unexpected done-set change: expected <NN>, got <list>`.
- `❌ Done file removed: <list>`.
- `❌ Invariant broken: <details>`.
- `❌ Commit failed at issue <NN>: <reason>`.
- `❌ Post-commit dirty after issue <NN>: <porcelain>`.
- `❌ Exceeded iteration cap (MAX=<MAX>); ran <N> rounds`.
- `❌ Verification did not converge after <VERIFY_MAX> rounds`.
- `❌ Preflight: <specific reason>`.

## Out of scope

- `git push` / PR creation (commit-behavior.md).
- Parallel issue execution.
- Editing `/run-next-issue`, `/tdd`, or `/finalize`.
- Cross-feature runs (one `.matt/` workspace per invocation).
- Rebase / squash / tag operations beyond the per-issue commits.
