# ADR-018 — Per-auction stepped bid increments

Status: Adopted for the Phase 21 increment slice, 2026-10-04.

## Context and public behavior

Catawiki's [published minimum-bid table](https://www.catawiki.com/en/help/bidding-basics/how-is-the-next-minimum-bid-calculated) chooses a euro increment from the current highest bid and says maximum bids use the same increments. It cautions that experiments may cause some lots to differ. Its [maximum-bid help](https://www.catawiki.com/en/help/max-bids/what-is-a-max-bid-and-how-does-it-work) describes smallest possible counters, an earlier maximum winning equal-ceiling ties, private unused ceilings, and an exception that permits a final offer below the normal next increment if the ceiling is too low. These are observable rules; Catawiki's code, transactions and data model are unknown.

Hammerfall previously stored one fixed `minimum_increment` per auction. Manual bids were checked after taking the auction row lock, and `ProxyResolver` used the same fixed increment after either loser's ceiling. Changing the amount only in the frontend or presenter would make accepted bids and proxy rows inconsistent.

## Decision

Add an immutable-after-draft `increment_policy` with `fixed` and `stepped`. Existing auctions and new auctions without an explicit choice remain `fixed`. `stepped` uses the published euro table in integer cents. The inclusive upper boundary determines the increment; values between whole euro boundaries take the next higher band. Values under €1 use the first band as a Hammerfall extension. The final band applies above €500,000. The source article is a snapshot, not a permanent Catawiki promise.

For a manual offer, the locked, current visible price chooses the band; the first bid still needs only the starting price. The winner's smallest automatic counter uses the band at the **loser's newly visible amount**, capped by the winning private ceiling. The existing final partial-ceiling and equal-ceiling priority rules survive. One logical contest and all its rows still commit under the same auction lock. `minimum_increment` remains the persisted fixed-policy amount; for `stepped`, it is a compatibility input with no pricing effect. Public API, outbox and projections report the **effective increment at the current visible price** in that existing field. The caller uses current price plus this field to display the expected next manual minimum after the first bid; the server recalculates under lock. No public snapshot field or event schema version is added.

The policy value itself is an auction configuration input accepted only on create or draft edit; it is not exposed as a public snapshot field. Public participants see the effective increment and fresh rejection minimum. `public_revision` changes on an authorized draft policy edit, even if the current effective increment happens to stay the same. This lets clients refresh before the next boundary.

## Alternatives

- Replace every auction's fixed value with stepped rules: silently changes historical auctions and invalidates retained expectations.
- Calculate bands in the browser: races with concurrent bids and leaves stale commands incorrectly accepted.
- Emit a new v2 public event schema containing the policy name and next minimum: adds consumer rollout work without an invariant gain for this slice. Revisit if a UI needs to explain a policy by name.
- Step through every intermediate proxy amount: adds rows and changes the at-most-two-row settled contest protocol without improving the final price or priority.

## Consequences, risks and revisit condition

The server, outbox and PostgreSQL presenter use one `BidIncrementPolicy` implementation. Existing fixed rows retain their exact values. A downgrade that sees stepped rows raises an irreversible-migration error rather than discard policy state. A mixed-version application rollout must migrate before new code and drain old bid writers before enabling stepped auctions; old code would otherwise price them as fixed. Public `minimum_increment` now means the current effective increment, while the stored column remains fixed-policy input. Redis may show an older revision until propagation/reconciliation; it never authorizes a bid.

Focused model, API, idempotency and independent PostgreSQL connection races demonstrate the new rule. Live multi-instance/Redis/Kafka and full regression evidence are later Phase 21 work, not claims of this ADR. Revisit this design if the published schedule changes, per-lot experiments are adopted, currency support expands, or observed scale justifies a different resolver transaction.
