# PSI-CIM-001G Adaptive Insight Orchestration & Retention Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a governed orchestration subsystem that deterministically decides whether PSI insight candidates are eligible, applies bounded adaptive ranking, selects the smallest sufficient next action, captures usefulness feedback without mutating scientific/safety truth, and emits auditable receipts for every decision.

**Architecture:** Add a PostgreSQL-first orchestration layer over the existing PSI-CIM 001D–001F data/decision plane. Keep materiality, eligibility, priority, usefulness learning, delivery budgeting, and action selection as separate independently testable modules, with SQL functions and immutable receipt tables as the canonical runtime contract. Expose only governed API functions to the dashboard role and enforce 001G invariants in CI.

**Tech Stack:** PostgreSQL 17, SQL/PLpgSQL, Neon, GitHub Actions, shell/psql CI, existing PSI-CIM canonical schema and auth functions.

**Spec:** `docs/superpowers/specs/2026-10-16-psi-cim-001g-adaptive-insight-orchestration-retention-loop-design.md`

## Global Constraints

- Learning cannot make an ineligible insight eligible.
- Preference data cannot change scientific certainty, safety severity, or authority class.
- Critical safety bypasses cooldown and cannot be permanently muted.
- Exact duplicates never create a new active insight; contradictions are never suppressed as duplicates.
- Cooldown applies to delivery only, never analysis.
- Adaptive ranking is bounded to the configured policy envelope and cannot cross hard tiers unless explicit policy permits it.
- Dwell time, session length, notification-open rate, scroll depth, screens/session, DAU/MAU, and total time in app must have zero ranking effect.
- One insight has at most one primary next action.
- `NO_ACTION` is valid.
- Reserved actions never auto-execute.
- Learning is captured only from observable user response or completed state change.
- Every materiality, suppression, ranking, delivery, action, and preference update decision must be reconstructable from versioned receipts.
- Preserve existing 001D–001F auth/read-model boundaries: dashboard role gets governed API execution, not direct canonical table/view access.
- Default priority tiers are `T0` safety, `T1` decision-critical, `T2` optimization/learning, `T3` informational.
- Initial adaptive adjustment is bounded to `[-0.15, +0.15]` as versioned product policy.
- Default attention budget: unlimited-as-needed T0; max 1 active primary T1; 2–3 visible T2; T3 collapsed/digest/in-app by default.
- Behavioral preference effects decay toward neutral; explicit preferences persist until changed.
- Empirical calibration constants remain versioned policy, not scientific truth.

## Review Focus

- **Malformed or incomplete signal inputs:** invalid enum/state, missing source refs, or null materiality dimensions must be rejected or explicitly classified, never silently coerced.
- **Conflicting semantic-family states:** a candidate must never be both duplicate and contradiction/escalation; classification must resolve exactly one family state.
- **Preference corruption or out-of-range values:** adaptive adjustment must remain bounded even if stored preference values are malformed or stale.
- **Concurrent delivery/action decisions:** simultaneous workers must not emit duplicate active T1 items or two primary actions for the same insight.
- **Adaptive subsystem failure:** ranking/learning failure must fall back to deterministic tiering + neutral preference state without suppressing safety or flooding notifications.

---

### Task 1: Establish 001G Policy Configuration and Canonical Enums

**Files:**
- Create: `db/migrations/001G_001_policy_config.sql`
- Create: `tests/sql/001g_policy_config.sql`
- Modify: `.github/workflows/psi-cim-certify.yml`

**Interfaces:**
- Consumes: existing PostgreSQL database and `psi_dashboard_reader` role.
- Produces:
  - table `psi_orchestration_policy(policy_version text primary key, adaptive_min numeric, adaptive_max numeric, behavioral_decay_days integer, t1_active_limit integer, t2_visible_limit integer, active boolean, created_at timestamptz)`
  - SQL function `psi_active_orchestration_policy() RETURNS psi_orchestration_policy`
  - canonical check constraints/enums encoded as SQL checks for priority tiers, signal types, duplicate classes, authority classes, and action burden classes.

