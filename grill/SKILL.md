---
name: grill
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan against their project's language and documented decisions.
---

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Probe the weakest assumption

Periodically ask: "What's the weakest assumption in this plan?" Force the user to name it themselves rather than you pointing it out. If they can't name one, that *is* the weakest assumption — they haven't stress-tested the plan yet.

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

Don't couple `CONTEXT.md` to implementation details. Only include terms that are meaningful to domain experts.

### Track session commitments

Maintain `$PWD/GRILLCOMMITMENTS.md` to detect when later answers silently overturn earlier ones.

#### File lifecycle

- **At start**:
  - If file does not exist → create with header (`# Grill Session Commitments`, `Started: <ISO>`, `Topic: <one line>`, empty `## Commitments`, `## Modifications`, `## Backtrack Check Log` sections)
  - If file exists → ask user (Chinese, terse): `发现已有 GRILLCOMMITMENTS.md（<date>，N 条承诺）。覆盖？(y/n)`. `n` → abort the skill.
- **At end** (user signals grilling is done): ask `Grilling 结束。删除 GRILLCOMMITMENTS.md？(y/n)`. **Never auto-delete.** A leftover file only triggers the start-time overwrite prompt next time; it does not corrupt new sessions.

#### What counts as a commitment

Record only:
- **Decisions** — chose A over B
- **Constraints** — "must support offline"
- **Scope** — feature must be in / out
- **Priorities** — A matters more than B
- **Key term definitions** — "Customer = paying entity, not User"

Do **not** record:
- Intermediate ideas or rejected proposals
- Single-point clarifications ("button on the left") unless they elevate to a principle
- Items marked TBD / pending
- Q&A answers that don't establish a cross-question stance

Append as `- [Cn] <statement> | added at Q<index>` to `## Commitments`.

#### When to run backtrack check

Run when **any** holds:
- ≥3 active commitments AND ≥5 questions since last check
- User makes a commitment-level statement (scope / priority / definition / quantity)
- Topic switch

#### Check procedure

1. **Read** `GRILLCOMMITMENTS.md` (do not rely on memory).
2. For each active commitment C, evaluate three dimensions against the new discussion:
   - **Alignment**: SUPPORTED / TENSION / **CONTRADICTED**
   - **Scope** (if C is about features/capabilities): PRESENT / WEAKENED / **ABSENT**
   - **Priority** (if C established ordering): MAINTAINED / SHIFTED / **REVERSED**
3. Classify and act:
   - **Hard** (Alignment = CONTRADICTED) → interrupt immediately: "和 C{n} 直接冲突——选一个。"
   - **Soft** (Scope = ABSENT or Priority = REVERSED) → confirm intent: "C{n} 之前说 X，现在像变了——确认是有意改吗？" If user confirms change, append `- [C{n} → modified at Q{m}] <reason>` to `## Modifications`.
   - **Warning** (TENSION / WEAKENED / SHIFTED) → log only, don't interrupt.
4. Append a `### After Q{m} (N commitments active)` block to `## Backtrack Check Log` listing each C's status.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

</supporting-info>
