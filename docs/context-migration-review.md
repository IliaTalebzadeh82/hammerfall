# Context migration: human review

The following original requirements are preserved but lack a safe roadmap assignment. They are **not** blockers for this documentation migration. Do not silently drop them or implement them in Phase 8 merely because they are listed here.

| Original reference | Why review is needed | Conflicting/current source | Recommended resolution |
|---|---|---|---|
| Section 1, “Administrators/operators should have a minimal operational interface” for auction/bid/reconciliation/failure/degraded state inspection | The 21-phase roadmap never assigns an operator UI; reconciliation and observability do not arrive until Phases 12–13. “Interface” could mean a browser UI, an internal API or runbooks. | Current repository has unauthenticated lifecycle APIs, no operator identity or console; `docs/production-readiness.md` calls out absent operational runbooks. | Before adding an operator surface, choose the smallest secured interface and phase after authentication/authorization and relevant telemetry exist; retain the requirement in `docs/architecture/system-boundaries.md`. |
| Section 31, authentication and authorization; section 32, rate limiting | These are explicit future protections but no phase schedules them. Phase 1–7 deliberately use demo actor IDs; an unauthenticated operator/bidder API cannot be publicly deployed. | `docs/security.md`, `docs/production-readiness.md`, ADR-004/006/007 and latest handoff state the current limit. | Assign security work before public or real-money exposure. Decide identity, ownership, lifecycle privileges and failure policy; preserve current explicit demo label until then. |
| Section 46, lightweight feature/experiment framework, stable bucketing and bidding-panel example | The roadmap has no experimentation phase. Event names include auction outcomes that could leak identity or imply analytics storage without a privacy model. | Current UI has no analytics/experiment infrastructure; Phase 13 observability is operational rather than product experimentation. | Decide whether to include this in Phase 20 or a separately requested phase, and define privacy/retention before recording exposure or outcomes. Requirement remains in `docs/architecture/operations-and-security.md`. |

## Resolved discrepancies (no decision needed now)

- Section 11's final-30/+30 soft-close numbers are an illustrative policy. The adopted Phase 4 contract is final-60/+90 in ADR-005, code and tests.
- Sections 8/10 suggested unnumbered ADR filenames; the repository uses ADR-003 and ADR-005. These documents are the adopted choices.
- Section 5 names `AutomaticBid`; the implemented model is `MaximumBid`. ADR-004 explicitly chose binding increases and no cancellation. This resolves section 9's “if supported” branch.
- Section 6 lists eventual event delivery, duplicate-safe consumers and repairable read models among system invariants; those are Phase 9–12 obligations, not current Phase 7 capabilities.
- Section 64 says to continue automatically after each phase. The current progress/handoff records explicit stop after Phase 7, and this user's migration request forbids feature implementation. This old execution instruction is obsolete.
