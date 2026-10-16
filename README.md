# J3S-MATcompanion

Canonical implementation repository for MAT Companion / Personal Supplement Intelligence (PSI-CIM).

## Current implementation track

**PSI-CIM-001G — Adaptive Insight Orchestration & Retention Loop**

Control architecture:

```text
Deterministic eligibility
→ bounded adaptive ranking
→ smallest sufficient action
→ user outcome
→ bounded usefulness learning
```

Usefulness learning is intentionally subordinate to science, safety, and authority. It may change delivery preference within policy bounds; it may not make an ineligible insight eligible, increase scientific certainty, reduce safety severity, change authority class, or auto-execute reserved actions.

### 001G policy defaults

- priority tiers: `T0` safety, `T1` decision-critical, `T2` optimization/learning, `T3` informational;
- adaptive ranking envelope: `[-0.15, +0.15]`;
- behavioral preference decay: 45 days;
- active primary T1 budget: 1;
- visible T2 budget: 3;
- engagement-volume signals such as dwell time/session length are excluded from usefulness ranking.

## Source layout

- `db/migrations/001G_*.sql` — canonical 001G PostgreSQL migrations;
- `tests/sql/` — deterministic component, invariant, lifecycle, E2E, replay, and authorization tests;
- `tests/concurrency/` — independent-process contention harnesses;
- `docs/superpowers/specs/` — approved design specification;
- `docs/superpowers/plans/` — implementation plan;
- `docs/receipts/` — certification receipts;
- `scripts/replay_001g.sh` — apply/replay 001G over a verified 001D–001F runtime baseline;
- `scripts/verify_001g.sh` — canonical 001G verification entrypoint.

## Verification

Against a disposable PostgreSQL 17 database carrying the verified PSI-CIM 001D–001F runtime baseline:

```bash
bash scripts/replay_001g.sh
bash scripts/verify_001g.sh
```

The verifier includes policy, materiality, redundancy, eligibility/cooldown, ranking, attention budgets, usefulness learning, next-action selection, action closure, append-only delivery resolution, audit reconstruction, degraded mode, constitutional invariants, E2E orchestration, authorization regression, and independent-process delivery-budget contention.

### GitHub Actions

- **PSI-CIM-001G Policy Smoke** — standalone policy-contract smoke test only; it is not full runtime certification.
- **PSI-CIM-001G Concurrency Certification** — no-secret PostgreSQL 17 proof that applies the actual 001G migration chain and tests final-function contention, delivery resolution, and migration replay.
- **PSI-CIM-001G Runtime Certification** — manual workflow intended for a disposable verified runtime database via `PSI_RUNTIME_DATABASE_URL`.

## Certification boundary

The current R1 receipt is deliberately conservative. Full repository/product certification remains distinct from proving the 001G subsystem itself.

Known broader gates include:

1. the repository does not yet carry canonical historical 001D–001F migrations, so a true repository clean-from-zero build is not yet certified;
2. production valid-interactive-JWT end-to-end admission remains an inherited runtime gate;
3. no merge or production deployment is authorized solely by an 001G test receipt.

See `docs/receipts/PSI-CIM-001G-R1.md` for the current evidence boundary.
