# Skills

Forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Upstream Sync

- **Upstream:** https://github.com/mattpocock/skills
- **Fork point:** `16a2a5c` (upstream main as of 2026-07-06)

### Skill mapping notes

Some local skills don't map 1:1 to their upstream namesake — sync accordingly.

- **`grill/`** — inlines upstream `productivity/grilling/` body inside `<what-to-do>`; entry maps to `engineering/grill-with-docs/`. Manually refresh when upstream `grilling` body changes.
- **`tdd/`** — reference-only architecture (upstream `e81f976` + `80e9dcc`); no Refactor stage (delegated to `/finalize`); `deep-modules.md` merged into `improve-codebase-architecture/DEEPENING.md`; `interface-design.md` + `refactoring.md` deleted. **TODO**: `interface-design.md`'s 3 testability rules (DI / return-vs-mutate / small-surface) — fold into `improve-codebase-architecture/`?
- **`spec/` + `tickets/` (renamed from `prd/` + `issues/`)** — aligned to upstream's
  `to-spec` / `to-tickets` naming but **without the `to-` prefix**. Full rename map in
  `RENAME-MAP.md`; the rename also covered `prd-review-loop→spec-review-loop`,
  `issues-review-loop→tickets-review-loop`, `run-all-issues→run-all-tickets`,
  `run-next-issue→run-next-ticket`, runtime paths (`.matt/issues/→.matt/tickets/`,
  `.matt/PRD.md→.matt/SPEC.md`, `issue-tracker.md→ticket-tracker.md`), and the
  review-with-agent mode/arg contract (`prd`/`issues` modes → `spec`/`tickets`,
  `--issue→--ticket`, `issuePath→ticketPath`, `issueFile→ticketFile`). Preserved
  problem-sense `issue` in code-review lenses (e.g. "security issue", "in-diff issues").
- **`tickets/`** — file-first (`.matt/tickets/NN-slug.md` + parser), not tracker-first. **Default-reject** upstream tracker-native mechanics changes (sub-issues / blocking edges / issue-URLs); re-evaluate if upstream abstracts tracker behind a `ticket-tracker.md` doc.
