-- PSI-CIM-001G-INTEGRATION-HARDEN-015
-- NEW post-certification integration hardening; NOT part of the original 001G R1 certified SHA.
-- Purpose: preserve the stronger post-001F authorization boundary after 001G creates
-- additional functions. No product semantics are changed.

BEGIN;

-- Every PSI-owned SECURITY DEFINER function uses only trusted schemas, with pg_temp
-- last so temporary-object resolution cannot precede canonical schemas.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner)=current_user
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, auth, pg_temp', r.signature);
  END LOOP;
END $$;

-- Converge the complete PSI-owned function namespace after 001G. This deliberately
-- repeats the H4 policy so newly-created 001G functions cannot reopen default
-- PostgreSQL PUBLIC EXECUTE authority.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature,p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.signature);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.signature);
    END IF;

    IF r.proname LIKE 'api\_%' ESCAPE '\' THEN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO psi_dashboard_reader', r.signature);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM psi_dashboard_reader', r.signature);
      END IF;
    END IF;
  END LOOP;
END $$;

-- Reassert trusted-schema CREATE denial in case deployment role/bootstrap behavior
-- differs across environments.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='auth') THEN
    EXECUTE 'REVOKE CREATE ON SCHEMA auth FROM PUBLIC';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    EXECUTE 'REVOKE CREATE ON SCHEMA public FROM psi_dashboard_reader';
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='auth') THEN
      EXECUTE 'REVOKE CREATE ON SCHEMA auth FROM psi_dashboard_reader';
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE CREATE ON SCHEMA public FROM authenticated';
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='auth') THEN
      EXECUTE 'REVOKE CREATE ON SCHEMA auth FROM authenticated';
    END IF;
  END IF;
END $$;

COMMIT;
