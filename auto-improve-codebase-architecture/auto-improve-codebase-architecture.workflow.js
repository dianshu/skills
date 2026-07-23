export const meta = {
  name: 'auto-improve-codebase-architecture',
  description: 'Automatically discover, implement, review, verify, or roll back one architecture-deepening refactor in a small personal repository.',
  phases: [{ title: 'Automatic architecture improvement' }],
}

phase('Automatic architecture improvement')

const { cwd, stateDir, guardPath, gateRunnerPath, architectureSkillDir } = args || {}
if (![cwd, stateDir, guardPath, gateRunnerPath, architectureSkillDir].every(value => typeof value === 'string' && value.length > 0)) {
  throw new Error('required args: cwd, stateDir, guardPath, gateRunnerPath, architectureSkillDir')
}

const shellQuote = value => "'" + String(value).replace(/'/g, "'\\''") + "'"

const OP_SCHEMA = {
  type: 'object',
  required: ['ok', 'detail', 'output'],
  properties: {
    ok: { type: 'boolean' },
    detail: { type: 'string' },
    output: { type: 'string' },
  },
}

const CANDIDATE_SCHEMA = {
  type: 'object',
  required: ['status', 'domainContext', 'seam', 'proposedChange', 'evidence', 'proposedPaths', 'reason'],
  properties: {
    status: { enum: ['candidate', 'noop'] },
    domainContext: { type: 'string' },
    seam: { type: 'string' },
    proposedChange: { type: 'string' },
    evidence: {
      type: 'object',
      required: ['code', 'tests', 'adrs', 'deletionTest', 'interfaceReduction', 'behaviorProtection'],
      properties: {
        code: { type: 'array', items: { type: 'string' } },
        tests: { type: 'array', items: { type: 'string' } },
        adrs: { type: 'array', items: { type: 'string' } },
        deletionTest: { type: 'string' },
        interfaceReduction: { type: 'string' },
        behaviorProtection: { type: 'string' },
      },
    },
    proposedPaths: { type: 'array', items: { type: 'string' } },
    reason: { type: 'string' },
  },
}

const CONSENSUS_SCHEMA = {
  type: 'object',
  required: ['unanimous', 'candidate', 'reason'],
  properties: {
    unanimous: { type: 'boolean' },
    candidate: CANDIDATE_SCHEMA,
    reason: { type: 'string' },
  },
}

const FALSIFIER_SCHEMA = {
  type: 'object',
  required: ['clear', 'counterexamples', 'reason'],
  properties: {
    clear: { type: 'boolean' },
    counterexamples: { type: 'array', items: { type: 'string' } },
    reason: { type: 'string' },
  },
}

const ADJUDICATION_SCHEMA = {
  type: 'object',
  required: ['approve', 'reason'],
  properties: {
    approve: { type: 'boolean' },
    reason: { type: 'string' },
  },
}

const GATES_SCHEMA = {
  type: 'object',
  required: ['status', 'root', 'commands', 'reason'],
  properties: {
    status: { enum: ['ready', 'noop'] },
    root: { type: 'string' },
    commands: {
      type: 'array',
      items: {
        type: 'object',
        required: ['category', 'source', 'command'],
        properties: {
          category: { enum: ['test', 'integration', 'e2e', 'lint', 'typecheck', 'build'] },
          source: { type: 'string' },
          command: { type: 'string' },
        },
      },
    },
    reason: { type: 'string' },
  },
}

const PLAN_SCHEMA = {
  type: 'object',
  required: ['status', 'paths', 'preservedBehaviors', 'contractMigrations', 'intent', 'reason'],
  properties: {
    status: { enum: ['ready', 'noop'] },
    paths: { type: 'array', items: { type: 'string' } },
    preservedBehaviors: { type: 'array', items: { type: 'string' } },
    contractMigrations: { type: 'array', items: { type: 'string' } },
    intent: { type: 'string' },
    reason: { type: 'string' },
  },
}

const WRITE_SCHEMA = {
  type: 'object',
  required: ['ok', 'changedPaths', 'testsAddedOrChanged', 'summary'],
  properties: {
    ok: { type: 'boolean' },
    changedPaths: { type: 'array', items: { type: 'string' } },
    testsAddedOrChanged: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['complete', 'findings', 'summary'],
  properties: {
    complete: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['category', 'file', 'line', 'problem', 'evidence'],
        properties: {
          category: { enum: ['correctness', 'scope', 'testing'] },
          file: { type: 'string' },
          line: { type: ['integer', 'string'] },
          problem: { type: 'string' },
          evidence: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

const result = (status, reason, evidence = {}) => ({ status, reason, evidence })

const parseLastJsonLine = output => {
  const lines = String(output || '').trim().split('\n').filter(Boolean)
  return lines.length > 0 ? JSON.parse(lines[lines.length - 1]) : null
}

const validRunPayload = payload => {
  if (!payload || !['PASS', 'NOOP', 'FAILED', 'FAILED_ROLLED_BACK', 'ROLLBACK_FAILED'].includes(payload.status)) return false
  if (typeof payload.reason !== 'string' || !Number.isInteger(payload.gates) || !Number.isInteger(payload.behaviorGates)) return false
  return payload.status !== 'PASS' || (payload.gates >= 1 && payload.behaviorGates >= 1)
}

async function rollback(reason, evidence) {
  try {
  const rollbackResult = await agent(`Work only in ${cwd}. Run exactly this deterministic rollback command and report its real exit result:\n\nbash ${shellQuote(guardPath)} rollback ${shellQuote(stateDir)}\n\nDo not edit files and do not run any other recovery command. Return the command stdout verbatim in output.`, {
    label: 'guard rollback',
    tier: 'small',
    schema: OP_SCHEMA,
  })
  let rollbackPayload = null
  try {
    rollbackPayload = rollbackResult ? parseLastJsonLine(rollbackResult.output) : null
  } catch {}
  if (rollbackResult && rollbackResult.ok && rollbackPayload && rollbackPayload.status === 'FAILED_ROLLED_BACK') {
    return result('FAILED_ROLLED_BACK', reason, { ...evidence, rollback: rollbackResult })
  }
  return result('ROLLBACK_FAILED', reason, { ...evidence, rollback: rollbackResult })
  } catch (error) {
    return result('ROLLBACK_FAILED', reason, { ...evidence, rollbackError: String(error) })
  }
}

async function scopeCheck(label, requireNonempty) {
  const option = requireNonempty ? ' --require-nonempty' : ''
  return await agent(`Work only in ${cwd}. Run exactly:\n\nbash ${shellQuote(guardPath)} check-scope ${shellQuote(stateDir)}${option}\n\nDo not edit files. Set ok only from the command exit status.`, {
    label,
    tier: 'small',
    schema: OP_SCHEMA,
  })
}

async function finalIntegrityCheck() {
  return await agent(`Work only in ${cwd}. Run exactly both commands:\n\nbash ${shellQuote(guardPath)} check-scope ${shellQuote(stateDir)} --require-nonempty\nbash ${shellQuote(guardPath)} check-diff ${shellQuote(stateDir)}\n\nDo not edit files. Set ok only when both commands exit 0.`, {
    label: 'final integrity check',
    tier: 'small',
    schema: OP_SCHEMA,
  })
}

let rollbackArmed = false
try {
const preflight = await agent(`Run exactly:\n\ncd ${shellQuote(cwd)} && bash ${shellQuote(guardPath)} preflight ${shellQuote(stateDir)}\n\nDo not edit repository files. Set ok only when the command exits 0; include its output verbatim.`, {
  label: 'guard preflight',
  tier: 'small',
  schema: OP_SCHEMA,
})
if (!preflight || !preflight.ok) {
  return result('NO-OP', 'PREFLIGHT_FAILED', { preflight })
}

const explorerPrompt = `Read-only architecture exploration in ${cwd}. Read project CONTEXT.md/CONTEXT-MAP.md and relevant ADRs when present, plus ${architectureSkillDir}/LANGUAGE.md and ${architectureSkillDir}/DEEPENING.md. Do not edit files. Find at most one evidence-backed deepening candidate in one domain context and one seam. It must: (1) show current friction in code/tests/ADRs, (2) pass the deletion test, (3) reduce caller interface obligations, (4) be protectable by behavior tests, and (5) have no unresolved ADR conflict. Reject aesthetic cleanup, speculative abstraction, dependency upgrades, and unrelated work. proposedPaths must be repository-relative files that the change and its tests would need. Return noop rather than guessing.`

const explorers = await parallel([
  () => agent(explorerPrompt, { label: 'explorer alpha', tier: 'medium', schema: CANDIDATE_SCHEMA }),
  () => agent(explorerPrompt, { label: 'explorer beta', tier: 'medium', schema: CANDIDATE_SCHEMA }),
  () => agent(explorerPrompt, { label: 'explorer gamma', tier: 'medium', schema: CANDIDATE_SCHEMA }),
])
if (explorers.some(candidate => candidate === null || candidate.status !== 'candidate')) {
  return result('NO-OP', 'NO_UNANIMOUS_CANDIDATE', { explorers })
}

const consensus = await agent(`Read-only. Compare the three independent Candidate objects below against the repository at ${cwd}. Approve unanimity only when they normalize to the same domainContext, seam, and substantive proposedChange, with compatible evidence and paths. Do not merge different candidates or invent a hybrid.\n\n${JSON.stringify(explorers)}`, {
  label: 'candidate consensus',
  tier: 'big',
  schema: CONSENSUS_SCHEMA,
})
if (!consensus || !consensus.unanimous || consensus.candidate.status !== 'candidate') {
  return result('NO-OP', 'NO_UNANIMOUS_CANDIDATE', { explorers, consensus })
}

const falsifier = await agent(`Read-only adversarial check in ${cwd}. Try to disprove this candidate with concrete repository evidence: hidden callers, ADR conflict, dynamic references, behavior that cannot be protected, a failed deletion test, an interface that does not actually shrink, or evidence that this is aesthetic/speculative. Do not propose alternatives. Candidate:\n${JSON.stringify(consensus.candidate)}`, {
  label: 'candidate falsifier',
  tier: 'medium',
  schema: FALSIFIER_SCHEMA,
})
if (!falsifier || !falsifier.clear || falsifier.counterexamples.length > 0) {
  return result('NO-OP', 'CANDIDATE_FALSIFIED', { explorers, consensus, falsifier })
}

const adjudicationPrompt = `Read-only final admission decision in ${cwd}. Approve only if the candidate has cited repository evidence, one context and seam, a positive deletion test, a smaller interface obligation, behavior-test protection, no unresolved ADR conflict, and no unresolved falsifier counterexample. Do not edit or improve the proposal.\nCandidate: ${JSON.stringify(consensus.candidate)}\nFalsifier: ${JSON.stringify(falsifier)}`
const adjudicators = await parallel([
  () => agent(adjudicationPrompt, { label: 'adjudicator one', tier: 'medium', schema: ADJUDICATION_SCHEMA }),
  () => agent(adjudicationPrompt, { label: 'adjudicator two', tier: 'medium', schema: ADJUDICATION_SCHEMA }),
])
if (adjudicators.some(decision => decision === null || !decision.approve)) {
  return result('NO-OP', 'ADJUDICATION_REJECTED', { explorers, consensus, falsifier, adjudicators })
}

const gates = await agent(`Work only in ${cwd}. Run exactly:\n\nbash ${shellQuote(gateRunnerPath)} discover ${shellQuote(stateDir)}\n\nDo not edit repository files and do not invent, omit, reorder, or rewrite gates. If the command succeeds, read ${stateDir}/gates.tsv and return its rows exactly as commands with their category and source; set root to ${cwd}. If it fails, return noop with the real error.`, {
  label: 'gate discovery',
  tier: 'medium',
  schema: GATES_SCHEMA,
})
if (!gates || gates.status !== 'ready' || gates.commands.length === 0) {
  return result('NO-OP', 'GATE_DISCOVERY_FAILED', { gates })
}

const plan = await agent(`Read-only scope plan in ${cwd}. Produce the smallest frozen path list for the admitted candidate, including any behavior tests needed to preserve the listed behaviors and only necessary technical docs. Paths must be repository-relative. Do not include CONTEXT.md, CONTEXT-MAP.md, ADRs, dependency manifests for upgrades, generated files, or unrelated cleanup. List observable behaviors to preserve and any closed-world contract migrations. Return noop if the complete path set cannot be known before editing.\nCandidate: ${JSON.stringify(consensus.candidate)}\nGate manifest: ${JSON.stringify(gates)}`, {
  label: 'change planner',
  tier: 'big',
  schema: PLAN_SCHEMA,
})
if (!plan || plan.status !== 'ready' || plan.paths.length === 0 || plan.preservedBehaviors.length === 0) {
  return result('NO-OP', 'SCOPE_PLANNING_FAILED', { plan })
}

rollbackArmed = true
const armed = await agent(`Work only in ${cwd}. Run exactly:\n\nbash ${shellQuote(guardPath)} arm ${shellQuote(stateDir)}\n\nDo not edit repository files. Set ok only from the command exit status.`, {
  label: 'guard arm',
  tier: 'small',
  schema: OP_SCHEMA,
})
if (!armed || !armed.ok) {
  return await rollback('ROLLBACK_ARM_FAILED', { armed })
}

const baselineRun = await agent(`Work only in ${cwd}. Run exactly this deterministic frozen-gate command:\n\nbash ${shellQuote(gateRunnerPath)} run ${shellQuote(stateDir)} baseline ${shellQuote(guardPath)} >/dev/null && cat ${shellQuote(stateDir + '/gate-result.json')}\n\nDo not edit files, install tools, or run gates yourself. Return the complete command output verbatim.`, {
  label: 'baseline gates',
  tier: 'small',
  schema: OP_SCHEMA,
})
let baselinePayload = null
try {
  baselinePayload = baselineRun && baselineRun.ok ? parseLastJsonLine(baselineRun.output) : null
} catch {}
const baseline = { run: baselineRun, payload: baselinePayload }
if (!validRunPayload(baselinePayload)) {
  return await rollback('BASELINE_RUNNER_FAILED', { gates, baseline })
}
if (baselinePayload.status === 'NOOP') {
  return result('NO-OP', 'BASELINE_FAILED', { gates, baseline })
}
if (baselinePayload.status === 'FAILED_ROLLED_BACK') {
  return result('FAILED_ROLLED_BACK', 'BASELINE_CHANGED_WORKTREE', { gates, baseline })
}
if (baselinePayload.status === 'ROLLBACK_FAILED') {
  return result('ROLLBACK_FAILED', 'BASELINE_CHANGED_WORKTREE', { gates, baseline })
}
if (baselinePayload.status !== 'PASS') {
  return await rollback('BASELINE_INVALID', { gates, baseline })
}

const frozen = await agent(`Work only in ${cwd}. Run the deterministic guard with exactly the frozen repository-relative paths below:\n\nbash ${shellQuote(guardPath)} freeze ${shellQuote(stateDir)} ${plan.paths.map(shellQuote).join(' ')}\n\nDo not edit files. Set ok only from the command exit status.\nPaths: ${JSON.stringify(plan.paths)}`, {
  label: 'scope freeze',
  tier: 'small',
  schema: OP_SCHEMA,
})
if (!frozen || !frozen.ok) {
  return await rollback('SCOPE_FREEZE_FAILED', { plan, frozen })
}

const implementation = await agent(`You are the sole source-writer role for this run. Every file read/write and shell command must use an absolute path rooted at ${cwd}; never rely on the process working directory. Implement exactly one admitted architecture deepening within the frozen paths. First add or strengthen behavior tests for plan.preservedBehaviors, then make the minimum production change. Respect ${architectureSkillDir}/LANGUAGE.md and ${architectureSkillDir}/DEEPENING.md. Do not modify files outside plan.paths; do not modify CONTEXT.md, CONTEXT-MAP.md, ADRs, dependency versions, generated files, or unrelated code; do not commit. If the plan is insufficient, return ok=false without expanding scope.\n\nCandidate: ${JSON.stringify(consensus.candidate)}\nPlan: ${JSON.stringify(plan)}\nBaseline: ${JSON.stringify(baseline)}`, {
  label: 'single writer implement',
  tier: 'big',
  schema: WRITE_SCHEMA,
})
if (!implementation || !implementation.ok) {
  return await rollback('IMPLEMENTATION_FAILED', { implementation })
}

const scopeAfterWrite = await scopeCheck('scope after write', true)
if (!scopeAfterWrite || !scopeAfterWrite.ok) {
  return await rollback('SCOPE_VIOLATION', { implementation, scopeAfterWrite })
}

const firstReview = await agent(`Read-only independent review in ${cwd}. Review the current uncommitted diff against the frozen intent and paths. Report only concrete correctness, scope, or testing defects with file/line evidence. Do not report style preferences, alternative designs, pre-existing issues, or unrelated cleanup. Do not edit files.\nIntent: ${plan.intent}\nFrozen plan: ${JSON.stringify(plan)}\nImplementation: ${JSON.stringify(implementation)}`, {
  label: 'review first pass',
  tier: 'big',
  schema: REVIEW_SCHEMA,
})
if (!firstReview || !firstReview.complete) {
  return await rollback('REVIEW_FAILED', { firstReview })
}

let finalReview = firstReview
let fixResult = null
if (firstReview.findings.length > 0) {
  fixResult = await agent(`You are the same serialized source-writer role. Every file read/write and shell command must use an absolute path rooted at ${cwd}; never rely on the process working directory. Fix exactly the independently evidenced findings below, once, within the already frozen paths. Do not expand scope, redesign the candidate, perform cleanup, or commit. If a finding requires any new path or broader change, return ok=false.\nPlan: ${JSON.stringify(plan)}\nFindings: ${JSON.stringify(firstReview.findings)}`, {
    label: 'single writer fix',
    tier: 'big',
    schema: WRITE_SCHEMA,
  })
  if (!fixResult || !fixResult.ok) {
    return await rollback('REVIEW_FIX_FAILED', { firstReview, fixResult })
  }
  const scopeAfterFix = await scopeCheck('scope after fix', true)
  if (!scopeAfterFix || !scopeAfterFix.ok) {
    return await rollback('REVIEW_FIX_SCOPE_VIOLATION', { firstReview, fixResult, scopeAfterFix })
  }
  finalReview = await agent(`Read-only re-review in ${cwd}. Verify only whether every prior finding is fixed and whether that single fix introduced a new correctness, scope, or testing defect. Do not add style suggestions or alternative designs. Do not edit files.\nPlan: ${JSON.stringify(plan)}\nPrior findings: ${JSON.stringify(firstReview.findings)}\nFix: ${JSON.stringify(fixResult)}`, {
    label: 'review second pass',
    tier: 'big',
    schema: REVIEW_SCHEMA,
  })
  if (!finalReview || !finalReview.complete || finalReview.findings.length > 0) {
    return await rollback('REVIEW_NOT_CLEAN', { firstReview, fixResult, finalReview })
  }
}

const verificationRun = await agent(`Work only in ${cwd}. Run exactly this deterministic frozen-gate command:\n\nbash ${shellQuote(gateRunnerPath)} run ${shellQuote(stateDir)} final ${shellQuote(guardPath)} >/dev/null && cat ${shellQuote(stateDir + '/gate-result.json')}\n\nDo not edit files, install tools, rediscover gates, or run any other command. Return the complete command output verbatim.\nFrozen plan: ${JSON.stringify(plan)}`, {
  label: 'final gate verifier',
  tier: 'small',
  schema: OP_SCHEMA,
})
let verificationPayload = null
try {
  verificationPayload = verificationRun && verificationRun.ok ? parseLastJsonLine(verificationRun.output) : null
} catch {}
const verification = { run: verificationRun, payload: verificationPayload }
if (!validRunPayload(verificationPayload) || verificationPayload.status !== 'PASS') {
  return await rollback('FINAL_VERIFICATION_FAILED', { verification, firstReview, fixResult, finalReview })
}

const finalScope = await finalIntegrityCheck()
if (!finalScope || !finalScope.ok) {
  return await rollback('FINAL_SCOPE_FAILED', { verification, finalScope })
}

return result('VERIFIED', 'ALL_GATES_PASSED', {
  candidate: consensus.candidate,
  explorers,
  falsifier,
  adjudicators,
  gates,
  baseline,
  plan,
  implementation,
  firstReview,
  fixResult,
  finalReview,
  verification,
  finalScope,
})
} catch (error) {
  if (rollbackArmed) {
    return await rollback('WORKFLOW_EXCEPTION', { error: String(error) })
  }
  return result('NO-OP', 'WORKFLOW_EXCEPTION', { error: String(error) })
}
