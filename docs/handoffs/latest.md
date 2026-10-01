# Current handoff — Phase 14 Load Testing in progress

Updated: 2026-10-01. Phase 13 is complete; Phase 14 was explicitly requested
and its first milestone is complete. This is a hard checkpoint. Resume in a
fresh Codex conversation with `AGENTS.md`, [Phase 14](../phases/phase-14.md),
the [active ExecPlan](../plans/phase-14-execplan.md) and targeted architecture
from the [context map](../context-map.md). The ExecPlan Evidence Index and
[benchmark index](../benchmarks/README.md) contain exact run evidence.

Harness commit `c86f4f8` added pinned k6 1.8.1, isolated demo-API fixtures,
normal/hot/duplicate scenarios, read-only warm-up, environment/telemetry capture,
PostgreSQL correctness verification and per-run reports. The primary runs used
the unchanged Compose application configuration with API observability enabled.
Normal 4 VU, hot 8 VU and duplicate 8 VU runs completed with zero unexpected
HTTP failures and zero checker failures. One hot auction yielded 370 accepted
bids and 1,149 expected domain rejections in 30 seconds. Duplicate retries
produced one logical bid from 2,507 HTTP attempts. These are short local runs,
not a capacity threshold. Earlier exploratory runs found and corrected a
fixture-selection correlation, an observability enablement mistake and a
too-early metric snapshot; the raw evidence is retained and labeled.

Next: closing storm and closer race, feasible 1,000-bidder challenge, WebSocket
fanout, stepped saturation, repeatability, trace/lock/pool/publisher analysis,
checker/classifier sabotage, full regression, Compose/browser/hosted CI and
final documentation/adversarial review. No Phase 15 optimization has begun.
Use fresh fixtures for each run, keep `OTEL_ENABLED=true` for primary evidence,
and preserve PostgreSQL authority. The current tree should be clean after the
checkpoint evidence commit; verify at resume.
