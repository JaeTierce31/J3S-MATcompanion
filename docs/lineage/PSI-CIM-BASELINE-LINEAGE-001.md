# PSI-CIM-BASELINE-LINEAGE-001 — Recovered Baseline Lineage Manifest

**Status:** **Recovered originals + clean 001F baseline + post-lineage hardening VERIFIED; zero→001G integration pending**  
**Verified runtime reference:** Neon project `polished-resonance-55615569`, branch `br-shiny-mode-b807pp2e`, database `neondb`, PostgreSQL 17  
**Purpose:** recover canonical pre-001G lineage without fabricating historical migrations, then harden it without rewriting signed history.

> The post-lineage H1–H4 hardening described below is currently certified in the repository/CI path. It has **not** been applied to the canonical Neon runtime branch referenced above.

## Recovery result

Original packaged artifacts were recovered from the active artifact store. They were not regenerated from memory or inferred from the runtime schema.

| Stage | Package SHA-256 | Migration SHA-256 | Integrity |
|---|---|---|---|
| 001B R1 receipt | `6cb1d490772cc3c27f1c97c1f8a068d0dea7f1da7bb8cd84fad72d78dfa6bdca` | n/a | receipt hashes PASS; Ed25519 artifact signature PASS |
| 001C R1 | `d64b15c5660a7c929d1920125f50ada5c1c776e7312f4586e4443a7468686647` | `001B_base.sql` `e9b5704af817a7e2c7c6841010655c97e86bec27f3bc627a15e4648f786a8126`; `001C_runtime_hardening.sql` `69d6b76a9723052a0e5fcecc8ed305738a553ad2bcbd00123151cb22d9f3ae7c` | all listed hashes PASS; signature PASS |
| 001D R1 | `bcdb937ca1830ae253c31feec2713a87e3f392c32fad428423c1a9cdd179a7e6` | `2cdadabf81970ac534643f32ba1441821794b7a790150d3f2c84475c900791e2` | all listed hashes PASS; signature PASS |
| 001E R1 | `f7bef6e47550d3b766c0db8284f8ea519664d614d9f04860c6b60934068c40a5` | `fda38fd5dfd57bed4d9bd7a0066acc582c0d8ab5cb4714966c7a50ab3e13bca9` | all listed hashes PASS; signature PASS |
| 001F R1 | `921edcfa4725537a387e4fd10f7decf7f543785176656ddad71339eab600e41f` | `5feeef146069191b989d8738f272f7abb69bbd096527e5bae32e6c3e539b2a04` | all listed hashes PASS; signature PASS |

These Ed25519 signatures are **artifact-integrity signatures only**. The keys were ephemeral and are not organizational, legal, clinical, or human-approval signatures.

## Canonical 001B choice

The earlier multi-file 001B DDL package is preserved as **superseded provenance**. The later signed 001C certification package carries the amended canonical `001B_base.sql`. It materially includes R1 entity registration, ontology mapping, stronger product/ingredient constraints, and replay/idempotency changes. Therefore the signed embedded `001B_base.sql` is the canonical recovered base.

## Canonical lineage classes

```text
000_roles.sql                        NEW_COMPATIBILITY_REPAIR
001B_base.sql                        ORIGINAL_SIGNED_RECOVERED
001C_runtime_hardening.sql           ORIGINAL_SIGNED_RECOVERED
001D_longitudinal_intelligence.sql   ORIGINAL_SIGNED_RECOVERED
001E_personal_intelligence.sql       ORIGINAL_SIGNED_RECOVERED
001F_delivery_read_model.sql         ORIGINAL_SIGNED_RECOVERED
001F_001_runtime_reconciliation.sql  RUNTIME_RECOVERED_RECONCILIATION
001F_002_definition_reconciliation.sql RUNTIME_RECOVERED_RECONCILIATION
001F_003_authz_rls_hardening.sql     POSTLINEAGE_HARDENING
001F_004_function_acl_hardening.sql  POSTLINEAGE_HARDENING
001F_005_late_table_rls_hardening.sql POSTLINEAGE_HARDENING
001F_006_client_surface_hardening.sql POSTLINEAGE_HARDENING
```

Historical signed files remain byte-for-byte preserved. `000_roles.sql` repairs the historical role-ordering defect without editing history.

## Verified historical 001F baseline root

The exact recovered chain plus the separately labeled compatibility/reconciliation layer builds from an empty PostgreSQL 17 database to the verified historical 001F product state.

**Historical manifest root:**

