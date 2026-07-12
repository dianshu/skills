---
name: tickets
description: Break a plan or spec into independently-grabbable tickets on the project ticket tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into tickets, create implementation tickets, or break down work into tickets.
---

# To Tickets

Break a plan into independently-grabbable tickets using vertical slices (tracer bullets).

Read `~/.claude/matt/ticket-tracker.md` and `~/.claude/matt/triage-labels.md` for the ticket tracker and triage label configuration.

Workflow position (parallels `/spec` → `/spec-review-loop` → `/spec` publish):

```
gather → draft slices → quiz user → step 5 publish FILES → /tickets-review-loop → step 6 apply triage labels
```

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an ticket reference (ticket number, URL, or path) as an argument, fetch it from the ticket tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the plan into **tracer bullet** tickets. Each ticket is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract** across normal ticket files, each phase a normal slice with normal `` `NN-slug.md` `` blocking edges:

- **expand** — add the new form beside the old so nothing breaks (one slice, no blockers).
- **migrate** — move the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket `Blocked by` the expand slice. CI stays green batch to batch because the old form still exists.
- **contract** — delete the old form once no caller remains, in a slice `Blocked by` every migrate batch.

When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify slice — green is promised only at that final slice. All edges are code dependencies, so they belong in `## Blocked by`, never in `## Hold`.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the ticket FILES to the ticket tracker

For each approved slice, write a new ticket file to the ticket tracker. Use the ticket body template below. Publish files in dependency order (blockers first) so you can reference real ticket identifiers in the "Blocked by" field. References MUST use the backtick-wrapped filename form (`` `NN-slug.md` ``) — see the template below. The `/run-all-tickets` skill enforces this format with a strict bullet parser; any other shape (PR-style `#NN`, plain prose, embedded references) makes the ticket undispatchable.

**Do NOT apply any triage label in this step.** The tickets are drafts pending review. Labels are applied in step 6 after `/tickets-review-loop` returns EXIT.

<ticket-template>
## Parent

A reference to the parent ticket on the ticket tracker (if the source was an existing ticket, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

One bullet per blocker. Each bullet's first token MUST be a backtick-wrapped reference to the blocker's ticket file (`` `NN-slug.md` ``); trailing prose / parenthetical context is allowed. Example:

- `` `01-schema-doc-and-transport-probe.md` `` (the probe event proves the datasource works end-to-end)
- `` `04-server-time-sync-and-ws-protocol.md` ``

Or `None - can start immediately` on its own line if there are no blockers.

Non-code gates (release-window signals, manual sign-offs, "wait 1 week of telemetry") do NOT belong in this section — they would be silently dropped by the `/run-all-tickets` parser and let the loop dispatch an ticket whose human gate is unmet. Put them in the ticket body, in a separate `## Hold` section, or out of the ticket entirely.

</ticket-template>

Do NOT close or modify any parent ticket.

### 5.5 Recommend `/tickets-review-loop`

After the ticket files land, suggest the user run `/tickets-review-loop <slug>` to adversarially review the ticket set before labelling them ready-for-agent. The review loop will catch:

- Vertical-slice violations (all-backend / all-frontend tickets that aren't demoable end-to-end)
- Undeclared semantic dependencies (ticket B uses schema from A but doesn't list A in `## Blocked by`)
- Granularity drift (multi-day epics or sub-task fragments)
- Acceptance criteria that aren't observable / testable
- spec-coverage gaps (User Stories with no ticket, orphan tickets)
- `## Blocked by` parser failures (deterministic regex — anything that would fail `/run-all-tickets` preflight)

The user may skip the review (e.g. for a trivial 1-ticket split) and go straight to step 6.

### 6. Apply triage labels (after review or skip)

Apply the appropriate triage label to each ticket file: AFK slices get `ready-for-agent` (they have a complete plan and acceptance criteria — no further triage needed); HITL slices get `ready-for-human`. Use `needs-triage` only if a slice is genuinely under-specified after `/tickets` ran.

Per `~/.claude/matt/ticket-tracker.md`, triage state is recorded as a `Status:` line near the top of each ticket file.
