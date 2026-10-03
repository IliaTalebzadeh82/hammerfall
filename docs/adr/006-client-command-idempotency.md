# ADR-006: Client command idempotency

Status: Accepted — Phase 5, 2026-09-25

## Context and failure scenario

A transaction protects a command's writes, not a client's knowledge of its outcome.
The server can commit a bid/proxy contest/extension and lose the HTTP response.
An unprotected retry then evaluates different state, may reject an already accepted
command, or repeat a mutation. This must work across independent Rails processes.

## Decision and scope

Protect POST /api/v1/auctions/:auction_id/bids and PUT
/api/v1/auctions/:id/maximum-bid. Require Idempotency-Key: 1–255 visible ASCII
characters (no spaces/control characters); UUID format is not required. Missing
header is 400 idempotency_key_required; malformed/blank is 400
invalid_idempotency_key. Lifecycle endpoints and the internal closer are unchanged.

Logical scope is **(actor_id, operation, client key)**. PostgreSQL uniquely indexes
(actor_id,operation,key_digest). The original Phase 5 representation was SHA-256 of
the raw key. Phase 20 Session 2 adopted [ADR-017](017-versioned-keyed-idempotency-digests.md):
new rows use versioned HMAC-SHA256, while retained SHA rows remain replayable until
physical pruning. The remainder of this ADR records the unchanged logical command
and response protocol; ADR-017 owns digest representation, locking and rotation.
Operations are constrained to place_bid / set_maximum_bid. The same key under a
different actor or operation is independent. Same actor/operation but another
auction or payload conflicts. Guarantees assume standard cryptographic collision
resistance; never deduplicate by equal bidder/amount values.

At Phase 5 the actor was a supplied user ID and was **not an authentication
boundary**. Phase 20 [ADR-016](016-first-party-identity-and-sessions.md) now derives
the same actor ID from a live authenticated session before key ownership; it
does not reinterpret retained rows. The actor foreign key preserves identity
while records are retained. Do not read Auction before resolving the command key.

## Fingerprinting

SHA-256 of a deterministic JSON object in this fixed order: api_version="v1",
operation, integer auction_id, integer actor_id, arguments (sorted by field name).
Arguments contain amount or maximum_amount with its parsed JSON scalar type intact.
Input object ordering, whitespace and unrelated headers do not participate. Integer
and string/float money inputs differ; only integers pass money validation. Missing
amount and explicit null normalize to the same invalid semantic input. The key
is not part of the fingerprint because it already selects the scoped record.

Only the digest is persisted; no raw request or private ceiling is stored in the
idempotency table. Fingerprints are not encrypted payloads or protection against
an operator with plaintext database access. Canonicalization is a compatibility
contract: changing it requires a plan for retained records.

## Ownership, lock ordering and atomicity

Idempotency::Executor owns one outer transaction (requires_new savepoint if nested):

```text
BEGIN
INSERT idempotency_record ON CONFLICT DO NOTHING RETURNING id
  ownership first; UNIQUE coordinates competing sessions
  existing matching completed -> return stored outcome
  existing mismatched fingerprint -> 409, no domain execution
  newly inserted processing row -> invoke bidding operation
    lock/reload Auction
    capture post-lock PostgreSQL clock_timestamp()
    validate and settle private/public bids and soft close
    RELEASE domain savepoint
  store terminal status/public JSON; mark completed
COMMIT mutation + terminal record together
```

Auction's existing requires_new transactions become savepoints, never independent
commits. Expected domain errors roll their savepoint back before the outer wrapper
stores the rejection. Snapshot persistence failure rolls back the outer transaction,
including released domain savepoints and ownership. A waiting conflicting INSERT
then either sees the owner's committed terminal record or becomes owner after its
rollback. No committed processing row is produced by the normal path. Unexpected
committed processing state raises instead of guessing or implementing leases.

The only lock order is idempotency ownership then auction row. A completed replay
never loads/locks Auction, calls its deadline clock, recalculates prices or resolves
proxies. It remains valid while another session holds that auction locked, even
when the auction is closed. The internal closer uses only its existing auction
protocol; it neither requires nor creates client idempotency records.

## Response replay and conflicts

