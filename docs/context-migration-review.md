# Context migration: human review

The following original requirements were preserved without a phase in the original 0–20 roadmap. After Phase 19, the roadmap extension assigned them to Phases 20–22. The earlier lack of assignment remains part of the migration history; none is implemented by this documentation update.

| Original reference | Why review is needed | Conflicting/current source | Recommended resolution |
|---|---|---|---|
| Section 1, “Administrators/operators should have a minimal operational interface” for auction/bid/reconciliation/failure/degraded state inspection | The original 21-phase roadmap did not assign an operator UI. “Interface” could mean a browser UI, internal API or runbooks. | Current repository has unauthenticated lifecycle APIs, no operator identity or console. | Resolved after Phase 19: Phase 20 assigns privileged identity/capabilities; Phase 22 selects the smallest secured operator behavior/interface and operating policy. |
| Section 31, authentication and authorization; section 32, rate limiting | Originally explicit future protections with no phase; Phase 1–7 used demo actor IDs. | `docs/security.md`, `docs/production-readiness.md`, ADR-004/006/007 and latest handoff state the current limit. | Resolved after Phase 19: assigned to Phase 20 — Identity & Security, before public exposure. |
| Section 46, lightweight feature/experiment framework, stable bucketing and bidding-panel example | The original roadmap had no experimentation phase. Outcome events need privacy and retention decisions. | Current UI has no product analytics/experiment infrastructure; Phase 13 telemetry is operational. | Resolved after Phase 19: Phase 21 owns a reasoned go/no-go decision and any justified bounded experiment with privacy/retention rules. This is not automatic implementation. |

## Resolved discrepancies (no decision needed now)

- Section 11's final-30/+30 soft-close numbers are an illustrative policy. The adopted Phase 4 contract is final-60/+90 in ADR-005, code and tests.
- Sections 8/10 suggested unnumbered ADR filenames; the repository uses ADR-003 and ADR-005. These documents are the adopted choices.
- Section 5 names `AutomaticBid`; the implemented model is `MaximumBid`. ADR-004 explicitly chose binding increases and no cancellation. This resolves section 9's “if supported” branch.
- Section 6 lists eventual event delivery, duplicate-safe consumers and repairable read models among system invariants; those are Phase 9–12 obligations, not current Phase 7 capabilities.
- Section 64 says to continue automatically after each phase. The current progress/handoff records explicit stop after Phase 7, and this user's migration request forbids feature implementation. This old execution instruction is obsolete.
