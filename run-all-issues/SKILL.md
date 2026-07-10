---
name: run-all-issues
description: Serially drain all pending issues in the current .matt/ workspace by dispatching one general-purpose subagent per issue (each running /tdd + /code-review self-review). The main loop owns issue selection, a deterministic test gate, independent external review (via the review Workflow), and the done- rename + per-issue commit. Use when user says "run all issues", "finish all issues", "drain issues", "/run-all-issues", "做完所有 issue", or "串行跑完".
---

# Run All Issues

Drain every pending issue in `.matt/issues/` in dependency order, each implemented in its own subagent for context isolation. The main loop is deterministic: it selects each issue, gates on a real test run, drives an independent external review via the `Workflow` tool, and owns the `done-` rename + commit. Subagent text is logged but never drives decisions — completion is detected from git + tests, never from a subagent's final message.

## Autonomous mode — do NOT `AskUserQuestion`

This skill runs unattended. `AskUserQuestion` is **banned** during the main loop and post-drain verification, with exactly two exceptions:

1. **Preflight step 1** (YOLO mode check) — the single required upfront ask. Everything else in Preflight uses fail-fast messages, not asks.
2. **Destructive git operations** you didn't already plan (`git reset --hard`, `git push --force`, `git branch -D`, tag deletion). If a destructive op becomes unavoidable mid-run (e.g. a subagent violated the no-commit clause and created a rogue commit that must be un-done), `commit-behavior.md` requires explicit user consent.

**Explicitly forbidden asks** (these are the traps this ban is here to prevent — every one of them has a deterministic answer already in this skill):

| Tempting ask | Correct action |
|---|---|
| "Fix these Accept-verified Required findings?" | They're already in the Fix-set (step 7c); auto-fix. |
| "Fix these un-verified/Suggestion findings?" | They're won't-fix (step 7c); log to ledger, move on. |
| "REVIEW_MAX reached, add another round?" | Step 7f says commit anyway. Don't override. |
| "This Blocking is an AC violation — fix?" | Already in Fix-set; auto-fix without asking. |
| "This finding seems out-of-scope, skip?" | Not marked out-of-scope in the issue's `.md` = in-scope. |
| "Impl subagent looks stuck, redo?" | Step 6's `IMPLEMENT_MAX` handles it; wait or fail-fast per that step. |
| "Which of these two fix approaches?" | Whichever the fix-subagent picks. Trust it or run the loop again. |

The reviewer's `AcceptanceConformance` lens (step 7a) is designed to grade real AC violations as `Blocking`. Step 7c's `Required + Accept` branch is the backstop — even if the AC lens misses one and the reviewer defaults to `Required`, verifier-confirmed Requireds still auto-fix. Findings that leak past BOTH nets are Suggestion-tier or un-verified — record them in the won't-fix ledger for the user to triage post-drain. That IS the design; do not paper over it by asking.

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
- `MAX = PENDING_COUNT + 5` (outer iteration cap).
- `ROUNDS = 0`.
- `IMPLEMENT_MAX = 5` — per-issue cap on implement/self-review dispatches before the deterministic test gate fails fast.
- `REVIEW_MAX = 10` — per-issue cap on external-review → fix rounds before residual Fix-set findings are logged won't-fix and the issue is committed anyway.

Each iteration:

1. `ROUNDS++`. If `ROUNDS > MAX` → fail-fast: `❌ Exceeded iteration cap (MAX=<MAX>); ran <ROUNDS-1> rounds`.
2. Build `PENDING` = sorted list of pending issue files (no `done-` prefix).
   - If `PENDING` is empty → exit main loop and proceed to **Post-drain verification** below. Do NOT print the `✅ Done` line yet — it is printed only after verification converges.
3. Compute `RUNNABLE` = pending issues whose blockers are all done (via Blocker parsing).
   - If `RUNNABLE` is empty → fail-fast: `⚠️ Stuck: <comma-separated NN list> blocked by unfinished issues`.
