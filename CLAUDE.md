# Skills

Forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Upstream Sync

- **Upstream:** https://github.com/mattpocock/skills
- **Fork point:** `6eeb81b` (Added PR's as a triage surface)

### Skill mapping notes

Some local skills don't map 1:1 to their upstream namesake — sync accordingly.

- **`grill/`** — entry-point maps to upstream `skills/engineering/grill-with-docs/` (a 1-line thin wrapper: `Run a /grilling session, using the /domain-modeling skill.`), but its `<what-to-do>` block **inlines the body of upstream `skills/productivity/grilling/`** instead of delegating. Watch `grilling/SKILL.md` for body updates and manually refresh our `<what-to-do>` block when it changes (last refresh: 2026-07-07, adopted upstream's confirmation gate + facts/decisions split from commits `0e9a072` + `e5932a7`).
