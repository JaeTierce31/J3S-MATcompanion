# PSI-CIM-BASELINE-LINEAGE-001 — Recovered Baseline Lineage Manifest

**Status:** recovery in progress; original artifacts recovered, clean-from-zero proof pending  
**Verified runtime:** Neon project `polished-resonance-55615569`, branch `br-shiny-mode-b807pp2e`, database `neondb`, PostgreSQL 17  
**Purpose:** recover canonical pre-001G lineage without fabricating historical migrations.

## Recovery result

Original packaged artifacts were recovered from the active working artifact store. The recovered packages are not reconstructed from memory.

| Stage | Package SHA-256 | Migration SHA-256 | Integrity |
|---|---|---|---|
| 001B R1 receipt | `6cb1d490772cc3c27f1c97c1f8a068d0dea7f1da7bb8cd84fad72d78dfa6bdca` | n/a | receipt file hashes PASS; Ed25519 artifact signature PASS |
| 001C R1 runtime certification | `d64b15c5660a7c929d1920125f50ada5c1c776e7312f4586e4443a7468686647` | `001B_base.sql`: `e9b5704af817a7e2c7c6841010655c97e86bec27f3bc627a15e4648f786a8126`; `001C_runtime_hardening.sql`: `69d6b76a9723052a0e5fcecc8ed305738a553ad2bcbd00123151cb22d9f3ae7c` | every listed file hash PASS; Ed25519 artifact signature PASS |
| 001D R1 | `bcdb937ca1830ae253c31feec2713a87e3f392c32fad428423c1a9cdd179a7e6` | `2cdadabf81970ac534643f32ba1441821794b7a790150d3f2c84475c900791e2` | every listed file hash PASS; Ed25519 artifact signature PASS |
| 001E R1 | `f7bef6e47550d3b766c0db8284f8ea519664d614d9f04860c6b60934068c40a5` | `fda38fd5dfd57bed4d9bd7a0066acc582c0d8ab5cb4714966c7a50ab3e13bca9` | every listed file hash PASS; Ed25519 artifact signature PASS |
| 001F R1 | `921edcfa4725537a387e4fd10f7decf7f543785176656ddad71339eab600e41f` | `5feeef146069191b989d8738f272f7abb69bbd096527e5bae32e6c3e539b2a04` | every listed file hash PASS; Ed25519 artifact signature PASS |

The signatures use ephemeral artifact-integrity keys. They attest artifact bytes only; they are not organizational, legal, clinical, or human approval signatures.

## Canonical 001B choice

The earlier multi-file 001B DDL package is **superseded provenance**, not the clean-build base. Its concatenated SQL hash is `7a927c00d6395963e788332d73b3b8ddac2d2806ce9c1266db646fd6b41ea26d`.

The later signed 001C certification package contains amended `migrations/001B_base.sql` with hash `e9b5704af817a7e2c7c6841010655c97e86bec27f3bc627a15e4648f786a8126`. It materially adds R1 changes including entity registration, ontology mappings, stronger product/ingredient constraints, and replay/idempotency hardening. Therefore that later signed file is the canonical base for recovery.

## Recovered canonical order

```text
000_roles.sql                     NEW compatibility repair
001B_base.sql                     ORIGINAL signed recovered artifact
001C_runtime_hardening.sql        ORIGINAL signed recovered artifact
001D_longitudinal_intelligence.sql ORIGINAL signed recovered artifact
001E_personal_intelligence.sql    ORIGINAL signed recovered artifact
001F_delivery_read_model.sql      ORIGINAL signed recovered artifact
```

`000_roles.sql` is explicitly new. It repairs a historical clean-build ordering defect: signed `001B_base.sql` grants to `psi_dashboard_reader` before signed `001C_runtime_hardening.sql` creates that role. Historical signed files must not be edited to hide this defect.

## Verified 001F runtime object inventory

Read-only catalog inspection of the verified 001F runtime currently reports:

