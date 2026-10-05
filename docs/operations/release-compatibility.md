# Release compatibility policy

This is the canonical Hammerfall deployment compatibility record. Check the
exact old and new image SHAs, migration versions, feature data, event envelopes
and long-lived workers before each release. A migration having a `down` method
does not establish a safe rollback. [ADR-018](../adr/018-stepped-bid-increments.md),
[ADR-019](../adr/019-hidden-reserve-policy.md),
[ADR-020](../adr/020-auction-closing-policies.md) and
[ADR-017](../adr/017-versioned-keyed-idempotency-digests.md) own the current
policy/digest contracts.

## Migration classes

| Migration / transition | Class | Required release handling |
| --- | --- | --- |
| Core domain creation | MAINTENANCE ONLY | Initial bootstrap; no old app compatibility claim. |
| Bid `sequence` backfill, NOT NULL and unique index | REQUIRES DRAIN | Access-exclusive locks and old writers lack sequence. Stop writers first. |
| Maximum bidding / origin backfill | REQUIRES DRAIN; IRREVERSIBLE WITH DATA | Lock/backfill; private commitments cannot be discarded by rollback. |
| Deadline/closure history | REQUIRES DRAIN; IRREVERSIBLE WITH DATA | Lock/backfill; preserve original deadlines and closed history. |
| Idempotency table | EXPAND/CONTRACT; IRREVERSIBLE WITH DATA | Old commands must drain before idempotent entry points replace them; retained outcomes block down. |
| Public revision | EXPAND/CONTRACT; IRREVERSIBLE WITH DATA | Old writers cannot maintain revision/outbox contract; down blocked once revisions exist. |
| Outbox, Kafka columns/receipts, projection leases | EXPAND/CONTRACT | Start compatible publishers/consumers after schema and writer protocol; retained events/receipts must survive. Kafka migration marks pre-domain rows acknowledged because historical snapshots do not exist. |
| Trace context, receipt digest, event integrity/window constraints | ROLLING SAFE only after data validation | Additive metadata/default or strengthened constraints; check actual rows and lock duration before rollout. |
| Identity/ownership/sessions | EXPAND/CONTRACT; REQUIRES DRAIN for auth cutover | Existing actors can be read, but old public write/auth behavior must not coexist with secured new ingress. |
| Versioned HMAC digests | REQUIRES DRAIN; IRREVERSIBLE WITH DATA | Old executor lacks advisory lock and HMAC lookup. Distribute identical keyring, stop old API, migrate, start new. |
| Stepped increment column/default | EXPAND/CONTRACT; REQUIRES DRAIN before stepped writes | Old writers price stepped rows as fixed; down blocked by stepped rows. |
| Reserve column, winner constraint and v2 outbox allowance | EXPAND/CONTRACT; REQUIRES DRAIN before reserve/v2 writes | Deploy v2 readers first; old closer/writer semantics are unsafe. Down blocked by reserve or v2 events. |
| Rapid closing column/default | EXPAND/CONTRACT; REQUIRES DRAIN before rapid writes | Old closer/bid writer uses regular deadline rules; down blocked by rapid rows or closing-policy events. |

`ROLLING SAFE` above is conditional on existing rows satisfying the new check and
on a measured lock budget; it is not a blanket zero-downtime promise. More
granular migrations are listed in `apps/api/db/migrate/`.

## Observed and supported combinations

| Schema/data | Phase 20 app/worker | Phase 21 app/worker | Decision |
| --- | --- | --- | --- |
| Phase 20 schema/data | Yes | No: Phase 21 code expects new columns/constraints | Keep old app until expansion. |
| Expanded Phase 21 schema, only fixed/regular/no-reserve rows and v1 events | A fixed regular write was exercised and new app read it | Yes | A narrow transition window, subject to HMAC/auth compatibility and worker drain. |
| Expanded schema with stepped rows | No: old writer accepted a bid current code rejects | Yes | Drain old writers before enabling stepped. |
| Reserve rows or emitted v2 events | No: old winner rule and exact v1 readers conflict | Yes; v1 retained events normalized | Upgrade readers before v2 writer activation. |
| Rapid rows or closing-policy events | No: old deadline logic and reader shape conflict | Yes | Drain old bid/closer workers. |
| Contracted schema after a future removal | No guarantee | Requires a reviewed contract migration | Never auto-rollback schema. |

The Phase 20→21 live drill used `6c38b59` in a detached worktree and a
disposable database. Old code wrote a fixed auction on new schema; current code
read it. At 35,000 cents on a stepped auction, old code accepted 36,000 in an
outer transaction rolled back for safety; new code rejected it with a 37,000
minimum. `db:rollback STEP=1` on rapid data raised and left schema intact.
See [Session 1 evidence](phase-22-session-1.md).

## Workers and event versions

| Role | Overlap rule |
| --- | --- |
| API bid/maximum writers and closer | Drain before new policy rows. Old code can make wrong legality/price/deadline/winner decisions. |
| Outbox publisher and Sidekiq notification job | Stable IDs/revision hints tolerate duplicates; old publisher forwards stored envelopes, but drain with the coordinated release to avoid mixed workers and ambiguous retries. |
| Kafka publisher | Forwards stored event envelope and can duplicate after ambiguity. Drain at boundary; do not assume simultaneous replica restart. |
| Kafka audit/projection consumers | Phase 20 codecs accept only v1; must deploy current v1/v2 readers and restart long-lived processes before v2 writers. New readers accept retained v1 and early v2. |
| Redis projection and reconciliation | Old projection uses v1 key/shape; current uses v2 with historical normalization. Stop old workers, rebuild v2 from PostgreSQL, then resume new consumers/scans. |
| Reconciliation scheduler/Sidekiq maintenance | PostgreSQL lease prevents unbounded scheduled chains, not version compatibility. Drain old jobs or let bounded retries settle under a reviewed version; verify queue/lease state. |

For a compatible future release, expand schema, deploy compatible readers,
drain old writers, then activate new writers/features. Contract in a later
release after old images, jobs and retained messages are gone. Phase 20→21
policy enablement is a coordinated drained release, not a rolling write rollout.
The new code's v1 reader compatibility does not make old v1 readers compatible
with v2.

## Rollback and artifact identity

Build and test one immutable image per service; promote its exact digest rather
than rebuilding for each environment. Record Git SHA, API/web image digests,
schema migration versions, supported Kafka snapshot versions, keyring/config
version IDs and deployment time in the release record. The GKE reference
requires digest images but no registry promotion pipeline is implemented.

If migration succeeds and the new app fails readiness **before** policy data
or v2 events are written, retain the expanded schema and roll back to the old
image only after confirming the matrix's narrow safe state. If new policy rows
or v2 events exist, keep old writers stopped and deploy a compatible forward
fix/current image. Do not run `db:rollback` automatically or erase auction
data to make an old image boot. A destructive downgrade needs its own data
migration, backup and recovery review. Maintain PostgreSQL backup/PITR and
secret recovery readiness before any such deployment.