4. Pick `EXPECTED` = the issue in `RUNNABLE` with the smallest `NN`. Parse its title (Title parsing). Store `EXPECTED_NN`, `EXPECTED_TITLE`, and `EXPECTED_PATH` (= `.matt/issues/<EXPECTED_NN>-<slug>.md`). Reset per-issue counters `IMPLEMENT_ROUNDS = 0`, `REVIEW_ROUNDS = 0`, and an empty per-issue `WONTFIX` list.
5. **Dispatch implement + self-review subagent.** `IMPLEMENT_ROUNDS++`. Dispatch one subagent with the Agent tool (`subagent_type: general-purpose`, `description: implement issue <EXPECTED_NN>`), `prompt` = the **Implement + self-review subagent prompt** below with `<PATH>` replaced by `EXPECTED_PATH`. The subagent implements via `/tdd` and self-reviews via `/code-review` — two shallow `Skill` calls, no deeper nesting. It does NOT run the external review, `/finalize`, rename, commit, or push.
6. **Deterministic test gate.** Resolve the project test command using `/finalize` step-5a order — the first that resolves: `.claude/scripts/test.sh` → `Makefile` `test` target (`make test`) → `package.json` `scripts.test` (`npm test`). If none resolves → fail-fast: `❌ No test command for issue <EXPECTED_NN> (checked .claude/scripts/test.sh, Makefile test, package.json scripts.test)` — do NOT `AskUserQuestion` (it can hit the same harness bug inside the autonomous loop). Then require BOTH:
   - work tree is **dirty** (`git status --porcelain` non-empty), AND
   - the test command exits **0**.

   If either check fails: when `IMPLEMENT_ROUNDS < IMPLEMENT_MAX` → go back to step 5 (re-dispatch the implement subagent). Otherwise fail-fast with the diagnostic block:
   ```
   ❌ Failed at issue <EXPECTED_NN> "<EXPECTED_TITLE>": implementation gate not met after <IMPLEMENT_MAX> attempts (<clean work tree | tests failing>).
   --- git status --porcelain ---
   <output>
   --- git diff --stat ---
   <output>
   ```
