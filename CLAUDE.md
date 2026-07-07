# Skills

Forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Upstream Sync

- **Upstream:** https://github.com/mattpocock/skills
- **Fork point:** `6eeb81b` (Added PR's as a triage surface)

### Skill mapping notes

Some local skills don't map 1:1 to their upstream namesake — sync accordingly.

- **`grill/`** — entry-point maps to upstream `skills/engineering/grill-with-docs/` (a 1-line thin wrapper: `Run a /grilling session, using the /domain-modeling skill.`), but its `<what-to-do>` block **inlines the body of upstream `skills/productivity/grilling/`** instead of delegating. Watch `grilling/SKILL.md` for body updates and manually refresh our `<what-to-do>` block when it changes (last refresh: 2026-07-07, adopted upstream's confirmation gate + facts/decisions split from commits `0e9a072` + `e5932a7`).
- **`tdd/`** — adopted upstream's reference-only architecture on 2026-07-07 (commits `e81f976` + `80e9dcc`): SKILL.md rewritten as 36-line reference (What a good test is / Seams / Anti-patterns / Rules of the loop); the 4th Refactor stage dropped and delegated to our `/finalize` skill (which runs `/code-review` sub-agents); sub-files `refactoring.md`, `interface-design.md`, `deep-modules.md` deleted. Before deletion, `deep-modules.md`'s Ousterhout attribution + deep/shallow definitions + ASCII diagrams + interface-design questions were merged into `improve-codebase-architecture/DEEPENING.md` (which silently assumed them). **TODO**: consider whether `interface-design.md`'s three testability rules (DI, return-vs-mutate, small-surface) should be folded into `improve-codebase-architecture/` — currently just deleted since upstream classifies them as design-layer, not test-layer.
- **`issues/`** — hard architecture divergence from upstream `skills/engineering/to-issues/`: we publish issues as **files** under `.matt/issues/` with strict backtick-wrapped filename refs (`` `NN-slug.md` ``) enforced by `/run-all-issues`'s deterministic parser, whereas upstream publishes to GitHub/GitLab-style trackers with URL/API references. Consequence: **default-reject** any upstream `to-issues` change that touches tracker-native mechanics (sub-issues, blocking edges, issue-URL formats) — the `## Parent` / `## Blocked by` body sections are our primary path, not a fallback. **Exception**: if upstream abstracts the tracker behind a doc like `issue-tracker.md` (they're trending that way), re-evaluate then. Last evaluated: 2026-07-07 (commit `0172e61` — rejected the tracker-native change on architecture grounds; the `/prototype` reference change is a no-op since our fork has no `/prototype` skill).
