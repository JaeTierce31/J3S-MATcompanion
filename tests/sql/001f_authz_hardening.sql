\set ON_ERROR_STOP on

-- Core historical RLS policies must be verified-auth bound and never mutable app.user_id bound.
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM pg_policies
  WHERE schemaname='public'
    AND tablename IN ('goals','user_medications','user_stack_items','experiments','observations','recommendations','decisions')
    AND (coalesce(qual,'') NOT ILIKE '%psi_current_user_from_auth()%'
         OR coalesce(with_check,'') NOT ILIKE '%psi_current_user_from_auth()%'
         OR coalesce(qual,'') ILIKE '%app.user_id%'
         OR coalesce(with_check,'') ILIKE '%app.user_id%');
  IF n<>0 THEN RAISE EXCEPTION 'AUTHZ_RLS_FAIL: % core policies remain mutable/unverified',n; END IF;
END $$;

-- Later 001D/001E user-owned tables must have defense-in-depth RLS.
-- Eight expose verified-auth SELECT only; the identity map is direct deny-all.
DO $$
DECLARE missing_rls integer; read_policies integer; bad_policy integer; identity_policies integer;
BEGIN
  SELECT count(*) INTO missing_rls
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN (
      'observation_daily_rollups','observation_weekly_rollups',
      'experiment_protocols','experiment_checkins','user_auth_identities',
      'personal_insights','insight_confidence_components','insight_evidence_links','attention_items'
    )
    AND NOT c.relrowsecurity;
  IF missing_rls<>0 THEN RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: % later tables lack RLS',missing_rls; END IF;

  SELECT count(*) INTO read_policies
  FROM pg_policies
  WHERE schemaname='public'
    AND tablename IN (
      'observation_daily_rollups','observation_weekly_rollups',
      'experiment_protocols','experiment_checkins',
      'personal_insights','insight_confidence_components','insight_evidence_links','attention_items'
    )
    AND cmd='SELECT';
  IF read_policies<>8 THEN RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: expected 8 read policies, found %',read_policies; END IF;

  SELECT count(*) INTO bad_policy
  FROM pg_policies
  WHERE schemaname='public'
    AND tablename IN (
      'observation_daily_rollups','observation_weekly_rollups',
      'experiment_protocols','experiment_checkins',
      'personal_insights','insight_confidence_components','insight_evidence_links','attention_items'
    )
    AND (cmd<>'SELECT'
         OR coalesce(qual,'') NOT ILIKE '%psi_current_user_from_auth()%'
         OR coalesce(qual,'') ILIKE '%app.user_id%');
  IF bad_policy<>0 THEN RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: % late policies violate verified-auth read-only contract',bad_policy; END IF;

  SELECT count(*) INTO identity_policies
  FROM pg_policies
  WHERE schemaname='public' AND tablename='user_auth_identities';
  IF identity_policies<>0 THEN RAISE EXCEPTION 'AUTHZ_IDENTITY_RLS_FAIL: identity map has % permissive policies',identity_policies; END IF;
END $$;

-- Internal non-extension PSI functions must not be client executable.
DO $$
DECLARE n integer;
BEGIN
  WITH funcs AS (
    SELECT p.oid,p.proacl,p.proowner,p.proname
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND p.proname NOT LIKE 'api\_%' ESCAPE '\'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
  ), public_exec AS (
    SELECT DISTINCT f.oid
    FROM funcs f CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl,acldefault('f',f.proowner))) a
    WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
  )
  SELECT count(*) INTO n
  FROM funcs f
  WHERE EXISTS(SELECT 1 FROM public_exec x WHERE x.oid=f.oid)
     OR has_function_privilege('psi_dashboard_reader',f.oid,'EXECUTE')
     OR has_function_privilege('authenticated',f.oid,'EXECUTE');
  IF n<>0 THEN RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: % internal functions remain client executable',n; END IF;
END $$;

-- Governed api_* functions are dashboard-only, never PUBLIC/authenticated.
DO $$
DECLARE bad integer;
BEGIN
  WITH funcs AS (
    SELECT p.oid,p.proacl,p.proowner
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND p.proname LIKE 'api\_%' ESCAPE '\'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
  ), public_exec AS (
    SELECT DISTINCT f.oid
    FROM funcs f CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl,acldefault('f',f.proowner))) a
    WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
  )
  SELECT count(*) INTO bad
  FROM funcs f
  WHERE EXISTS(SELECT 1 FROM public_exec x WHERE x.oid=f.oid)
     OR NOT has_function_privilege('psi_dashboard_reader',f.oid,'EXECUTE')
     OR has_function_privilege('authenticated',f.oid,'EXECUTE');
  IF bad<>0 THEN RAISE EXCEPTION 'AUTHZ_API_FAIL: % governed APIs have incorrect ACLs',bad; END IF;
END $$;

-- Every owner-created SECURITY DEFINER public function must pin search_path including pg_temp.
DO $$
DECLARE bad integer;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND pg_get_userbyid(p.proowner)=current_user
    AND (p.proconfig IS NULL OR NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) cfg
      WHERE cfg LIKE 'search_path=%' AND cfg LIKE '%pg_temp%'
    ));
  IF bad<>0 THEN RAISE EXCEPTION 'AUTHZ_SEARCH_PATH_FAIL: % SECURITY DEFINER functions lack pinned search_path',bad; END IF;
END $$;

