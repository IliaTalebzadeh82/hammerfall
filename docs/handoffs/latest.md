# Current handoff — Phase 16 active, Session 1 checkpoint

Updated: 2026-10-02. Phase 16 Chaos Testing was explicitly authorized and
started from `2b9fb2fe2d7031c5a5b543afd48cf94e86ee540a`. The
[active ExecPlan](../plans/phase-16-execplan.md) and
[Session 1 report](../chaos/session-1.md) index retained local evidence.
Resume in a **fresh conversation**. Do not begin Phase 17.

Session 1 added a small Compose chaos harness and a direct PostgreSQL probe.
Baseline, Redis stop plus fixture projection-key loss and targeted repair,
Kafka outage, Sidekiq/publisher stop, Kafka publisher SIGKILL with pending
backlog, and live duplicate Kafka delivery all passed their direct checker and
final derived comparison. Expected temporary fallback/backlog was observed.
Both Kafka consumers explicitly logged duplicate treatment for one replayed
event; audit receipt/effect counts remained one per event. Three harness
preflight failures were fixed and retained in the report.

Next work: deterministic publisher post-broker/pre-ack and audit consumer
post-DB/pre-offset crash windows; API restart/ambiguous command retry and
API-only outage; worker/Cable and reconciliation failure integration. Later
fresh context owns broad regression, browser/runtime/CI gates, adversarial
review and phase completion. Do not infer the dangerous crash windows from
Session 1's generic SIGKILL; it occurred while Kafka was unavailable.

No authoritative correctness failure was observed. The stopped Sidekiq run
did not directly count WebSocket hints. Prometheus scrape samples missed some
short-lived fixture backlog, so direct SQL remains the recovery proof. Local
times are observations, not guarantees. Focused Ruby/Python checks and the
privacy scan passed; full phase completion gates remain outstanding.
