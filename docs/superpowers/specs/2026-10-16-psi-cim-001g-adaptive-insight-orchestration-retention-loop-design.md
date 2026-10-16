# PSI-CIM-001G — Adaptive Insight Orchestration & Retention Loop Design Specification

**Status:** Design approved; implementation not yet authorized  
**Date:** 2026-10-16  
**Depends on:** PSI-CIM-001D, 001E, and 001F

## Purpose

001G governs when PSI creates an insight, suppresses or defers one, ranks competing attention, learns from bounded usefulness signals, and selects the smallest sufficient next action.

**Core law:** Eligibility is deterministic. Ranking is bounded-adaptive. Action selection minimizes burden. Learning changes delivery preference only; it cannot change scientific truth, safety severity, or medical authority.

## Non-goals

001G does not diagnose disease, autonomously change prescription medication, override clinicians, optimize for raw engagement, allow preferences to demote critical safety, or allow engagement behavior to increase scientific certainty.

## Canonical lifecycle

```text
RAW CHANGE
→ CHANGE SIGNAL
→ INSIGHT CANDIDATE
→ MATERIALITY CHECK
→ FINGERPRINT / DUPLICATE CHECK
→ COOLDOWN / PERSISTENCE CHECK
→ ELIGIBILITY DECISION
→ PRIORITY TIER
→ BOUNDED ADAPTIVE RANKING
→ DELIVERY DECISION
→ USER RESPONSE
→ NEXT-ACTION CANDIDATES
→ ACTION POLICY FILTER
→ SMALLEST SUFFICIENT ACTION
→ ACTION EXECUTION
→ ACTION OUTCOME
→ LEARNING CAPTURE
→ PREFERENCE STATE UPDATE
→ FUTURE RANKING
```

Alternative states: `SUPPRESSED`, `DEFERRED`, `SUPERSEDED`, `CONTRADICTED`, `EXPIRED`, `ACKNOWLEDGED`, `NO_ACTION`, `ESCALATED`.

Every transition must be receipted.

## Constitutional invariants

1. Learning cannot make an ineligible insight eligible.
2. Preference data cannot change scientific certainty.
3. Preference data cannot alter safety severity.
4. Preference data cannot change authority class.
5. Critical safety bypasses cooldown.
6. Critical safety cannot be permanently muted.
7. Exact duplicates never generate a new active insight.
8. Contradictions are never suppressed as duplicates.
9. Material revisions preserve prior lineage.
10. Cooldown affects delivery only.
11. Adaptive ranking is bounded.
12. Adaptive ranking cannot cross hard tiers unless explicit policy permits it.
13. Dwell time and engagement volume cannot drive ranking.
14. Every suppression decision has a reason receipt.
15. Every delivered insight has a ranking receipt.
16. Every selected action has a policy receipt.
17. One insight has at most one primary action.
18. `NO_ACTION` is valid.
19. Reserved actions never auto-execute.
20. Learning is captured only from observable response or completed state change.

## Acceptance-test families

- `G-MAT-*` materiality
- `G-DUP-*` duplicate/revision
- `G-RANK-*` bounded adaptive ranking
- `G-NOTIFY-*` notification budget
- `G-ACT-*` smallest-next-action policy
- `G-LEARN-*` learning integrity
- `G-AUD-*` auditability

## Freeze decision

Freeze:

> **Deterministic eligibility → bounded adaptive ranking → smallest sufficient action → user outcome → bounded usefulness learning.**

Do not freeze empirical calibration constants yet: behavioral decay half-life, exact adaptive cap, materiality thresholds, notification cadence, burden weights, or information-gain weights.

The frozen elements are the control architecture, authority boundary, auditability requirement, learning boundary, state semantics, and invariant set.
