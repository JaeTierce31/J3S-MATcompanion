# PSI-CIM-001G-R1 Certification Receipt

**Artifact:** PSI-CIM-001G — Adaptive Insight Orchestration & Retention Loop  
**Policy version:** `001G-R1`  
**Repository:** `JaeTierce31/J3S-MATcompanion`  
**Source branch:** `psi-cim-001g-implementation`  
**Verdict:** **CONDITIONAL PASS**

## Verified

The following were executed against disposable PostgreSQL 17 / Neon branches derived from the verified PSI-CIM runtime baseline:

- orchestration policy contract;
- meaningful-change/materiality oracle;
- semantic fingerprinting and exact-one redundancy classification;
- deterministic eligibility and delivery cooldowns;
- hard T0–T3 priority tiers;
- bounded adaptive adjustment with the initial `[-0.15,+0.15]` envelope;
- single-session attention-budget behavior;
- explicit + bounded behavioral usefulness learning;
- rejection of dwell-time and other engagement-volume ranking signals;
- smallest-sufficient-next-action selection;
- one-primary-action constraint;
- action-closure prerequisites and closure-triggered learning;
- reconstruction of suppression, ranking, action, supersession, and preference lineage;
- dashboard direct-access denial with governed orchestration APIs;
- degraded adaptive fallback to deterministic tiering + neutral preference;
- forged mutable `app.user_id` substitution rejection;
- **20/20 constitutional invariants PASS**;
- end-to-end synthetic orchestration fixture PASS;
- clean 001G apply over a fresh child of the verified 001F runtime baseline PASS;
- second full 001G replay over that baseline PASS.

Implementation test branch: `br-calm-glitter-b8wnjuel`  
Replay-cert branch: `br-snowy-sea-b8clvdpn`

## Constitutional boundary proven by the tests

Usefulness learning modifies delivery preference only. It does not grant eligibility, increase scientific certainty, reduce safety severity, change authority class, or auto-execute reserved actions. Critical/high safety retains lexical precedence over mute, cooldown, personalization, and attention-budget optimization.

## Open certification gates

### 1. True two-independent-connection delivery contention — UNVERIFIED

A race-free executable harness is committed at:

`tests/concurrency/001g_delivery_budget_atomic.sh`

It starts two independent `psql` processes and requires exactly one `DELIVER_NOW`, one `BLOCKED`, and exactly one active T1 primary item. The harness has **not** been executed in this chat harness, so this receipt does not claim the contention gate as PASS.

### 2. Repository clean-from-zero migration — BLOCKED

The repository does not currently contain the canonical historical PSI-CIM-001D through 001F migration lineage. Therefore the verified replay scope is:

> verified 001F runtime baseline → apply 001G → full second 001G replay

It is **not** a claim that the current repository can construct the complete PSI database from an empty PostgreSQL database.

### 3. Production valid-JWT end-to-end — OPEN inherited gate

001G verifies that mutable client context such as forged `app.user_id` cannot substitute for verified auth context. A complete production valid-interactive-JWT path was not re-certified in this work and remains an inherited runtime gate.

### 4. Immutable final source SHA — OPEN until freeze

The feature branch is intentionally still moving while certification artifacts are being written. The exact immutable source SHA must be captured after the final certification commit or CI run before promotion to full PASS.

## Reproduction entrypoints

On a disposable PostgreSQL 17 database carrying the verified 001D–001F runtime baseline:

```bash
bash scripts/replay_001g.sh
bash scripts/verify_001g.sh
```

`replay_001g.sh` applies all `001G_*` migrations twice and checks replay postconditions. `verify_001g.sh` runs component suites, 20 invariants, E2E, auth regression, and the two-process contention harness.

## Promotion rule

Do **not** promote `PSI-CIM-001G-R1` from CONDITIONAL PASS to full PASS until:

1. `tests/concurrency/001g_delivery_budget_atomic.sh` executes successfully against a disposable migrated runtime;
2. the exact immutable Git commit SHA is recorded in the machine-readable receipt;
3. for a clean-from-zero repository certification specifically, canonical 001D–001F migration lineage is added or formally reconciled.

No production deployment or merge is authorized by this receipt.