-- Trusted schemas used by SECURITY DEFINER code must not be CREATE-writable by client roles.
DO $$
DECLARE bad integer;
BEGIN
  WITH role_names(role_name) AS (VALUES ('psi_dashboard_reader'::text),('authenticated'::text)),
       schema_names(schema_name) AS (VALUES ('public'::text),('auth'::text))
  SELECT count(*) INTO bad
  FROM role_names r CROSS JOIN schema_names s
  WHERE EXISTS(SELECT 1 FROM pg_roles pr WHERE pr.rolname=r.role_name)
    AND EXISTS(SELECT 1 FROM pg_namespace pn WHERE pn.nspname=s.schema_name)
    AND has_schema_privilege(r.role_name,s.schema_name,'CREATE');
  IF bad<>0 THEN RAISE EXCEPTION 'AUTHZ_SCHEMA_FAIL: % client-role trusted-schema CREATE grants remain',bad; END IF;
END $$;

DO $$
BEGIN
  IF has_function_privilege('psi_dashboard_reader','psi_current_user_from_auth()','EXECUTE') THEN
    RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: dashboard can execute identity resolver directly';
  END IF;
  IF has_function_privilege('psi_dashboard_reader','psi_refresh_daily_rollups(date,date)','EXECUTE') THEN
    RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: dashboard can refresh rollups directly';
  END IF;
END $$;

-- Behavioral RLS probe. The shim models verified auth subject resolution on vanilla PostgreSQL CI.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.user_id() RETURNS text
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'') $$;
REVOKE ALL ON FUNCTION auth.user_id() FROM PUBLIC;

DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='psi_rls_probe') THEN CREATE ROLE psi_rls_probe NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public,auth TO psi_rls_probe;
GRANT EXECUTE ON FUNCTION auth.user_id() TO psi_rls_probe;
GRANT EXECUTE ON FUNCTION psi_current_user_from_auth() TO psi_rls_probe;
GRANT SELECT,INSERT ON goals,personal_insights,observation_daily_rollups TO psi_rls_probe;

INSERT INTO users(id) VALUES
  ('00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b2')
ON CONFLICT DO NOTHING;
INSERT INTO user_auth_identities(auth_provider,auth_subject,user_id,active) VALUES
  ('neon_auth','sub-a','00000000-0000-0000-0000-0000000000a1',true),
  ('neon_auth','sub-b','00000000-0000-0000-0000-0000000000b2',true)
ON CONFLICT(auth_provider,auth_subject) DO UPDATE SET user_id=EXCLUDED.user_id,active=true;
INSERT INTO goals(id,user_id,label,domain,target_direction,status) VALUES
 ('10000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','A goal','test','understand','active'),
 ('10000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b2','B goal','test','understand','active')
ON CONFLICT DO NOTHING;
INSERT INTO personal_insights(id,user_id,insight_type,subject_type,title,summary,confidence,authority_class,status) VALUES
 ('20000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','change_detected','test','A insight','A only',0.5,'informational','active'),
 ('20000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b2','change_detected','test','B insight','B only',0.5,'informational','active')
ON CONFLICT DO NOTHING;
INSERT INTO observation_daily_rollups(user_id,metric,day,n) VALUES
 ('00000000-0000-0000-0000-0000000000a1','probe','2026-10-16',1),
 ('00000000-0000-0000-0000-0000000000b2','probe','2026-10-16',1)
ON CONFLICT(user_id,metric,day) DO UPDATE SET n=EXCLUDED.n;

SET ROLE psi_rls_probe;
SELECT set_config('request.jwt.claim.sub','sub-a',false);
SELECT set_config('app.user_id','00000000-0000-0000-0000-0000000000b2',false);
DO $$
BEGIN
  -- Core table: A's seeded row must be visible, B's seeded row and every foreign row must be invisible.
  IF NOT EXISTS(SELECT 1 FROM goals WHERE id='10000000-0000-0000-0000-0000000000a1')
     OR EXISTS(SELECT 1 FROM goals WHERE id='10000000-0000-0000-0000-0000000000b2')
     OR EXISTS(SELECT 1 FROM goals WHERE user_id<>'00000000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'AUTHZ_RLS_FAIL: forged app.user_id changed core visibility';
  END IF;

  -- Later table: tolerate arbitrary additional A-owned rows created by upstream verification,
  -- while proving the fixed B row and every foreign-user row remain invisible.
  IF NOT EXISTS(SELECT 1 FROM personal_insights WHERE id='20000000-0000-0000-0000-0000000000a1')
     OR EXISTS(SELECT 1 FROM personal_insights WHERE id='20000000-0000-0000-0000-0000000000b2')
     OR EXISTS(SELECT 1 FROM personal_insights WHERE user_id<>'00000000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: cross-user personal insight visible';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM observation_daily_rollups WHERE user_id='00000000-0000-0000-0000-0000000000a1' AND metric='probe' AND day='2026-10-16')
     OR EXISTS(SELECT 1 FROM observation_daily_rollups WHERE user_id='00000000-0000-0000-0000-0000000000b2' AND metric='probe' AND day='2026-10-16')
     OR EXISTS(SELECT 1 FROM observation_daily_rollups WHERE user_id<>'00000000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: cross-user rollup visible';
  END IF;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO goals(user_id,label,domain,target_direction,status)
    VALUES('00000000-0000-0000-0000-0000000000b2','forged','test','understand','active');
    RAISE EXCEPTION 'AUTHZ_RLS_FAIL: cross-user goal insert unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class,status)
    VALUES('00000000-0000-0000-0000-0000000000b2','change_detected','test','forged','forged',0.5,'informational','active');
    RAISE EXCEPTION 'AUTHZ_LATE_RLS_FAIL: direct personal-insight write unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

DROP OWNED BY psi_rls_probe;
DROP ROLE psi_rls_probe;
