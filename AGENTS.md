# Hammerfall repository instructions

## Context and scope

- Treat correctness and engineering depth as more important than
  reducing tokens. Load only the context relevant to the task; use
  [docs/context-map.md](docs/context-map.md) to route it.
- Start substantial phase work with
  [docs/handoffs/latest.md](docs/handoffs/latest.md), that phase's
  `docs/phases/phase-XX.md`, and the relevant architecture/ADR
  documents. The archived master prompt and chronological progress log
  are audit material, not routine startup context.
- Batch related repository inspection. Do not repeatedly reread
  unchanged files. Inspect implementation and tests before changing a
  claimed contract; distinguish intended future architecture from what
  exists.
- Do not start another roadmap phase without an explicit user request.
  Keep each phase working and its exclusions intact. Do not introduce a
  listed technology early merely because it is on the roadmap.
- For substantial work, create or update a concise
  `docs/plans/<topic>-execplan.md` with decisions, progress,
  verification and unresolved items. Remove stale execution detail from
  active plans when done.

## Engineering rules

- Rails owns auction business rules; PostgreSQL owns authoritative
  auction state. Next.js presents public state. Redis, Kafka, Sidekiq
  and WebSocket delivery cannot decide bid legality, price, deadline or
  winner. Preserve the current lock, time and idempotency protocols
  unless an explicit, reviewed architecture change replaces them with
  equivalent guarantees.
- Model the auction lifecycle and invariants explicitly. Keep client
  timestamps, browser countdowns, local memory and transport arrival
  order out of authoritative bid ordering or closing decisions. Keep
  private maximum, priority, origin, raw keys and secrets out of public
  representations and logs.
- Prefer one modular Rails application. Extract services only for
  demonstrated scaling, availability, lifecycle, workload, ownership or
  fault isolation needs; document a substantial change in an ADR before
  implementation. Keep controllers thin, transactions readable, business
  behavior easy to locate, and abstractions bounded. Avoid hidden
  callback workflows, service-object proliferation, generic
  repositories, premature dependency injection and clever
  metaprogramming.
- Use PostgreSQL transactions, locks, constraints and indexes
  deliberately. Assume multiple Rails instances. Document lock order and
  transaction ownership; do not rely on a Ruby mutex or a single
  scheduler for correctness. Use UTC internally and an explicit
  authoritative clock for deadlines.
- Respect client command identity: a retry of the same intention keeps
  its key and payload; replay is a historical outcome and a fresh GET
  supplies current state. Never infer a command result from a Cable
  notification.
- Protect input boundaries, authorization when introduced, secure
  configuration and private data. Do not commit credentials. Make
  expected errors deliberate; do not mask database or unexpected
  failures as success.

## Work and verification

- Choose a reasonable reversible engineering default and record it.
  Raise genuinely ambiguous product semantics or consequential
  irreversible choices for review; do not silently invent a guarantee.
- For a meaningful feature, add tests at the level that can prove the
  behavior. Concurrency, retry, proxy bidding, closure, event delivery
  and reconciliation need real integration evidence where feasible, not
  mostly mocked distributed behavior. Use real PostgreSQL and, once
  introduced, Redis/Kafka for relevant integration tests.
- Run focused checks during implementation and broad regression near
  completion. Verify Docker/local startup when phase scope calls for it.
  Do not rerun an expensive successful suite without a concrete reason.
  Avoid excessive polling of long-running commands.
- If a check fails, diagnose and repair it, then rerun relevant
  verification. Never delete a failing test or weaken an invariant just
  to obtain green CI. Never fabricate tests, performance data, benchmark
  results, scalability or operational claims; label unrun checks and
  unverified infrastructure.
- Perform a final adversarial review of correctness, concurrency,
  privacy/security, failure recovery, tests and changed documentation.
  Record material limits honestly.
- Update the canonical architecture/ADR, `docs/invariants.md`, API and
  operational documents when their contracts change. After substantial
  or phase work, rewrite `docs/handoffs/latest.md` as the compact
  current state; record phase completion and actual evidence in
  `docs/progress.md`. Maintain `docs/learning-guide.md`,
  `docs/code-map.md`, and the engineering journal for meaningful
  discoveries. Use coherent commits when appropriate.
- A phase is done only when implementation, tests, lint, relevant
  integration checks, documentation and local setup are verified, major
  decisions recorded, and no known serious correctness bug remains. Do
  not call a phase complete merely because code was written.

## Repository-specific references

- `apps/web/AGENTS.md` applies to frontend edits, including its
  requirement to consult installed Next.js docs for version-sensitive
  work.
- [docs/architecture/](docs/architecture/) contains durable domain
  boundaries; [docs/adr/](docs/adr/) records adopted choices. Current
  details and evidence live in
  [docs/handoffs/latest.md](docs/handoffs/latest.md) and
  `docs/progress.md` respectively.
- The original master prompt is preserved in
  `docs/archive/masterprompt-original.md` for audit only. Do not load it
  by default.