- [ ] **Step 1: Write the failing policy-contract tests**
  - exactly one active orchestration policy is returned;
  - `adaptive_min = -0.15`;
  - `adaptive_max = 0.15`;
  - `t1_active_limit = 1`;
  - `t2_visible_limit = 3`;
  - `behavioral_decay_days` is positive;
  - invalid tier/signal/duplicate/action values are rejected by constraints.

- [ ] **Step 2: Run the test and confirm failure**
  `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/sql/001g_policy_config.sql`

- [ ] **Step 3: Implement the policy table and lookup function**
  Seed version `001G-R1`; function must raise if zero or multiple active policies exist.

- [ ] **Step 4: Run the policy test and confirm pass**

- [ ] **Step 5: Wire migration/test into CI**

- [ ] **Step 6: Commit**
  `git commit -m "feat: add PSI 001G orchestration policy contract"`

### Task 2: Add Change Signals, Insight Candidates, and Materiality Oracle

**Files:**
- Create: `db/migrations/001G_002_signal_materiality.sql`
- Create: `tests/sql/001g_materiality.sql`

**Interfaces:**
- Consumes: `psi_active_orchestration_policy()`.
- Produces: `change_signals`, `insight_candidates`, `materiality_receipts`, and `psi_evaluate_materiality(p_signal_id uuid) RETURNS text`.

- [ ] Write failing tests for `G-MAT-001` through `G-MAT-004`, malformed signal type, and missing source refs.
- [ ] Run tests and confirm failure.
- [ ] Implement schema and deterministic materiality oracle with safety/state-transition bypasses.
- [ ] Make materiality receipts immutable.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add PSI 001G materiality oracle`.

### Task 3: Implement Semantic Fingerprinting and Redundancy Classification

**Files:**
- Create: `db/migrations/001G_003_fingerprint_redundancy.sql`
- Create: `tests/sql/001g_redundancy.sql`

**Interfaces:**
- Consumes: `insight_candidates`, prior `personal_insights`.
- Produces: `insight_fingerprints`, `redundancy_receipts`, `psi_classify_candidate(p_candidate_id uuid) RETURNS text`.

- [ ] Write failing tests for `G-DUP-001` through `G-DUP-005` and exact-one classification.
- [ ] Run tests and confirm failure.
- [ ] Implement stable semantic fingerprint from user + subject + candidate type + claim/context + direction + authority class.
- [ ] Implement deterministic exact-one classification and immutable receipt.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add semantic redundancy classification`.

### Task 4: Add Deterministic Eligibility Oracle and Delivery Cooldowns

**Files:**
- Create: `db/migrations/001G_004_eligibility_cooldown.sql`
- Create: `tests/sql/001g_eligibility.sql`

**Interfaces:**
- Consumes: materiality/redundancy receipts, 001E authority classes, orchestration policy.
- Produces: `eligibility_decisions`, `delivery_cooldowns`, `psi_evaluate_eligibility(p_candidate_id uuid, p_now timestamptz) RETURNS text`.

- [ ] Test duplicate suppression, normal eligibility, 72h trend cooldown, safety cooldown bypass, user suppression boundary, contradiction handling, and analysis-continuity during cooldown.
- [ ] Run tests and confirm failure.
- [ ] Implement versioned cooldown policy and deterministic eligibility.
- [ ] Make receipts immutable/versioned.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add deterministic insight eligibility oracle`.

### Task 5: Add Hard Priority Tiers and Bounded Adaptive Ranking

**Files:**
- Create: `db/migrations/001G_005_priority_ranking.sql`
- Create: `tests/sql/001g_ranking.sql`

**Interfaces:**
- Produces `priority_decisions`, `psi_priority_tier(p_candidate_id uuid) RETURNS text`, and `psi_rank_candidate(p_candidate_id uuid, p_preference_adjustment numeric DEFAULT 0) RETURNS numeric`.

- [ ] Test T0/T1/T2/T3 assignment and invalid tier sources.
- [ ] Test bounded preference adjustment, zero dwell-time effect, cross-tier protection, safety non-demotion, and corrupted preference containment.
- [ ] Run tests and confirm failure.
- [ ] Implement hard tiering before adaptive adjustment; write immutable priority receipt.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add bounded adaptive insight ranking`.

