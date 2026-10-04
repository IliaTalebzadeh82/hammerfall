# ADR-019 — Hidden reserve as auction state

Status: Design selected in Phase 21 Session 1; implementation and combined tests pending.

## Context and public behavior

Catawiki [describes a hidden minimum sale price](https://www.catawiki.com/en/help/reserve-prices/i-d-like-to-place-a-bid-on-an-object-with-a-reserve-price-what-does-this-mean-and-how-do-i-know-what-the-reserve-price-is). It accepts manual bids below reserve, shows them in history, and tells the bidder when reserve is unmet. An initial maximum below reserve is fully placed; one above reserve first matches the reserve. An unmet reserve means [the object does not sell](https://www.catawiki.com/en/help/estimates-and-reserve-prices/can-i-set-a-minimum-selling-price-reserve-price). Catawiki also [allows qualified lowering/removal](https://www.catawiki.com/en/help/during-auction-changes-to-removal-of-lots/can-i-edit-my-reserve-price) during an auction. These are public product statements, not evidence of internal implementation.

Hammerfall's current SQL and model rule requires a closed auction's `winner_id` to equal `current_leader_id`. That is wrong for an unmet reserve: the highest bidder is visible, but no sale winner exists. Existing public snapshots have no reserve status.

## Hammerfall decision and invariants

Add nullable private integer-cent `reserve_price` to Auction, configurable by the authenticated seller on draft create/edit and frozen when scheduled. Null means no reserve. Existing rows remain null. Do not introduce estimates, expert review, auction-time reserve editing, post-auction offers or payments. The fixed-after-scheduling choice deliberately differs from Catawiki's public rule.

- Keep reserve amount out of public serializers, domain payloads, Kafka, Redis, Cable, errors, logs, metrics and bid history metadata. A visible proxy bid may equal the reserve because that price action is an intended public effect of the chosen rule; it does not authorize a raw reserve field.
- Expose public reserve status as `none`, `not_met`, or `met`. With a reserve, `met` requires an accepted visible bid at/above the private amount. First bid and subsequent changes derive status from PostgreSQL while holding the auction lock; public revision and outbox must change together. The amount remains private even to the seller through ordinary public GET.
- A manual bid below reserve is valid if it meets the normal authoritative minimum. A new maximum below reserve bids its entire ceiling; one at/above reserve bids at least the reserve without exceeding its ceiling. A leader who adds/increases a maximum while reserve is unmet advances its visible bid to the lesser of its ceiling and reserve. Competing maxima use the existing durable ceiling/priority resolver, then apply the reserve floor to the winner where its authorization permits it. Every generated price remains monotonic and at/below its owner's ceiling.
- Closing copies `current_leader_id` to `winner_id` only if there is an accepted bid and no reserve or the reserve is met. Otherwise it closes with no winner and retains the current leader as the historical highest bidder. Adjust model, SQL and snapshot validation accordingly. Duplicate closure remains a no-op. Bidder, maximum, reserve status, public event and deadline updates share the auction transaction.

Representative no-competition results for reserve €500/start €100: manual €200 → €200, not met; max €400 → €400, not met; max €700 → €500, met. Competing maxima A €700 then B €600 settle A at €650 using the €501–1,000 step, met. These are Hammerfall design examples to prove, not claims about Catawiki's hidden implementation.

## Alternatives

- Expose the reserve number: defeats the hidden product rule.
- Assign winner then cancel an unmet sale: creates an authoritative false win and difficult compensation.
- Reject all below-reserve bids: contradicts the documented visible bid history.
- Permit live reserve edits: creates seller-versus-bid races and a policy for a lowered threshold, outside this first selected slice. Revisit with a separately reviewed lock and event protocol.

## Consequences, risks and revisit condition

This changes an SQL winner invariant, public API and async snapshot schema; all consumers and reconciliation must evolve deliberately. Do not deploy a writer before schema/reader compatibility is established. A new public status can reveal that a known bid crossed the hidden threshold, which is allowed by the selected public approximation; no raw number is emitted. The implementation must test contention, ties, partial increments, retries, unsold close and privacy across every representation. Revisit when implementing live reserve edits or seller-only private inspection.
