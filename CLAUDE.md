# Skills

Forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Upstream Sync

- **Upstream:** https://github.com/mattpocock/skills
- **Fork point:** `6eeb81b` (Added PR's as a triage surface)

### Skill mapping notes

Some local skills don't map 1:1 to their upstream namesake — sync accordingly.

- **`grill/`** — inlines upstream `productivity/grilling/` body inside `<what-to-do>`; entry maps to `engineering/grill-with-docs/`. Manually refresh when upstream `grilling` body changes.
- **`tdd/`** — reference-only architecture (upstream `e81f976` + `80e9dcc`); no Refactor stage (delegated to `/finalize`); `deep-modules.md` merged into `improve-codebase-architecture/DEEPENING.md`; `interface-design.md` + `refactoring.md` deleted. **TODO**: `interface-design.md`'s 3 testability rules (DI / return-vs-mutate / small-surface) — fold into `improve-codebase-architecture/`?
- **`issues/`** — file-first (`.matt/issues/NN-slug.md` + parser), not tracker-first. **Default-reject** upstream tracker-native mechanics changes (sub-issues / blocking edges / issue-URLs); re-evaluate if upstream abstracts tracker behind an `issue-tracker.md` doc.
