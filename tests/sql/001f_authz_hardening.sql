\set ON_ERROR_STOP on

-- Structural RLS oracle: every historical user-scope policy must resolve through verified auth.
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
  IF n<>0 THEN RAISE EXCEPTION 'AUTHZ_RLS_FAIL: % policies still mutable/unverified',n; END IF;
END $$;

-- Function ACL oracle: no internal non-extension PSI function may remain PUBLIC/dashboard executable.
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
    FROM funcs f
    CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl,acldefault('f',f.proowner))) a
    WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
  )
  SELECT count(*) INTO n
  FROM funcs f
  WHERE EXISTS(SELECT 1 FROM public_exec x WHERE x.oid=f.oid)
     OR has_function_privilege('psi_dashboard_reader',f.oid,'EXECUTE');
  IF n<>0 THEN RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: % internal functions remain client executable',n; END IF;
END $$;

-- Governed API allowlist invariant: APIs are dashboard-executable but never PUBLIC-executable.
DO $$
DECLARE bad integer;
BEGIN
  WITH funcs AS (
    SELECT p.oid,p.proacl,p.proowner,p.proname
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND p.proname LIKE 'api\_%' ESCAPE '\'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
  ), public_exec AS (
    SELECT DISTINCT f.oid
    FROM funcs f
    CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl,acldefault('f',f.proowner))) a
    WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
  )
  SELECT count(*) INTO bad
  FROM funcs f
  WHERE EXISTS(SELECT 1 FROM public_exec x WHERE x.oid=f.oid)
     OR NOT has_function_privilege('psi_dashboard_reader',f.oid,'EXECUTE');
  IF bad<>0 THEN RAISE EXCEPTION 'AUTHZ_API_FAIL: % governed APIs have incorrect ACLs',bad; END IF;
END $$;

-- Dashboard must not invoke identity resolver or maintenance/mutation helpers directly.
DO $$
BEGIN
  IF has_function_privilege('psi_dashboard_reader','psi_current_user_from_auth()','EXECUTE') THEN
    RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: dashboard can execute identity resolver directly';
  END IF;
  IF has_function_privilege('psi_dashboard_reader','psi_refresh_daily_rollups(date,date)','EXECUTE') THEN
    RAISE EXCEPTION 'AUTHZ_FUNC_FAIL: dashboard can refresh rollups directly';
  END IF;
END $$;

-- Behavioral RLS probe using a local auth.user_id() shim.
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
GRANT SELECT,INSERT ON goals TO psi_rls_probe;

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

SET ROLE psi_rls_probe;
SELECT set_config('request.jwt.claim.sub','sub-a',false);
SELECT set_config('app.user_id','00000000-0000-0000-0000-0000000000b2',false);
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM goals;
  IF n<>1 THEN RAISE EXCEPTION 'AUTHZ_RLS_FAIL: forged app.user_id changed visible row count to %',n; END IF;
  IF EXISTS(SELECT 1 FROM goals WHERE user_id<>'00000000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'AUTHZ_RLS_FAIL: cross-user row visible under forged app.user_id';
  END IF;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO goals(user_id,label,domain,target_direction,status)
    VALUES('00000000-0000-0000-0000-0000000000b2','forged','test','understand','active');
    RAISE EXCEPTION 'AUTHZ_RLS_FAIL: cross-user insert unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

DROP OWNED BY psi_rls_probe;
DROP ROLE psi_rls_probe;
