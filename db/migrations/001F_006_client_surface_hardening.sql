-- PSI-CIM-001F-HARDEN-006
-- NEW post-001F client-surface hardening; NOT original signed historical lineage.
-- Purpose: explicitly deny client-role access to internal PSI functions and CREATE on
-- trusted schemas used by SECURITY DEFINER code. Governed api_* functions remain
-- executable only by psi_dashboard_reader.

BEGIN;

-- Trusted schemas used by SECURITY DEFINER functions must never be attacker-writable.
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

-- Explicitly converge function ACLs for every PSI-owned, non-extension public function.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public'
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

COMMIT;