Store HTTP status and the exact safe public JSON body from BidPresenter or the
amount-free maximum acknowledgement; never a model attribute dump. Original and
replayed responses both use the JSONB-normalized saved snapshot, preserving response
bytes as well as IDs, sequence, timestamps and error details. These endpoints do not
emit a Location header or other required logical headers. Date/request IDs/etc. are
transport metadata, not persisted. Replays add Idempotency-Replayed: true; originals
omit the marker. Replay is historical command outcome, not a current auction GET.

Matching terminal outcomes replay before current auction checks, including after
price/leader changes, deadline or closure. Same scope with a different fingerprint
returns 409 idempotency_key_conflict with no previous payload, and never mutates the
original record or Auction. A new key with an identical maximum is a new logical
command that may be a domain no-op; the old key is a replay, not another evaluation.

## Failure policy

Persist terminal 200/201 success, DomainError 422, RecordInvalid 422 and
RecordNotFound 404 reached inside execution (notably missing Auction). Persist
original public details for later rejection replay, even when the current minimum
has changed. Schema constraints allow only these terminal statuses, never 500.
Missing/invalid key, malformed request shape/ID/JSON and missing actor occur before
ownership and are not retained. A conflicting request is 409 against the existing
record, not a new stored outcome. Database/connection errors, unexpected exceptions
and snapshot write failures propagate and roll back ownership plus mutation;
the key can be retried. No broad exception-to-cached-500 rescue exists.

## Retention and pruning

Default retention is seven days from the claim transaction's DB start timestamp,
configurable with IDEMPOTENCY_RETENTION_DAYS (1..365). expires_at is prune eligibility,
not automatic logical invalidation. CURRENT_TIMESTAMP is appropriate for this
conservative retention calculation, **not** for post-wait auction eligibility.
Record present: key reserved, even after expiry. Physically pruned: key can become
a new command. The guarantee lasts while the record is retained, not indefinitely.

bin/rails idempotency:prune deletes one bounded batch (default 1000, maximum 10000,
IDEMPOTENCY_PRUNE_BATCH_SIZE), using PostgreSQL time, completed status, expiry order
and FOR UPDATE SKIP LOCKED. A partial completed (expires_at,id) index supports this
operation. Automatic scheduling is future operations work; no Sidekiq was added.
If pruning deletes an expired conflicting row between INSERT and SELECT, execution
retries ownership acquisition; physical removal is exactly the reuse boundary.
Do not lower retention blindly: clients may still retry old keys after pruning.

The additive migration preserves existing domain tables. Rollback refuses to drop
retained outcomes, since that would silently invalidate replay guarantees. Preserve
or deliberately expire/prune records before a planned downgrade.

## Privacy

Public snapshots contain only already-public representations. Maximum acknowledgments
never include ceilings/priority/origin. Stored request identity is digest-only.
Full raw keys and request bodies are never added to application logs. Rails filters
private maximum inputs and idempotency digest/snapshot attributes; conflict-safe
bulk SQL may show hashes, never the raw key/ceiling. This is not a new authorization
system or protection against impersonating a supplied actor ID.

## Alternatives considered

- Unprotected retries: response loss can repeat effects or change an outcome.
- Search equal bid values: confuses legitimate independent commands with retries.
- Redis idempotency: cannot atomically commit with this PostgreSQL auction state.
- Process-local cache/mutex: cannot coordinate separate Rails instances or restarts.
- Commit processing before mutation: creates orphan ownership and recovery leases.
- Write terminal record after mutation commit: crash gap permits duplicate mutation.
- Lock/evaluate auction before resolving key: rejects historical successes after
  closure and makes completed retries contend with unrelated current commands.
- Server-generated-only keys: the client cannot reuse a key lost with the response.

## Consequences and revisit when

One extra indexed row and a small response snapshot are retained per logical command;
claim, read, final write and normalized snapshot read add work to the transaction.
After domain savepoint release, the auction lock remains held until the wrapper's
outer commit. No network I/O/sleep is performed in production transactions. No
throughput or latency improvement is claimed. Hot auctions and duplicate-key waits
can consume connections. Retention needs operational ownership and storage planning.
Same-database atomicity is the benefit, not a new service or command bus.

Revisit scope when authentication changes identity; strategy for multi-region writes
or a future command authority; retention when volume becomes meaningful; and stored
response/version compatibility before changing endpoint contracts. Phase 6 frontend
must reuse keys for retries and generate new keys for new user intentions.
