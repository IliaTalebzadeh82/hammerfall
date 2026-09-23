# Consistency model

Phase 0 connects ActiveRecord to PostgreSQL and contains no domain state,
transactions spanning domain objects, cache, or projections.

The required direction is PostgreSQL authority for bids and lifecycle transitions.
Client clocks and process-local memory must not determine authoritative outcomes.
Locking, accepted-bid ordering, transaction boundaries, and consistency guarantees
will be specified and tested when the corresponding phases are implemented.
