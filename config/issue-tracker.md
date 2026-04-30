# Issue tracker: Local Markdown

Issues and PRDs live as markdown files in `~/.claude/matt/features/`.

## Conventions

- One feature per directory: `~/.claude/matt/features/<slug>/`
- The PRD is `~/.claude/matt/features/<slug>/PRD.md`
- Implementation issues are `~/.claude/matt/features/<slug>/issues/<NN>-<slug>.md`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `~/.claude/matt/features/<slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.