### Task 6: Enforce Attention and Notification Budgets

**Files:**
- Create: `db/migrations/001G_006_delivery_budget.sql`
- Create: `tests/sql/001g_delivery_budget.sql`

**Interfaces:**
- Produces `delivery_events` and `psi_delivery_decision(p_candidate_id uuid, p_surface text, p_now timestamptz) RETURNS text`.

- [ ] Test `G-NOTIFY-001` through `G-NOTIFY-004` plus concurrent T1 delivery.
- [ ] Run tests and confirm failure.
- [ ] Implement user/tier locking via advisory lock or dedicated budget-head row.
- [ ] Implement delivery receipts.
- [ ] Run two-session contention test; prove only one active T1 primary.
- [ ] Commit `feat: enforce PSI attention budgets`.

### Task 7: Implement Usefulness Feedback and Interpretable Preference State

**Files:**
- Create: `db/migrations/001G_007_usefulness_preferences.sql`
- Create: `tests/sql/001g_learning.sql`

**Interfaces:**
- Produces `usefulness_events`, `preference_state_versions`, `psi_record_usefulness_event(...) RETURNS uuid`, `psi_effective_preference(...) RETURNS numeric`.

- [ ] Test `G-LEARN-001` through `G-LEARN-005`, single vs repeated bounded behavior, forbidden engagement signals, and out-of-range persistence.
- [ ] Run tests and confirm failure.
- [ ] Implement append-only explicit/behavioral usefulness events.
- [ ] Implement versioned preference projection: behavioral decay, explicit persistence.
- [ ] Run tests and confirm pass.
- [ ] Re-run ranking tests using actual preference projection.
- [ ] Commit `feat: add bounded usefulness learning`.

### Task 8: Implement Next-Action Candidates and Smallest-Sufficient-Action Oracle

**Files:**
- Create: `db/migrations/001G_008_next_action.sql`
- Create: `tests/sql/001g_next_action.sql`

**Interfaces:**
- Produces `next_action_candidates`, `next_action_decisions`, `psi_select_next_action(p_insight_id uuid) RETURNS uuid`.

- [ ] Test `G-ACT-001` through `G-ACT-007` plus concurrent selector uniqueness.
- [ ] Run tests and confirm failure.
- [ ] Implement burden classes B0–B5 and action admissibility.
- [ ] Implement dominant-uncertainty selection.
- [ ] Enforce one-primary-action uniqueness.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add smallest sufficient next-action oracle`.

### Task 9: Add Action Execution, Closure, and Learning Capture

**Files:**
- Create: `db/migrations/001G_009_action_closure.sql`
- Create: `tests/sql/001g_action_closure.sql`

**Interfaces:**
- Produces `action_executions`, `action_outcomes`, `psi_close_action(...) RETURNS uuid`.

- [ ] Test click-not-completion, threshold closure, analyzed/decision closure, decision-object requirement, no learning-before-closure, and invalid transitions.
- [ ] Run tests and confirm failure.
- [ ] Implement execution/outcome state machine.
- [ ] Implement closure-triggered approved usefulness events only.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: close the PSI action-learning loop`.

### Task 10: Add Full Audit Receipt and Reconstruction APIs

**Files:**
- Create: `db/migrations/001G_010_audit_receipts.sql`
- Create: `tests/sql/001g_auditability.sql`

**Interfaces:**
- Produces `v_psi_orchestration_receipt`, `api_orchestration_receipt(p_insight_or_candidate_id uuid) RETURNS jsonb`, `api_orchestration_attention() RETURNS jsonb`.