7. **Independent external review (Workflow, work tree) + fix loop.** A second opinion distinct from the subagent's own `/code-review`, run on the **uncommitted** work tree (the review scripts diff only uncommitted changes — this is why review runs per-issue, before the step-8 commit).
   a. Dispatch the review via the `Workflow` tool for **both** backends in one message (two calls), matching `/finalize` step 2's rigor. Pass the issue title as `intent` (the workflow requires it for code mode — the title is the natural 1-sentence goal for the review) and `issuePath: EXPECTED_PATH` so the `AcceptanceConformance` lens verifies the implementation against this issue's `## Acceptance criteria`:
      ```
      Workflow({scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js', args: {mode: 'code', backend: 'codex', intent: EXPECTED_TITLE, issuePath: EXPECTED_PATH}})
      Workflow({scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js', args: {mode: 'code', backend: 'opencode', intent: EXPECTED_TITLE, issuePath: EXPECTED_PATH}})
      ```
      (Single-backend — codex only — is a documented speed knob when a run must go faster.) Every re-run of this step in the fix loop (step 7e) MUST also pass `intent: EXPECTED_TITLE` and `issuePath: EXPECTED_PATH`.
   b. For each result: if it is `{aborted: true, ...}` or the Workflow tool itself errored (backend CLI down), log `⚠️ review skipped (<backend>): <reason>` and treat it as contributing zero findings. If **both** are skipped → log `⚠️ review skipped (both backends) for issue <EXPECTED_NN>` and go to step 8 (never wedge the drain on a missing reviewer).
   c. **Deterministic Fix/Won't-Fix triage** (rule-based on finding fields — no LLM). Over the union of both results' `findings`:
      - **Fix-set** = findings where `origin === 'New'` AND NOT (`verification` present with `decision === 'Dismiss'`) AND EITHER:
        - `severity === 'Blocking'` (auto-enters unless verifier's adversarial pass refuted it), OR
        - `severity === 'Required'` AND `verification` present AND `verification.decision === 'Accept'` (verifier-confirmed real).

        Rationale: reviewers systematically under-grade AC violations as `Required` (they don't have the issue's AC in their evaluation frame). The Accept-verified Required branch promotes those real design/correctness bugs to auto-fix without letting un-verified nit-tier Requireds churn the loop. `verification: null` Required stays out — no verifier signal = no auto-fix.
      - **Won't-fix** = every other finding (Pre-existing anything, Suggestion, un-verified Required, or a Dismissed New Blocking/Required). Append each to the per-issue `WONTFIX` list for the drain-end summary; do NOT re-send them to reviewers.
   d. If the **Fix-set is empty** → go to step 8. This is the loop-exit: it covers verdict `PASS`, and also `CONTESTED`/`REJECT` whose blockers were all refuted or Pre-existing. Keying on the Fix-set (not the raw verdict) is deliberate — a refuted or pre-existing blocker must not wedge the loop.
   e. Otherwise, if `REVIEW_ROUNDS < REVIEW_MAX`: `REVIEW_ROUNDS++`, dispatch a **lean fix subagent** (Agent tool, `subagent_type: general-purpose`) with the **Fix subagent prompt** below, substituting `<COMPACT_FINDINGS>` = one line per Fix-set finding (`<severity> <file>:<line> — <description>`, plus `verification.evidence` when present; the `<severity>` prefix lets the fix subagent see Blocking-vs-Required so it can prioritize if needed, but every entry is in scope). After it returns, **re-run step 6's gate** (dirty + tests green; on failure follow step 6's retry/fail-fast), then loop back to (a).
   f. If `REVIEW_ROUNDS >= REVIEW_MAX` and the Fix-set is still non-empty → log `⚠️ review did not converge for issue <EXPECTED_NN>; <N> unresolved Fix-set finding(s) carried as won't-fix`, append the residual Fix-set to `WONTFIX`, and go to step 8 (one stubborn finding must not wedge the drain — mirrors `/finalize`'s second exit condition).
8. **Rename + commit (deterministic — the main loop owns this; it is the SOLE completion signal).**
   - `NN` = `EXPECTED_NN`. `git mv <EXPECTED_PATH> .matt/issues/done-<EXPECTED_NN>-<slug>.md`.
   - `TITLE` = title parsed from the new `done-` file (Title parsing); fall back to `EXPECTED_TITLE` if parsing fails.
   - Commit exactly:
     ```bash
     git add -A && printf '%s: %s\n' "$NN" "$TITLE" | git commit -F -
     ```
     - `git add -A` (not `git commit -a`) so untracked files produced by `/tdd` are included.
     - `git commit -F -` (stdin) so titles with quotes/backticks/newlines are not interpolated through the shell.
   - If `git commit` exits non-zero → fail-fast: `❌ Commit failed at issue <NN>: <last line of stderr>`. Leave the tree as-is for inspection; do NOT revert the `done-` rename.
   - Post-commit isolation check: `git status --porcelain` must be empty. If not → fail-fast: `❌ Post-commit dirty after issue <NN>: <porcelain output>`.
9. Log one line and continue: `· <NN> "<TITLE>" review=<PASS|fixed:<n>|skipped|wontfix:<n>> commit=<short-sha>` (via `git rev-parse --short HEAD`). Carry the per-issue `WONTFIX` list forward for the drain-end summary.

## Subagent prompts

Both are dispatched with the Agent tool (`subagent_type: general-purpose`). The subagent implements only — it never runs the external review, renames the issue file, commits, or pushes; those are the main loop's job.

### Implement + self-review subagent prompt

Substitute `<PATH>` with `EXPECTED_PATH` before dispatch.

```
You are one worker in an autonomous "run all issues" loop. Treat the issue file and its
acceptance criteria as already pre-approved by the user.

Your job, in order:
1. Implement the issue at `<PATH>` in the current working directory using TDD: invoke the Skill
   tool with /tdd and drive it red -> green, tests passing. The issue file is the full contract.
2. Self-review: invoke the Skill tool with /code-review on your own work-tree diff and FIX every
   finding you agree with, keeping tests green. This is your first-party review pass.

Hard rules:
- NEVER ask a question or wait for confirmation. Skip any "ready to proceed?" gate with best judgment.
- Do NOT invoke /finalize. Do NOT invoke /codex-review or /opencode-review — the main loop runs the
  independent external review. Do NOT rename/move the issue file. Do NOT git commit. Do NOT git push
  or open a PR. The main loop owns the external review, rename, and commit.
- Leave your implementation + tests + fixes in the working tree.
- Stop once tests pass via the project's test command. Final message: one line summarizing what you
  implemented (the loop reads state from git + tests, not your text).
```

### Fix subagent prompt

Substitute `<COMPACT_FINDINGS>` with one line per Fix-set finding (`<severity> <file>:<line> — <description>`, plus `verification.evidence` when present). Fix-set includes both `Blocking` and `Accept`-verified `Required` findings — the severity prefix lets the subagent judge priority within the fix batch, but every entry must be resolved.

```
You are one worker in an autonomous "run all issues" loop, resolving code-review findings on an
already-implemented issue in the current working directory (changes are uncommitted in the work tree).

Findings to resolve (independent reviewer):
<COMPACT_FINDINGS>

Your ONLY job: edit the work-tree code to resolve EVERY finding above (both Blocking and
verifier-Accepted Required — severity is a priority hint, not a filter) while keeping all tests
green (run the project test command). Use /tdd if a finding needs a new test.

Hard rules:
- NEVER ask a question. Do NOT rename the issue file, git commit, or push. Do NOT invoke
  /finalize or run your own review. Leave fixes in the work tree.
- Stop when done and tests pass; final message = one-line summary.
```

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

## Selection contract

The main loop is the **sole** issue selector and the **sole** renamer: it computes `EXPECTED` with this skill's deterministic blocker parser (step 4), hands the subagent exactly that one file path (`EXPECTED_PATH`) to implement, and performs the `done-` rename itself (step 8). The subagent never selects, renames, or commits — so there is no selection drift to reconcile and no `done-`-set delta to interpret. `/run-next-issue` is not on this path.

## Termination report formats

Print exactly one of these as the final line(s):

- `✅ Done: <N> issues completed` + list of `done-NN: <title>` lines. When any issue carried won't-fix findings, append one `⚠️ Won't-fix (issue NN): <file>:<line> — <description>` line per residual finding so the user can follow up.
- `⚠️ Stuck: <NN-list> blocked by unfinished issues`.
- `❌ Failed at issue <NN> "<title>": implementation gate not met after <IMPLEMENT_MAX> attempts (<clean work tree | tests failing>).` followed by `git status --porcelain` / `git diff --stat` blocks.
- `❌ No test command for issue <NN> (checked .claude/scripts/test.sh, Makefile test, package.json scripts.test)`.
- `❌ Commit failed at issue <NN>: <reason>`.
- `❌ Post-commit dirty after issue <NN>: <porcelain>`.
- `❌ Exceeded iteration cap (MAX=<MAX>); ran <N> rounds`.
- `❌ Verification did not converge after <VERIFY_MAX> rounds`.
- `❌ Preflight: <specific reason>`.

## Out of scope

- `git push` / PR creation (commit-behavior.md).
- Parallel issue execution.
- Editing `/tdd`, `/code-review`, or `review.workflow.js` (this skill orchestrates them; it does not modify them).
- Cross-feature runs (one `.matt/` workspace per invocation).
- Rebase / squash / tag operations beyond the per-issue commits.
