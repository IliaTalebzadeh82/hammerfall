# Phase 16 chaos evidence

Each `p16-*` directory is an isolated Compose run. `timeline.json` records UTC
actions and the starting SHA; stage JSON files contain PostgreSQL, ordinary GET,
eventual GET and (in later runs) sampled Prometheus observations. `verify.json`
is the direct PostgreSQL correctness checker. No raw request body, private
maximum, idempotency key or full process log is retained.

[Session 1 report](session-1.md) is the evidence index and interpretation.
The [Session 2 report](session-2.md) covers ambiguous publisher, consumer and
HTTP crash windows. The [final review](phase-16-final.md) and
[final gates](final-gates.md) reconcile these sessions with browser recovery,
regression, runtime and CI evidence.
The three early failed/aborted baseline directories are retained as harness
preflight failures, not treated as Hammerfall failures or successful campaigns.

Run from the repository root with the normal Compose stack and observability
profile already started:

```sh
python3 scripts/chaos/run.py baseline
python3 scripts/chaos/run.py redis
python3 scripts/chaos/run.py kafka
python3 scripts/chaos/run.py worker
python3 scripts/chaos/run.py publisher
python3 scripts/chaos/run.py duplicate
```

The harness has a 120-second convergence deadline, samples every five seconds,
and starts stopped dependencies in `finally` on ordinary failures. A host kill
or power loss can bypass that cleanup; check `docker compose ps` before rerun.
These are local observations, not availability or recovery guarantees.
