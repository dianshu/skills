const { Workflow } = require('/home/fei/.claude/core/workflow.js');

async function main() {
  const result = await Workflow({
    scriptPath: '/home/fei/.claude/skills/review-with-agent/opencode-review.workflow.js',
    args: { 
      mode: 'code', 
      intent: 'Create a new manual-only /auto-improve-codebase-architecture skill for small trusted single-maintainer repositories. It must use consensus architecture discovery, deterministic trusted repository gates, serialized writers and review, and fail-closed Git-visible rollback. Hostile repository scripts, hostile prompt injection, production process isolation, and large-repository performance tuning are intentionally out of scope.'
    },
  });
  console.log(JSON.stringify(result, null, 2));
}

main().catch(console.error);