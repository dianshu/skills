# Skills

Forked from [mattpocock/skills](https://github.com/mattpocock/skills). **Fork point:** `16a2a5c` (upstream main, 2026-07-06).

## Skill mapping notes

Local skills that don't map 1:1 to their upstream namesake — sync accordingly.

- **`grill/`** — inlines upstream `productivity/grilling/` body inside `<what-to-do>`; entry maps to `engineering/grill-with-docs/`. Refresh when upstream `grilling` body changes.
- **`tdd/`** — reference-only; converged with upstream `engineering/tdd/` (only diff: our Refactoring line points at `/finalize`). `tests.md` + `mocking.md` siblings. **TODO:** upstream's *old* `interface-design.md` 3 testability rules (DI / return-vs-mutate / small-surface) still not folded in anywhere — `INTERFACE-DESIGN.md` is a different doc (Design-It-Twice), not those rules.
- **`improve-codebase-architecture/`** — we inline the glossary + keep `LANGUAGE.md` / `DEEPENING.md` / `INTERFACE-DESIGN.md` siblings; upstream instead extracts these into `/codebase-design` + `/domain-modeling` skills. Same content, org differs — **not a gap**. Local-only: report language forced to Chinese.
- **`spec/` + `tickets/`** (renamed from `prd/` + `issues/`, dropping upstream's `to-` prefix) — rename spans derivatives (`*-review-loop`, `run-all/next-*`), runtime paths (`.matt/{issues→tickets}/`, `PRD→SPEC.md`, `issue→ticket-tracker.md`), and the review-with-agent mode/arg contract (`prd`/`issues`→`spec`/`tickets`, `--issue→--ticket`, `issuePath→ticketPath`, `issueFile→ticketFile`). Problem-sense `issue` preserved in code-review lenses.
- **`tickets/`** — file-first (`.matt/tickets/NN-slug.md` + parser), not tracker-first. **Default-reject** upstream tracker-native mechanics (sub-issues / blocking edges / issue-URLs); re-evaluate if upstream abstracts tracker behind a `ticket-tracker.md` doc.
