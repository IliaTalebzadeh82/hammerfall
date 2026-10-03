# ADR-017 — Versioned keyed idempotency digests

Status: Adopted for Phase 20 Session 2 (2026-10-03)

## Context

ADR-006 stores SHA-256 of raw client keys. A stolen idempotency table permits offline guesses of low-entropy keys. Seven-day default replay actually lasts until physical pruning, and retained rows must keep replaying across a digest migration and key rotation. Multiple Rails processes may receive retries. PostgreSQL remains the command and auction authority.

## Decision

Store a 64-character HMAC-SHA256 digest for every new claim, with separate `digest_version=2` and `digest_key_id`. Existing rows become `digest_version=1`, `digest_key_id=NULL` and keep their SHA-256 digest. The unique `(actor_id, operation, key_digest)` index stays in place. Fingerprint, response snapshot, actor/operation scope and retention are unchanged.

The keyring JSON file has exactly `current` and `keys` fields. `current` names the write key; all listed keys are accepted for lookup. Each key is a unique 64-character lowercase hexadecimal value representing 32 bytes of secret material. Production boot fails without a readable, valid `IDEMPOTENCY_HMAC_KEYRING_FILE`; only development/test have an explicitly local fixed key. All Rails replicas must use the same file/version during a rollout. The GCP reference adds Secret Manager metadata and read-only CSI mount; it never puts payload in Terraform state.

For a command, authenticate the actor first, open the executor's PostgreSQL transaction, then take a transaction-scoped advisory lock on a transient 64-bit hash of actor, operation and raw key. This lock serializes different digest representations of the same logical command. After the lock, reject an incomplete keyring if any retained version-2 row names an unavailable key ID. Look up current HMAC, previous HMAC keys and legacy SHA-256 in order. A found row replays or conflicts normally. A miss inserts a version-2 claim with the current key, then executes the unchanged domain transaction. The lock order is advisory logical key, idempotency claim/row, then auction row. The transient lock hash and raw key are not stored or logged.

Rotation retains the old key as accepted while its rows exist. `expires_at` alone does not release a key; physically prune all rows bearing that key before removing it. Do not run old and new executor code concurrently during migration: the old code does not take the advisory lock and cannot look up HMAC rows. Drain old API requests, migrate, distribute one keyring, then start all new replicas. During later key rotation all replicas must receive the same current/previous set before new writes; a stale replica fails when it sees a retained unknown key ID, but an in-flight configuration mismatch is not an availability guarantee. Different material under the same key ID is not detected across replicas and could miss a retained retry. Release operations must verify byte-identical keyring content before enabling new writes.

## Alternatives and consequences

Unversioned HMAC and eager conversion of retained rows were rejected because they obscure replay/rotation or create a concurrency migration risk. Permanent dual writes add unnecessary states. A separate stable scope digest would require a second long-lived secret and index; the advisory lock plus existing unique index is smaller for this workload. Redis cannot coordinate the transaction with PostgreSQL. The extra lock and key-ID validation query add DB work; this is a correctness/security choice, not a performance claim. The migration refuses down after keyed rows exist. The algorithm/secret version fields and unchanged 64-character digest width preserve current index shape. Production key distribution, retention pruning and synchronized rollout are operational requirements, and no cloud secret version has been created.
