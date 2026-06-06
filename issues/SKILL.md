---
name: issues
description: Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

Read `~/.claude/matt/issue-tracker.md` and `~/.claude/matt/triage-labels.md` for the issue tracker and triage label configuration.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

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

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. Apply the appropriate triage label: AFK slices get `ready-for-agent` (they have a complete plan and acceptance criteria — no further triage needed); HITL slices get `ready-for-human`. Use `needs-triage` only if a slice is genuinely under-specified after this skill ran.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field. References MUST use the backtick-wrapped filename form (`` `NN-slug.md` ``) — see the template below. The `/run-all-issues` skill enforces this format with a strict bullet parser; any other shape (PR-style `#NN`, plain prose, embedded references) makes the issue undispatchable.

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

One bullet per blocker. Each bullet's first token MUST be a backtick-wrapped reference to the blocker's issue file (`` `NN-slug.md` ``); trailing prose / parenthetical context is allowed. Example:

- `` `01-schema-doc-and-transport-probe.md` `` (the probe event proves the datasource works end-to-end)
- `` `04-server-time-sync-and-ws-protocol.md` ``

Or `None - can start immediately` on its own line if there are no blockers.

Non-code gates (release-window signals, manual sign-offs, "wait 1 week of telemetry") do NOT belong in this section — they would be silently dropped by the `/run-all-issues` parser and let the loop dispatch an issue whose human gate is unmet. Put them in the issue body, in a separate `## Hold` section, or out of the issue entirely.

</issue-template>

Do NOT close or modify any parent issue.
