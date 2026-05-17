---
name: load-feature
description: Copy a feature (PRD + issues) from the global ~/.claude/matt/features/<slug>/ into the current directory's .matt/ workspace and generate .matt/CLAUDE.md with sync rules. Use when user says "load feature", "/load-feature <slug>", "checkout feature", or wants to start working on a feature locally.
---

# Load Feature

Bring a feature from the global backup into the current directory's `.matt/` workspace.

## Inputs

- `<slug>`: the feature directory name under `~/.claude/matt/features/`. If the user didn't pass one, list available slugs (`ls ~/.claude/matt/features/`) and ask which to load.

## Preconditions

- `~/.claude/matt/features/<slug>/` must exist.

## Process

### 1. Check local `.matt/` state

- If `.matt/` does not exist: proceed.
- If `.matt/` exists:
  - Read `.matt/CLAUDE.md` to identify the current feature slug.
  - Same slug → ask "reload and overwrite?"; stop unless confirmed.
  - Different slug → ask "current `.matt/` is `<other>`. Discard and load `<slug>`?"; stop unless confirmed. (Assume user has already synced pending changes per the sync rule. Do not detect or merge.)

### 2. Copy files

- Remove existing `.matt/` if present.
- Create `.matt/issues/`.
- If `~/.claude/matt/features/<slug>/PRD.md` exists, copy to `.matt/PRD.md`.
- Copy every `~/.claude/matt/features/<slug>/issues/*.md` to `.matt/issues/`, preserving filenames (including any `done-` prefix).

### 3. Generate `.matt/CLAUDE.md`

Write this exact content, substituting `<slug>`:

```markdown
# Feature: <slug>

This `.matt/` directory is the **authoritative** working copy of the current feature.
Backup path: `~/.claude/matt/features/<slug>/`

## Status convention

Issue completion status is encoded in the filename:
- Pending: `NN-<slug>.md`
- Done:    `done-NN-<slug>.md`

The filename is the single source of truth. There is no `Status:` field to maintain.

## Sync rules (local → backup, one-way)

When any of these files change, immediately mirror the change to the backup:
- `.matt/PRD.md`
- `.matt/issues/*.md`

Mirror semantics:
- Edit   → `cp` the file to the backup.
- Create → `cp` the new file to the backup.
- Rename (e.g. `03-foo.md` → `done-03-foo.md`) → `mv` the old name in the backup, then `cp` the new name (or `rm` old + `cp` new).
- Delete → `rm` from the backup.

Other files (including this `CLAUDE.md`, scratch notes, drafts) are NOT synced.
Never sync in reverse (backup → local).
```

### 4. Update `.gitignore`

- Run `git rev-parse --show-toplevel` to find the repo root.
- If inside a git repo:
  - Open `<repo-root>/.gitignore` (create if missing).
  - If it does not already contain a line matching `.matt/` or `.matt`, append `.matt/`.
- If not inside a git repo: skip; note in the report.

### 5. Report

Print:
- Feature loaded: `<slug>`
- Files copied: PRD (yes/no), N issues total (M done, P pending)
- `.gitignore`: updated / already present / skipped (not a git repo)
- Suggest next step: `/run-next-issue`

## Notes

- This skill is the only thing that writes `.matt/CLAUDE.md`. `/run-next-issue` and `/tdd` assume it's already there.
- This skill never modifies the global backup.
