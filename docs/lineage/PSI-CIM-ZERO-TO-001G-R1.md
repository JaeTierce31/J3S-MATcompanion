# PSI-CIM-ZERO-TO-001G-R1 — Clean-From-Zero Integration Certification

**Verdict:** **PASS — repository/CI clean-from-zero lineage through PSI-CIM-001G**  
**Repository:** `JaeTierce31/J3S-MATcompanion`  
**Branch:** `psi-cim-zero-to-001g-integration`  
**Certified source SHA:** `9075794a4966ce267b66cd88e5c1ad9815be6545`  
**CI run:** `39014998981`  
**CI job:** `117345181747`  
**Database engine:** PostgreSQL 17  

## Scope

This receipt certifies that the repository can deterministically construct the PSI-CIM database from an empty PostgreSQL 17 database through the recovered historical 001B–001F lineage, compatibility/reconciliation, post-lineage 001F hardening, complete 001G orchestration, and post-integration convergence fixes.

It does **not** authorize or imply production database migration, canonical Neon mutation, merge to `main`, deployment, or production JWT admission.

## Proven lineage

The certified sequence is:

```text
empty PostgreSQL 17
→ 000_roles.sql
→ recovered signed 001B_base.sql
→ recovered signed 001C_runtime_hardening.sql
→ recovered signed 001D_longitudinal_intelligence.sql
→ recovered signed 001E_personal_intelligence.sql
→ recovered signed 001F_delivery_read_model.sql
→ 001F_001 runtime reconciliation
→ 001F_002 definition reconciliation
→ 001F_003 verified-auth RLS hardening
→ 001F_004 function ACL hardening
→ 001F_005 later-table RLS hardening
→ 001F_006 client-surface hardening
→ complete 001G_001 … 001G_014 certified orchestration chain
→ 001G_015 integrated security convergence
→ 001G_016 deterministic preference revision ordering
```

Historical signed migration bytes remain unchanged. Compatibility, reconciliation, hardening, and integration fixes are separately labeled and versioned.

## Cryptographic roots

### Historical verified 001F product baseline

```text
151|0edffd890d3b1347b9abdf73f108322e856cef28a5e88045e249fe3d44fb08b5
```

### Post-lineage hardened 001F baseline

```text
177|61d9ba2210293729a6076572c416431312efa06dc1f595d12adbaf503bf27ed8
```

### Integrated zero→001G state

```text
238|183a767bb4ad935910054f5526c648f3b5b24957a3064aa32ad8ee2e5aca6465
```

The integrated root after full replay was byte-identical:

```text
238|183a767bb4ad935910054f5526c648f3b5b24957a3064aa32ad8ee2e5aca6465
```

## Full first-pass verification

Run `39014998981` / job `117345181747` verified, in order:

1. exact reconstruction of recovered signed migrations and hash verification;
2. empty PostgreSQL 17 → historical 001F baseline;
3. historical manifest root match;
4. H1–H4 post-lineage authorization hardening;
5. hardened 001F authorization oracle;
6. hardened 001F manifest root match;
7. complete 001G migration chain through `001G_016`;
8. full `scripts/verify_001g.sh` PASS;
9. inherited hardened authorization oracle PASS after 001G;
10. integrated schema/security root capture.

The full 001G verifier included:

- policy contract;
- materiality;
- redundancy;
- eligibility/cooldown;
- bounded ranking;
- delivery budget;
- deterministic usefulness learning;
- next-action oracle;
- action closure;
- delivery resolution;
- attention visibility;
- audit reconstruction;
- degraded mode;
- **20/20 constitutional invariants PASS**;
- end-to-end orchestration PASS;
- auth regression PASS;
- true two-process contention PASS:
  `one DELIVER_NOW, one BLOCKED, active_t1=1`.

## Full replay verification

The same database then received a complete replay of:

- `000_roles.sql`;
- recovered signed 001B–001F migrations;
- 001F reconciliation + H1–H4 hardening;
- every `001G_*.sql` migration including integration fixes.

After replay:

- inherited hardened authorization oracle: PASS;
- integrated root: identical to first apply;
- 20/20 001G invariants: PASS;
- 001G E2E: PASS;
- auth regression: PASS;
- true delivery-budget contention: PASS.

## Integration defects discovered and resolved

### INT-FIX-001 — SECURITY DEFINER convergence

The original certified 001G chain recreated two `api_orchestration_*` SECURITY DEFINER functions with `search_path=public`, which violated the stronger inherited post-001F search-path invariant.

`001G_015_integrated_security_convergence.sql` now:

- pins PSI-owned SECURITY DEFINER functions to `public, auth, pg_temp`;
- re-converges function ACLs so internal PSI helpers are not client executable;
- preserves governed dashboard execution for `api_*` only;
- reasserts client CREATE denial in trusted schemas.

### INT-FIX-002 — nondeterministic same-timestamp preference ordering

The certified 001G preference history previously ordered equal-timestamp versions by random UUID:

```text
ORDER BY effective_at DESC, id DESC
```

Because PostgreSQL `now()` is transaction-stable, multiple versions in one transaction can share `effective_at`, making UUID ordering nondeterministic.

`001G_016_preference_revision_ordering.sql` adds monotonic `revision` ordering and updates all relevant latest-preference reads to:

```text
ORDER BY effective_at DESC, revision DESC
```

The learning oracle now proves exact same-timestamp accumulation:

- one evidence-open → `0.02`;
- four evidence-opens → `0.08`;
- behavioral state decays toward neutral;
- explicit preference persists;
- science/safety truth remains unchanged;
- dwell-time remains rejected as a ranking signal.

### TEST-FIX-001 — RLS probe cardinality coupling

The inherited RLS behavioral test originally assumed exactly one visible same-user row. Upstream 001G verification legitimately creates additional same-user rows, causing a false positive. The oracle now proves the actual security property:

- fixed user-A seed is visible;
- fixed user-B seed is invisible;
- no foreign-user row is visible;
- additional user-A rows are allowed.

## Authority and security boundary retained

The integrated certification proves:

- mutable `app.user_id` cannot override verified identity scope;
- later user-owned 001D/001E tables have defense-in-depth RLS;
- `user_auth_identities` remains direct-client deny-all under RLS;
- internal PSI helpers are not exposed to PUBLIC, `authenticated`, or dashboard roles;
- governed `api_*` functions remain the dashboard execution surface;
- client roles cannot CREATE objects in trusted `public` / `auth` schemas;
- SECURITY DEFINER functions pin trusted search paths;
- 001G learning cannot alter scientific certainty, safety severity, authority class, or eligibility.

## Remaining external gate

**PSI-CIM-AUTH-E2E-001 / Issue #3 remains OPEN.**

A real issuer-generated interactive JWT has not yet been exercised end-to-end through the production-style client/verifier path. Repository clean-from-zero lineage PASS does not close that authentication-admission gate.

## Deployment boundary

No production or canonical Neon runtime schema was changed by this certification. All lineage/hardening/integration work described here is repository + CI evidence only unless and until a separate migration is explicitly authorized.
