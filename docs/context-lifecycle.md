# Codex context lifecycle

This is the detailed convention behind [AGENTS.md](../AGENTS.md). Preserve
engineering depth and verification; spend context on relevant evidence instead
of accumulated conversation. Repository state is durable working memory.

## Start and resume

- Start a substantial new phase in a fresh session after an explicit request.
  Read `AGENTS.md`, [latest handoff](handoffs/latest.md), and the current
  [phase specification](phases/). Create its ExecPlan in `docs/plans/` before
  implementation. Do not pre-create plans for unrequested phases.
- To resume an active phase, read `AGENTS.md`, the latest handoff, the active
  ExecPlan, and the current phase specification. Use the
  [context map](context-map.md) to select only architecture, ADR, source and
  tests needed for unresolved work. The kickoff prompt can be short because
  the specification and current state are in the repository.
- Do not reconstruct a phase by reading all previous specifications, progress
  history, ADRs, Git history or previously touched source. Read the archived
  master prompt only for a specific missing historical fact that active docs
  cannot answer. Expand context when a concrete question requires it.

## Read and output deliberately

- Use `rg`, `git grep`, the code map, targeted file listings and `git status`
  to locate a path before opening broad files. For large specs, tests, source,
  logs and [progress](progress.md), search first and read relevant ranges.
  Do not recursively read `docs/`, all architecture files or all ADRs.
- Reuse understanding of unchanged files in the same session. After edits,
  inspect `git diff --stat` and relevant hunks or `git show` for specific
  paths; reread whole files only when structural coherence requires it. Avoid
  broad history archaeology.
- Batch independent lightweight inspections when their outputs remain clear.
  Keep failure-prone commands separate enough to diagnose. If verification
  fails, inspect the failure excerpt, relevant implementation and test first;
  expand outward only if that does not explain it.
- Run the full rigor required by the phase. For large successful commands,
  keep full logs in files when useful and report command, exit status, test
  count, failure count, significant warnings and log location. For failures,
  retain the relevant error region and inspect more only as needed. Do not
  repeatedly tail unchanged logs or paste thousands of successful lines.
  Repeated concurrency runs should record count, example count, seeds/ranges
  and failures. Sabotage records need the exact change, expected failure,
  actual failing tests and restoration verification.
- Never save tokens by weakening reasoning, model choice, tests, sabotage,
  concurrency or security coverage, architecture records, or meaningful phase
  scope; never ignore failures or accept an uncertain implementation early.

## ExecPlan convention

Use `docs/plans/<topic>-execplan.md` for substantial work. It is the detailed
active-phase execution state; the latest handoff is the compact entry point.
Keep the plan concise and current, with links to durable ADRs instead of copied
decisions and links to logs instead of pasted output. A new session must be
able to resume without conversation history. Include these fields or clear
equivalents:

```text
Status:
Current milestone:
Completed:
Verified:
Remaining:
Known failures/limitations:
Relevant files:
Relevant ADRs:
Next-session starting point:
```

Add a short `## Decisions` ledger when choices need reasoning for resumption.
For architectural decisions, summarize the reason and link to the ADR. Every
substantial ExecPlan needs a concise `## Evidence Index`:

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Backend suite | `bundle exec rspec` | example/failure count | Log path or concise note |
| Failure scenario | Exact method | Observed result | Targeted details section |

Record actual runs, seeds, limitations and unrun checks honestly. The index
should let later sessions find proof without reopening raw logs or long
chronological history. Remove stale execution detail when the plan is complete.

## Checkpoint and phase boundary

Checkpoint after a coherent milestone, such as primary implementation, focused
tests, major integration or resolved debugging, especially before extensive
failure/sabotage/full regression work or when tool and log history is large.
Do not wait for automatic compaction or continue merely because the session
still fits. Do not fragment work after every small task; a small phase may fit
in one session.

1. Update the ExecPlan's milestone state, decisions, changed files/subsystems,
   completed verification and evidence index.
2. Record discovered failures, their resolution and restoration verification;
   identify remaining failures, limitations, work and the precise next step.
3. Update [latest handoff](handoffs/latest.md) when the compact entry point has
   changed. Keep it short: current phase, plan, key ADR/architecture links,
   implementation status, remaining work, blockers and verification status.
4. Stop with `CONTEXT CHECKPOINT READY`. Continue substantial remaining work
   in a fresh session using the resume path above.

Before declaring a phase complete, finish required implementation, tests,
lint, integration, adversarial review and local setup; record actual evidence
in the ExecPlan and [progress](progress.md), update relevant durable docs/ADRs,
rewrite the compact handoff, record limitations, and leave a clean repository.
End at the phase boundary. Do not start the next phase without a request.
Conversation history must contain no unique information needed for continuation.

`docs/progress.md` is chronological historical evidence, not startup context.
Use its phase headings/anchors to retrieve specific older results when needed;
the handoff and active ExecPlan carry current state.
