---
name: release-features
description: Use when the user asks for the latest Claude Code or pi release features, new capabilities, or release-note highlights while excluding bug fixes.
---

# Release Features

Report the **new user-facing capabilities** in the latest stable releases of Claude Code and pi. The authoritative source is each project's GitHub release body; never rely on a cached changelog, search snippet, or a third-party summary.

## Scope

- **Claude Code:** `anthropics/claude-code`
- **pi:** `earendil-works/pi`
- Default scope: the latest published, non-prerelease release of each project.
- If the user gives a version, date range, or release count, retrieve that requested range instead. State the range used.

## Procedure

1. Fetch both release records in parallel with GitHub CLI:

   ```bash
   gh api repos/anthropics/claude-code/releases/latest
   gh api repos/earendil-works/pi/releases/latest
   ```

   Each returned record must provide `tag_name`, `published_at`, `html_url`, and `body`.

2. For a user-specified range, list releases first, excluding drafts and prereleases, then select the requested records:

   ```bash
   gh api 'repos/anthropics/claude-code/releases?per_page=100'
   gh api 'repos/earendil-works/pi/releases?per_page=100'
   ```

3. Extract only feature entries from every selected release body.

   Include entries that explicitly introduce a capability, such as sections headed **Added**, **New Features**, or **What's New**, and bullets that say a user can now do something (for example: `Added`, `Introduced`, `now supports`, `can now`). Preserve meaningful sub-bullets that explain the new capability.

   Exclude bug fixes, regressions, crashes, security fixes, performance/reliability-only changes, documentation-only updates, dependency updates, refactors, and release-process changes. Do not turn a fix into a feature merely because it improves an existing workflow.

   If a mixed bullet contains both a new capability and a fix, report only the capability and label it as an excerpt when needed to avoid implying the fix is included.

4. If a release has no qualifying entries, report **“No new features listed; this release contains only fixes or maintenance changes.”** Do not pad the report with non-feature changes.

## Output

Write in the user's language. Use this compact format:

```markdown
## Claude Code — <tag> (<YYYY-MM-DD>)
- <new feature>
- <new feature>
Source: <release URL>

## pi — <tag> (<YYYY-MM-DD>)
- <new feature>
- <new feature>
Source: <release URL>
```

- Keep each bullet to one concise, user-oriented sentence.
- Link every section to the exact release used.
- If either source cannot be fetched, show the other result and explicitly name the failed repository and error; never substitute old release notes.
