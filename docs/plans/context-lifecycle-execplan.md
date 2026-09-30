# Context lifecycle migration ExecPlan

Status: COMPLETE — documentation-only migration, 2026-09-30.
Current milestone: finalized.
Completed: established the context lifecycle, checkpoint/resume protocol,
ExecPlan convention, evidence index, output hygiene and routing. Phase 9 remains
unstarted.
Verified: 35 local Markdown links (including anchors) resolve; changed-file
scope, phase-spec/archive integrity and whitespace checks pass.
Remaining: none for this migration.
Known failures/limitations: no failures found. There is no measured effect on
a future phase's context size yet; this policy must be exercised during Phase 9.
Relevant files: `AGENTS.md`, `docs/context-lifecycle.md`, `docs/context-map.md`,
`docs/handoffs/latest.md`, `docs/progress.md`, this plan.
Relevant ADRs: none; auction architecture and ADR contracts are unchanged.
Next-session starting point: for an explicitly requested Phase 9, read
`AGENTS.md`, latest handoff and `docs/phases/phase-09.md`; create the Phase 9
ExecPlan using the new convention.

## Decisions

- D1 — Keep mandatory lifecycle rules short in `AGENTS.md`; place operational
  detail and the ExecPlan convention in one linked document to bound startup
  context.
- D2 — Preserve completed Phase 8 evidence and all future phase specifications;
  apply the new convention to future substantial plans and this migration plan.
- D3 — Keep `progress.md` as history and the handoff as a compact entry point;
  the active ExecPlan carries detailed working state.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Documentation scope | `git status --short` | 6 documentation/instruction files only | This plan; no application changes |
| Link resolution | Local Markdown file/anchor check | 35 links, zero broken | Six changed files checked |
| Phase/archive integrity | `git diff --quiet -- docs/phases docs/archive apps scripts` | Exit 0, unchanged | Phase 09–20 headings reviewed; no specs edited |
| Whitespace | `git diff --check` | Exit 0 | No whitespace errors |

## Verification note

No application test suite was run because this migration changes only
documentation and agent instructions. The handoff remains 33 lines; progress
history below its opening note is unchanged. Existing Phase 8 run evidence was
preserved without retrofitting its completed ExecPlan.
