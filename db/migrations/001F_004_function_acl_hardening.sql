-- PSI-CIM-AUTHZ-FUNC-001
-- NEW post-001F hardening migration. Not historical lineage.
-- Deny-by-default function execution: client roles may invoke governed api_* entrypoints only.

BEGIN;

DO $$
DECLARE f record;
BEGIN
  -- Internal PSI-owned functions: no PUBLIC or dashboard execution.
  FOR f IN
    SELECT p.oid,
           quote_ident(n.nspname)||'.'||quote_ident(p.proname)||'('||pg_get_function_identity_arguments(p.oid)||')' AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND p.proname NOT LIKE 'api\_%' ESCAPE '\'
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_proc'::regclass
          AND d.objid=p.oid
          AND d.deptype='e'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',f.signature);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM psi_dashboard_reader',f.signature);
  END LOOP;

  -- Governed API functions: never PUBLIC, explicitly callable by dashboard role.
  FOR f IN
    SELECT p.oid,
           quote_ident(n.nspname)||'.'||quote_ident(p.proname)||'('||pg_get_function_identity_arguments(p.oid)||')' AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND pg_get_userbyid(p.proowner)=current_user
      AND p.proname LIKE 'api\_%' ESCAPE '\'
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_proc'::regclass
          AND d.objid=p.oid
          AND d.deptype='e'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO psi_dashboard_reader',f.signature);
  END LOOP;
END $$;

COMMIT;
