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
- Read the mandatory entry documents individually or in bounded form. Then
  discover relevant source and docs before loading them. Do not make one large
  startup dump of the context map, multiple architecture docs and ADRs, and
  large source or test files just to save tool calls.

## Read and output deliberately

- Read narrow-first: locate with the [context map](context-map.md), `rg`,
  `git grep`, the code map or targeted listings; inspect headings, matches,
  changed hunks or relevant test names; read the smallest useful section with
  a targeted range; expand only when needed. If an initial command would dump
  tens of kilobytes across files, narrow the discovery first. Do not
  recursively read `docs/`, all architecture files or all ADRs.
- Reuse understanding of unchanged files in the same session. After edits,
  inspect `git diff --stat` and relevant hunks or `git show` for specific
  paths; reread whole files only when structural coherence requires it. Avoid
  broad history archaeology.
- Prefer fewer, more purposeful model/tool cycles without reducing reasoning
  or verification quality. Batch related lightweight inspections and known
  narrow steps when outputs stay bounded and clear; avoid one tiny shell call
  per obvious step, repeated Git/status/log queries for unchanged information,
  and needless check-then-recheck loops. Do not create giant commands or
  outputs. Keep failure-prone operations separate enough to diagnose.
- Diagnose failures from the failure excerpt, relevant implementation and
  test, a targeted hypothesis, and a focused rerun. Expand only when needed;
  do not repeatedly tail the same log, dump whole Docker logs or diffs,
  inspect unrelated services, or rerun the full suite for a local failure.
  Stop gathering redundant evidence once the cause is understood.
- Stage verification: focused checks during implementation, then live failure,
  recovery, concurrency or sabotage work required by the phase; repair found
  issues, run focused confirmation, and run one final broad completion gate.
  Avoid premature full-suite reruns. Rerun the appropriate broad gate when a
  late change affects broad behavior; never skip required final regression.
- Run the full rigor required by the phase. For large successful commands,
  keep full logs in files when useful and report command, exit status, test
  count, failure count, significant warnings and log location. For failures,
  retain the relevant error region and inspect more only as needed. Do not
  repeatedly tail unchanged logs or paste thousands of successful lines.
  Repeated concurrency runs should record count, example count, seeds/ranges
  and failures. Sabotage records need the exact change, expected failure,
  actual failing tests and restoration verification.
- Never save tokens or cycles by weakening reasoning, switching to a weaker
  model, skipping tests, sabotage, concurrency or security coverage, real
  infrastructure checks, architecture/docs, or meaningful phase scope; never
  ignore failures or accept an uncertain implementation early.

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

Update the index after each meaningful milestone, such as focused tests, a live
outage, sabotage, browser/runtime proof or final regression. For each check,
record its command or method, actual result and important evidence or log path.
Record seeds, limitations and unrun checks honestly; do not paste full logs.
The index should let later sessions find proof without reopening raw logs or
long chronological history. Remove stale execution detail when the plan is
complete.

## Checkpoint and phase boundary

**Hard invariant:** Once a session checkpoint is triggered, the current Codex
run ends. Continuing substantial phase work in the same conversation after
`CONTEXT CHECKPOINT READY` is a lifecycle violation. A checkpoint is a terminal
operation for this conversation, not merely a heading or note in the ExecPlan.
The user starts a new Codex conversation for continuation; writing checkpoint
documentation and continuing in the current conversation does not provide a
fresh-session reset.

Decide *whether* a checkpoint is needed at a coherent work boundary, not a
token threshold. Primary implementation and focused tests complete with
substantial live/integration verification remaining requires a checkpoint.
Completed live failure, recovery, concurrency or sabotage work with substantial
repair, broad regression, browser/runtime verification, documentation or
adversarial review remaining also requires a checkpoint. Major debugging
history and a cleanly resumable next work category reinforce the decision.
Do not wait for automatic compaction or continue merely because context space
remains. Small phases may finish in one conversation; do not create sessions
mechanically. **Once a checkpoint is required, stopping is mandatory; there is
no further decision about whether to continue in the same conversation.**

When a session checkpoint triggers:

1. Finish only the current coherent milestone. Do not begin the next one.
2. Update the active ExecPlan's milestone state, decisions, changed
   files/subsystems and incremental Evidence Index. Record completed
   implementation, completed verification, failures found and fixed, remaining
   work (including failure tests, regression and documentation), known
   limitations and the exact next action. Record failure resolution and
   restoration evidence where applicable.
3. Update [latest handoff](handoffs/latest.md) when the compact entry point has
   changed. Keep it short: current phase, plan, key ADR/architecture links,
   implementation status, remaining work, blockers and verification status.
4. Ensure repository state is coherent and preferably clean/committed according
   to the current phase plan. Return a concise checkpoint report whose final
   line is exactly `CONTEXT CHECKPOINT READY`.
5. **Stop.** Do not start the next milestone, verification campaign, unrelated
   debugging, broad regression or documentation finalization in this
   conversation. The user starts a fresh Codex conversation, which resumes
   from the ExecPlan, Evidence Index, handoff and targeted context above.

For a substantial phase, a useful milestone-driven pattern is:

```text
SESSION 1: plan, implementation, focused verification
If substantial live/integration work remains: persist checkpoint; STOP.

FRESH SESSION 2: live integration, failure recovery, concurrency, sabotage,
                 adversarial investigation
If substantial repair/regression/docs remain: persist checkpoint; STOP.

FRESH SESSION 3 IF NEEDED: repairs, final broad regression, browser/runtime
                           verification, security/build, documentation,
                           handoff and completion
```

Bounded phases may use two sessions or finish in one. This pattern does not
change phase scope, technical requirements or verification gates.

Before declaring a phase complete, finish required implementation, tests,
lint, integration, adversarial review and local setup; record actual evidence
in the ExecPlan and [progress](progress.md), update relevant durable docs/ADRs,
rewrite the compact handoff, record limitations, and leave a clean repository.
End at the phase boundary. Do not start the next phase without a request.
Conversation history must contain no unique information needed for continuation.

`docs/progress.md` is chronological historical evidence, not startup context.
Use its phase headings/anchors to retrieve specific older results when needed;
the handoff and active ExecPlan carry current state.