- **46** public tables;
- **17** public views;
- **48** public non-extension functions;
- **37** public triggers;
- **7** RLS-enabled public tables;
- **7** public RLS policies.

Object-level fingerprints are generated from live PostgreSQL catalog definitions using SHA-256 over table columns/defaults + constraints + indexes + view SQL, `pg_get_functiondef()` for functions, and `pg_get_triggerdef()` for triggers. These fingerprints are evidence of the verified runtime state and will be used to compare the recovered clean build against the runtime baseline.

### 001D objects evidenced by both receipt and runtime

- `observation_daily_rollups`
- `observation_weekly_rollups`
- `experiment_protocols`
- `experiment_checkins`
- `claim_applicability_matrices`
- `terminology_resolution_queue`
- `user_auth_identities`
- `v_user_metric_daily`
- `v_user_metric_weekly`
- `v_experiment_metric_windows`
- `v_experiment_temporal_analytics`
- `v_recommendation_trace_edges`
- `v_personalized_knowledge_graph`
- associated rollup/readiness/applicability/recommendation-trace API functions

### 001E objects evidenced by both receipt and runtime

- `personal_insights`
- `insight_confidence_components`
- `insight_evidence_links`
- `attention_items`
- `v_user_insight_feed`
- `v_user_attention_queue`
- `psi_insight_confidence(...)`
- `psi_authority_guard(...)`
- `api_dashboard_insights()`
- `api_dashboard_attention()`

### 001F objects evidenced by both receipt and runtime

- `v_user_decision_feed`
- `api_dashboard_decision_feed()`
- governed identity path `auth.user_id() -> user_auth_identities -> PSI user -> decision feed`

## Authorization audit findings

### Verified safe today

- `psi_dashboard_reader` has no direct SELECT/INSERT/UPDATE/DELETE privileges on the audited user-scoped 001D–001F tables.
- `authenticated` likewise has no direct audited-table privileges.
- No non-owner role currently has direct privileges on the seven RLS-protected core tables.
- SECURITY DEFINER API functions revoke `PUBLIC` EXECUTE and grant the dashboard role explicitly.
- SECURITY DEFINER functions pin `search_path`.
- neither `public` nor `auth` schema is CREATE-writable by `PUBLIC`, `authenticated`, or `psi_dashboard_reader`; therefore the current SECURITY DEFINER search paths are not exposed to untrusted-schema hijacking.

### Hardening defect discovered

The seven historical RLS policies still use mutable session configuration:

```sql
user_id = current_setting('app.user_id', true)::uuid
```

while the governed 001D–001F API path has moved to verified Neon Auth identity resolution. This is not currently exploitable through the client roles because direct table privileges are revoked, but it is a latent authorization hazard if direct grants are ever added.

**Required handling:** do not rewrite signed historical migrations. Create a new post-001F hardening migration that aligns RLS with `psi_current_user_from_auth()` / verified auth identity and adds regression tests proving mutable `app.user_id` cannot authorize table access.

## Secrets audit

Recovered migration SQL contains no embedded credentials. `001C_runtime_hardening.sql` defines `psi_auth_keys(secret bytea)` but explicitly does not provision secrets; deployment/runtime keys were external.

## Open gates

1. Import exact recovered migration bytes into this reconciliation branch or another immutable artifact store without reformatting.
2. Run clean PostgreSQL 17 build from empty using `000_roles.sql` + recovered signed chain.
3. Compare resulting object fingerprints against the verified 001F runtime manifest.
4. Classify any differences as expected runtime integration objects, historical post-package drift, or defects.
5. Run a second full replay from zero-built state.
6. Only after the clean build and fingerprint comparison pass may repository clean-from-zero move from BLOCKED to PASS.

## Explicit non-claim

No reconstructed 001F baseline snapshot is authorized or needed at this stage. Original migration artifacts have been recovered. A reconstructed snapshot should be considered only if exact-byte import or executable recovery of these originals becomes impossible.
