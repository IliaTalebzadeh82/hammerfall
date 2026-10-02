# Current handoff — Phase 17 Session 2 checkpoint

Updated: 2026-10-02. Phase 17 remains active; Phase 18 is excluded. Resume in
a fresh conversation with [Phase 17](../phases/phase-17.md), the
[active ExecPlan](../plans/phase-17-execplan.md) and the
[Session 2 report](../multi-instance/session-2.md). Session 1's initial
two-replica/proxy and sequential/concurrent command proof is retained in its
[report](../multi-instance/session-1.md); do not replay it without a concrete
invalidation.

The local nginx endpoint `localhost:3001` routes ordinary HTTP and Cable to
two Rails/Puma processes without affinity. Session 2 used a local upgrade
header plus Chrome DevTools to prove a browser WebSocket on `a` received a
PostgreSQL-backed revision hint caused by a bid on `b`, and the inverse. The
browser fetched the matching public revision by REST and displayed the price;
the hint carried only `type`, `auction_id`, `revision`. A scoped missed hint
while Sidekiq was stopped still recovered through browser visibility REST.

Stopping socket-owning `b` closed the WebSocket. One run resubscribed on `a`;
later runs did not show a new handshake within 30 seconds. In all retained
runs, `a` served new bids and GETs, browser REST recovered current state and
restarted `b` read the current PostgreSQL revision through the proxy without
reconstruction. Investigate the variable automatic reconnect behavior before
final closure; do not claim uninterrupted realtime failover.

Scoped process death on `b` after commit produced HTTP 502, then same-key
replay on `a` returned the original 201 with no extra bid, revision, outbox
row or command effect. Death before commit left no partial SQL state; the same
key executed once on `a`. Direct PostgreSQL snapshots proved both boundaries.
Cross-replica bids waiting behind one auction lock produced two valid soft-close
bids with one extension in that timing. A separate race held both bids until
after PostgreSQL time passed the deadline; both were rejected. An autonomous
closer racing a waiting bid finalized one coherent closed state. Existing
focused tests prove the complementary close order and duplicate close safety.

Session 2 focused RSpec passed 82 examples with zero failures (seed 39585).
Targeted RuboCop, Biome, Ruby/Python/Node syntax, nginx/Compose validation and
diff checks passed. A bounded PostgreSQL snapshot showed 11 client backends
against 100 configured connections. No pool/thread/DB limit or business rule
changed. Final full backend/frontend regression, clean Compose recreation,
browser regression, hosted CI, adversarial review and documentation
reconciliation belong to Session 3. Phase 17 is **not complete**.