- [ ] Test `G-AUD-001` through `G-AUD-005` plus five version fields.
- [ ] Run tests and confirm failure.
- [ ] Implement deterministic signal→action/outcome JSON lineage including suppressed/deferred paths.
- [ ] Revoke direct dashboard reads; grant governed API execution only.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add orchestration audit receipts`.

### Task 11: Implement Deterministic Degraded Mode

**Files:**
- Create: `db/migrations/001G_011_degraded_mode.sql`
- Create: `tests/sql/001g_degraded_mode.sql`

**Interfaces:**
- Produces `psi_rank_candidate_safe(p_candidate_id uuid) RETURNS numeric` and `orchestration_runtime_events`.

- [ ] Simulate unavailable preference projection, invalid preference version, ranking error.
- [ ] Assert deterministic eligibility/tier preserved, adaptive adjustment 0, T0 still delivered, no flood/silence, failure receipted.
- [ ] Run tests and confirm failure.
- [ ] Implement safe wrapper that catches adaptive-layer failures only.
- [ ] Run tests and confirm pass.
- [ ] Commit `feat: add deterministic PSI orchestration fallback`.

### Task 12: Compile the 20 Constitutional Invariants into a Single CI Oracle

**Files:**
- Create: `tests/sql/001g_invariants.sql`
- Create: `tests/fixtures/001g_invariants.json`
- Modify: `.github/workflows/psi-cim-certify.yml`

- [ ] Encode INV-G-001 through INV-G-020 in JSON.
- [ ] Add one executable SQL assertion block per invariant.
- [ ] Run suite and require 20/20 PASS.
- [ ] Add invariant suite to CI after component tests.
- [ ] Commit `test: enforce PSI 001G constitutional invariants`.

### Task 13: Add End-to-End Orchestration Fixture

**Files:**
- Create: `tests/sql/001g_e2e.sql`
- Create: `tests/fixtures/001g_e2e_expected.json`

- [ ] Build synthetic persistent stress-improvement scenario through materiality, eligibility, T2 ranking, in-app delivery, `REVIEW_EVIDENCE`, explicit helpful feedback, preference update, science/safety immutability, and second-candidate duplicate suppression.
- [ ] Run fixture and confirm failure.
- [ ] Fix only integration mismatches.
- [ ] Run fixture and compare exact semantic output to expected JSON.
- [ ] Commit `test: certify PSI 001G end-to-end orchestration`.

### Task 14: Add Migration Replay and Authorization Regression Gates

**Files:**
- Create: `tests/sql/001g_migration_replay.sql`
- Create: `tests/sql/001g_auth_regression.sql`
- Modify: `.github/workflows/psi-cim-certify.yml`

- [ ] Test clean migration, second replay, denied direct canonical/view reads, allowed governed API execute, and forged-context rejection.
- [ ] Run on fresh PostgreSQL 17 and confirm current failures.
- [ ] Fix migration ordering/idempotency only; do not weaken permissions.
- [ ] Re-run: clean build PASS, second replay PASS, auth regression PASS.
- [ ] Commit `test: add PSI 001G migration and auth regression gates`.

### Task 15: Produce the 001G Certification Receipt and Freeze Gate

**Files:**
- Create: `docs/receipts/PSI-CIM-001G-R1.md`
- Create: `docs/receipts/PSI-CIM-001G-R1.json`
- Create: `scripts/verify_001g.sh`
- Modify: `README.md`

- [ ] Create verification script running all 14 prerequisite suites in canonical order.
- [ ] Run script and record exact PASS counts.
- [ ] Create machine-readable receipt with commit SHA, policy version, counts, replay/auth results, open calibration parameters, verdict.
- [ ] Create human-readable receipt separating verified facts from calibration parameters.
- [ ] Update README with architecture, verification command, certification state.
- [ ] Commit `docs: certify PSI-CIM-001G R1`.

## Final Verification Gate

Before declaring 001G complete, run:

```bash
bash scripts/verify_001g.sh
```

Required conjunctive result:

```text
20/20 constitutional invariants PASS
all G-MAT tests PASS
all G-DUP tests PASS
all G-RANK tests PASS
all G-NOTIFY tests PASS
all G-ACT tests PASS
all G-LEARN tests PASS
all G-AUD tests PASS
E2E orchestration PASS
migration clean replay PASS
second replay PASS
authorization regression PASS
degraded-mode fallback PASS
```

The implementation is **not** certified if any conjunct is missing, even if the feature appears operational.
