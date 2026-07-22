---
name: auto-improve-codebase-architecture
description: Automatically select, implement, review, and verify one architecture-deepening refactor in a small personal repository.
disable-model-invocation: true
compatibility: Requires Git, Bash, jq for package.json projects, and the Workflow tool. Run only in a small repository maintained solely by the invoking user.
---

# Auto Improve Codebase Architecture

Fully automate one evidence-backed module-deepening refactor. Never ask the user a question while this skill runs.

This skill is intentionally for a **small personal repository with one maintainer**. Explicit invocation is the user's assertion that this assumption holds and that a failed run may reset the repository to its starting commit.

Read the sibling architecture references before starting:

- [LANGUAGE.md](../improve-codebase-architecture/LANGUAGE.md)
- [DEEPENING.md](../improve-codebase-architecture/DEEPENING.md)
- [HTML-REPORT.md](../improve-codebase-architecture/HTML-REPORT.md)

`CONTEXT.md`, `CONTEXT-MAP.md`, and ADRs are read-only constraints. Never modify them.

## Hard boundaries

- One run, one domain context, one seam, one candidate.
- No questions. Ambiguity means `NO-OP`.
- No commit, push, PR, dependency upgrade, or unrelated cleanup.
- Repository gate scripts are trusted personal code. This skill does not sandbox a deliberately deceptive test command or a child process that intentionally escapes its process group.
- Only the workflow's serialized writer role may edit source, tests, or necessary technical docs. The initial implementation and optional one-time fix never run concurrently.
- The final status is exactly one of:
  - `VERIFIED`
  - `NO-OP`
  - `FAILED_ROLLED_BACK`
  - `ROLLBACK_FAILED`
- This skill has its own review flow. Do **not** invoke `/finalize` afterward.

## Run

1. Resolve the repository root with `git rev-parse --show-toplevel`; use its absolute canonical path as `cwd`. If it cannot be resolved, return `NO-OP`.
2. Create a state directory outside the repository with `mktemp -d`.
3. Invoke the workflow:

```js
Workflow({
  scriptPath: '/home/fei/.claude/skills/auto-improve-codebase-architecture/auto-improve-codebase-architecture.workflow.js',
  args: {
    cwd: '<absolute canonical repository root>',
    stateDir: '<absolute mktemp directory>',
    guardPath: '/home/fei/.claude/skills/auto-improve-codebase-architecture/scripts/git-guard.sh',
    gateRunnerPath: '/home/fei/.claude/skills/auto-improve-codebase-architecture/scripts/gate-runner.sh',
    architectureSkillDir: '/home/fei/.claude/skills/improve-codebase-architecture'
  }
})
```

The workflow owns candidate discovery, baseline gates, frozen scope, implementation, one review/fix cycle, final verification, and rollback.

If the workflow call itself errors after rollback has been armed, run:

```bash
bash /home/fei/.claude/skills/auto-improve-codebase-architecture/scripts/git-guard.sh rollback <state-dir>
```

Report `FAILED_ROLLED_BACK` when that succeeds, otherwise `ROLLBACK_FAILED`.

## Report

First print the workflow's terminal status and concise reason. Then create the report path with `mktemp "${TMPDIR:-/tmp}/architecture-auto-improve.XXXXXX.html"`, set mode `0600`, and best-effort write a Chinese HTML report containing:

- selected candidate and consensus evidence;
- falsifier and adjudicator decisions;
- discovered gate manifest and baseline evidence;
- frozen paths and preserved behaviors;
- final diff summary;
- review findings and the optional single fix;
- final verification or rollback evidence;
- the exact terminal status.

Use the visual language from [HTML-REPORT.md](../improve-codebase-architecture/HTML-REPORT.md), but keep the report compact. HTML-escape every repository-derived value before interpolation and configure Mermaid with `securityLevel: 'strict'`. If report creation or opening fails, print `report unavailable`; never change the workflow status because of report I/O.
