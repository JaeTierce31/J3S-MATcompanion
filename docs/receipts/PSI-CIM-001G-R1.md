# PSI-CIM-001G-R1 Certification Receipt

**Artifact:** PSI-CIM-001G — Adaptive Insight Orchestration & Retention Loop  
**Policy version:** `001G-R1`  
**Repository:** `JaeTierce31/J3S-MATcompanion`  
**Source branch:** `psi-cim-001g-implementation`  
**Certified source SHA:** `dcf1db097ded2aaf9200a053208f8366c5466e5b`  
**Verdict:** **PASS — PSI-CIM-001G subsystem**  
**Broader repository/product promotion:** **NOT implied by this PASS**

## Verified

The following were executed against PostgreSQL 17 and/or disposable Neon branches derived from the verified PSI-CIM runtime baseline:

- orchestration policy contract;
- meaningful-change/materiality oracle;
- semantic fingerprinting and exact-one redundancy classification;
- deterministic eligibility and delivery cooldowns;
- hard T0–T3 priority tiers;
- bounded adaptive adjustment with the initial `[-0.15,+0.15]` envelope;
- attention-budget behavior including a true two-independent-process T1 contention proof;
- append-only delivery-resolution lifecycle, including T1 budget release after resolution;
- automatic delivery resolution after a valid action outcome;
- delivery-resolution idempotency and immutable receipt history;
- explicit + bounded behavioral usefulness learning;
- rejection of dwell-time and other engagement-volume ranking signals;
- smallest-sufficient-next-action selection;
- one-primary-action constraint;
- action-closure prerequisites and closure-triggered learning;
- reconstruction of suppression, ranking, delivery resolution, action, supersession, and preference lineage;
- direct canonical table/view denial for the dashboard role;
- internal 001G function execution denial for the dashboard role / `PUBLIC` default surface;
- governed `api_orchestration_receipt(uuid)` and `api_orchestration_attention()` execution retained for the dashboard role;
- degraded adaptive fallback to deterministic tiering + neutral preference;
- forged mutable `app.user_id` substitution rejection;
- **20/20 constitutional invariants PASS after the delivery-resolution migration**;
- end-to-end synthetic orchestration fixture PASS;
- clean 001G apply over a fresh child of the verified 001F runtime baseline PASS;
- second full 001G replay over that baseline PASS;
- complete no-secret PostgreSQL 17 migration-chain replay PASS through `001G_013`.

Implementation test branch: `br-calm-glitter-b8wnjuel`  
Replay-cert branch: `br-snowy-sea-b8clvdpn`

## CI evidence

GitHub Actions workflow: **PSI-CIM-001G Concurrency Certification**  
Run: `38976335180`  
Job: `117226566872`  
Head SHA: `dcf1db097ded2aaf9200a053208f8366c5466e5b`  
Conclusion: **SUCCESS**

That run verified, in order:

1. minimal pre-001G dependency baseline creation;
2. complete actual `001G_*` migration chain application;
3. presence of the final delivery-resolution oracle/view;
4. true two-process T1 contention against the final delivery function;
5. append-only delivery-resolution lifecycle;
6. first-pass migration contract;
7. complete second `001G_*` replay;
8. second replay contract.

The standalone **PSI-CIM-001G Policy Smoke** workflow is intentionally only a policy-contract smoke test and is not treated as full subsystem certification.

## Constitutional boundary proven

Usefulness learning modifies delivery preference only. It does not grant eligibility, increase scientific certainty, reduce safety severity, change authority class, or auto-execute reserved actions. Critical/high safety retains lexical precedence over mute, cooldown, personalization, and attention-budget optimization.

Delivery and action history remain append-oriented. Resolving a decision-critical item creates a separate immutable delivery-resolution receipt; it does not rewrite the original delivery event.

The dashboard/Data-API role cannot invoke the internal orchestration mutation surface directly. User-facing access remains behind explicitly governed API functions.

## Remaining gates outside the 001G subsystem PASS

### 1. Repository clean-from-zero lineage — BLOCKED

The repository does not currently contain the canonical historical PSI-CIM-001D through 001F migration lineage. Therefore the strongest verified runtime replay scope remains:

> verified 001F runtime baseline → apply complete 001G chain → full second 001G replay

The local PostgreSQL 17 CI baseline intentionally contains only minimal pre-001G dependency shapes needed to exercise the actual 001G migrations. It is not evidence that this repository can reconstruct the complete PSI system from an empty database.

### 2. Production valid-interactive-JWT end-to-end — OPEN inherited gate

001G verifies that mutable client context such as forged `app.user_id` cannot substitute for verified auth context. A complete production valid-interactive-JWT admission path was not re-certified by 001G and remains an inherited runtime gate.

### 3. Merge / production deployment — NOT AUTHORIZED

This receipt certifies the 001G subsystem at the pinned source SHA. It does not itself authorize merge to `main`, production migration, production database mutation, or deployment.

## Reproduction entrypoints

On a disposable PostgreSQL 17 database carrying the verified 001D–001F runtime baseline:

```bash
bash scripts/replay_001g.sh
bash scripts/verify_001g.sh
```

`replay_001g.sh` applies all `001G_*` migrations twice and checks replay postconditions. `verify_001g.sh` runs component suites, delivery resolution, 20 invariants, E2E, authorization regression, and the two-process contention harness.

## Scope statement

**PASS means:** the PSI-CIM-001G orchestration subsystem at certified source SHA `dcf1db097ded2aaf9200a053208f8366c5466e5b` satisfies its current deterministic/adaptive control, audit, concurrency, resolution, and authorization gates on the tested PostgreSQL 17 / verified-runtime surfaces.

**PASS does not mean:** full repository-from-zero certification, full production auth admission, merge approval, or production deployment approval.