```text
151|0edffd890d3b1347b9abdf73f108322e856cef28a5e88045e249fe3d44fb08b5
```

This root fingerprints the historical product surface: relation definitions and RLS flags, non-extension function definitions, triggers, and policies, while excluding certification-only residue.

This historical root is intentionally frozen and is **not** rewritten to include later security hardening.

## Runtime reconciliation

The recovered signed 001C migration contains the historical custom HMAC context path. The verified later runtime had already superseded those objects with Neon Auth / Better Auth identity resolution. `001F_001_runtime_reconciliation.sql` and `001F_002_definition_reconciliation.sql` are explicitly runtime-derived reconciliation, not historical originals. They converge the recovered chain to the independently verified 001F runtime definitions.

No reconstructed 001F schema snapshot is required: the original migrations are executable and recoverable.

## Authorization/security findings and fixes

The lineage audit found four meaningful hardening gaps. None justified altering the signed originals.

### H1 — core RLS authority

Historical user-scope RLS used mutable `app.user_id`. `001F_003_authz_rls_hardening.sql` replaces those predicates with `psi_current_user_from_auth()` and verifies forged mutable session context cannot grant cross-user access.

### H2/H4 — function and trusted-schema attack surface

Internal invoker-rights PSI helpers inherited PostgreSQL's default `PUBLIC EXECUTE`; this was not a proven privilege escalation because direct table privileges were denied, but it broadened unnecessary client attack/abuse surface. `001F_004` and `001F_006` converge function ACLs so governed `api_*` functions remain the dashboard surface while internal helpers are denied to `PUBLIC`, `authenticated`, and dashboard roles. H4 also revokes client `CREATE` in trusted schemas used by SECURITY DEFINER code.

### H3 — later-table RLS defense in depth

Nine user-scoped 001D/001E tables did not originally have table-local RLS. `001F_005_late_table_rls_hardening.sql` enables RLS on all nine. Eight expose verified-auth SELECT-only policies; `user_auth_identities` remains direct deny-all with no permissive client policy. Canonical writes remain governed/owner paths.

### SECURITY DEFINER search-path invariant

All owner-created public SECURITY DEFINER PSI functions are asserted to pin a trusted `search_path` including `pg_temp`, and client roles are asserted unable to CREATE objects in the trusted `public`/`auth` schemas.

## Hardened post-lineage 001F root

After H1–H4, CI fingerprints product definitions plus RLS/policies, SECURITY DEFINER configuration, relevant function/relation ACLs, and trusted-schema ACLs.

**Hardened root:**

```text
177|61d9ba2210293729a6076572c416431312efa06dc1f595d12adbaf503bf27ed8
```

The root was captured after the first H1–H4 apply and again after complete H1–H4 replay. The two values are byte-identical.

**Authorization-hardening CI evidence:**
- run `39014174287`
- job `117342724655`
- source SHA `d6a80d2dd322e2d5d0c2e6dd26a0335a1b54b15e`
- result: **SUCCESS**

Verified by that run:
1. exact recovered migration hashes;
2. clean PostgreSQL 17 historical 001F baseline root;
3. H1–H4 first application;
4. structural and behavioral authorization oracle;
5. hardened 001F manifest root;
6. complete H1–H4 replay;
7. second oracle pass;
8. identical hardened root after replay.

The earlier RED run `39013573615` is retained as evidence that the strengthened test suite initially detected all nine missing late-table RLS boundaries before H3 was implemented.

## Current promotion boundary

**Verified now:**
- original 001B–001F artifacts recovered and hash-verified;
- no reconstructed snapshot required;
- empty PostgreSQL 17 can build deterministically to the verified 001F product baseline;
- historical 001F root is reproducible;
- H1–H4 security hardening passes and replays idempotently;
- hardened security root is reproducible.

**Still required before Issue #2 can be closed as full clean-from-zero lineage PASS:**
1. build an isolated integration branch from empty PostgreSQL 17 through recovered originals + compatibility/reconciliation + H1–H4 + the complete 001G chain;
2. execute the full 001G invariant/E2E/concurrency/auth-regression suite on that integrated lineage;
3. perform a complete second replay and prove the integrated state remains deterministic.

Production valid-interactive-JWT admission remains **Issue #3**, a separate runtime/authentication gate.

## Explicit deployment boundary

H1–H4 are repository/CI-certified but **not applied to the referenced canonical Neon runtime branch by this work**. Applying them to that runtime is a separate consequential migration decision requiring explicit authorization.
