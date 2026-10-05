# Phase 22 — Durability, Release & Operations

Status: In progress — Session 1 durability and release milestone verified;
operating policy and game day remain for Session 2.

## Goal

Demonstrate reasoned backup, restore, deployment, migration, rollback, incident and recovery behavior. Keep this a bounded learning and case-study phase, not a multi-phase infrastructure program or a claim of production operation.

## Durability and release

- Define backup strategy, PITR, restore procedure and evidence-based RPO/RTO. Restore PostgreSQL authority, rebuild disposable Redis projections, and explain Kafka/outbox recovery and secret/config recovery. A configured backup alone is not restore proof; run a realistic local restore exercise where feasible.
- Document schema/application compatibility, migration sequencing, expand/contract where needed, rolling deploys, image promotion, rollback and failed-deployment handling. Check background worker and Kafka schema compatibility across versions. A paid cloud deployment is not required to demonstrate the reasoning.

## Operating policy and game day

Turn existing observability into justified SLIs/SLOs, alerts, ownership, incident classification and runbooks. Cover backlog/lag, DB saturation, auction failure indicators, Redis/Kafka degradation and reconciliation drift. Avoid arbitrary SLO targets without evidence. Define the smallest secured operator behavior or interface needed to inspect auction/bid/reconciliation/failure/degraded state and perform authorized recovery; use Phase 20 roles rather than exposing privileged operations publicly.

Run one integrated production-style game day: failure or deployment event → observable symptom → alert → operator diagnosis → runbook action → recovery → reconciliation → proof that authoritative auction state remains correct. Combine existing systems rather than adding infrastructure for its own sake. Record actual observations, gaps and limits.

## Verification and boundary

Verify restore, compatibility and operational claims with realistic local/integration evidence where feasible. Update runbooks, production readiness, progress and handoff. Do not start Phase 23 without an explicit request.
