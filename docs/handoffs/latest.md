# Current handoff — Phase 21 Session 3 closure gate

Updated: 2026-10-05. Phase 20 is complete. Phase 21 Marketplace Trust &
Auction Policy implementation and browser/Compose verification are complete;
hosted closure remains pending. Phase 22 has not started. Start from the
[ExecPlan](../plans/phase-21-execplan.md) and [final policy report](../marketplace/phase-21-final.md).

All selected policies exist: stepped increments (ADR-018), hidden reserve
(ADR-019), and persisted regular/rapid closing (ADR-020). Closing policy is
draft-editable and freezes on scheduling; regular final-60/+90 and rapid
final-15/+10 use the existing auction lock, post-lock PostgreSQL clock and one
deadline decision per accepted external command. Proxy rows and replays do not
multiply extensions. Reserve still separates highest bidder from sale winner.

Public snapshots stay v2. Retained v1/early-v2 events normalize to regular;
earlier Redis v2 values validate their original digest and normalize safely,
including equivalent equal-revision replay. Cable remains a v1 invalidation.
The frontend displays rapid terms and adopts effective deadlines via REST.

Evidence: full backend 554 examples/0 failures/4 opt-in pending, seed 33589,
isolated Redis DB 15 and pool 15; five rapid race seeds, each 3 examples/0
failures; 78 frontend tests plus typecheck/lint/format/build; RuboCop 173
files/0 offenses, Zeitwerk, Brakeman and bundler-audit passed. Test migration
rollback/reapply and both populated-data downgrade guards passed. Final live smoke
auction 771/closed revision 5 passed A acceptance/B read and replay, +10 once,
€650/met, autonomous winner, real Kafka/Redis delivery and exact PostgreSQL
rebuild. Full browser: 9 passed, 1 historical opt-in skipped, 8.5 minutes.

Remaining: unlock GitHub SSH authentication, push verified work, then verify
hosted API/web/Compose success. Record completion only after that success;
push the final closure commit and require CI on its exact SHA. Explicit
anonymous/rate-limited rapid deadline assertions passed. An earlier browser
fixture expired during a real quota retry;
setup headroom and waiting into the actual window repaired it without weakening
the production limiter.
Session 1/2 evidence remains in the ExecPlan. No Phase 21 completion or hosted
CI success is claimed yet. No active reserve edits, payment reservations,
country/category restrictions, livestream infrastructure or Phase 22 work.

Push blocker: the runtime's existing GitHub SSH key is locked; HTTPS has no
saved login. The user has been asked to unlock the key locally, never to share
its passphrase. Commit/push is already authorized. Resumed local gate logs are
under ignored `apps/api/tmp/phase21-final-gate/`.
