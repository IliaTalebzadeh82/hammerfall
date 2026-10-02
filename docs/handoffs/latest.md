# Current handoff — Phase 17 Session 1 checkpoint

Updated: 2026-10-02. Phase 17 is active; Phase 18 is excluded. Start the next
fresh session with [Phase 17](../phases/phase-17.md), the
[active ExecPlan](../plans/phase-17-execplan.md), and the
[Session 1 report](../multi-instance/session-1.md). The retained
[three runs](../multi-instance/session-1-runs.jsonl) are concise public
evidence; no Phase 16 raw chaos reread is needed.

The normal localhost:3001 API endpoint now reaches a local nginx proxy and two
separate Rails/Puma containers. The web server uses that same proxy. A bounded
development-only header identifies `a` or `b`; it is diagnostic only. Existing
closer, worker, publishers, consumers and reconciliation scheduler remain
separate single operational roles. PostgreSQL remains auction, time, sequence,
priority, idempotency, revision and outbox authority; development Cable already
uses the PostgreSQL adapter.

Six GETs alternated between replicas. Three retained end-to-end runs passed
sequential commands, ten simultaneous bids on one auction, equal maximum-bid
priority and concurrent same-key requests plus replay on another replica. The
verifier checked direct PostgreSQL results. Focused real-PostgreSQL tests passed
80 examples with zero failures; targeted RuboCop/static/proxy checks and the
established sequential API smoke through the proxy passed. CI has a new
cross-replica step but has not run. No application-domain correctness failure
was observed; invalid initial proxy and verifier assumptions were repaired and
are described in the report. Two API pools of three can reserve six connections;
14 client backends were observed against a 100-connection local maximum.

Session 2 should prove Cable notification from a mutation on the opposite API
process, REST recovery, replica stop/rejoin, ambiguous same-key retry onto a
different replica, and deadline/soft-close races. Then checkpoint before final
broad, browser, hosted CI and adversarial verification. Do not call Phase 17
complete or begin Phase 18 yet.
