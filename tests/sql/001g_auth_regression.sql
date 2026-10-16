DO $$
DECLARE u uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    IF has_table_privilege('psi_dashboard_reader','change_signals','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct change_signals SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','insight_candidates','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct insight_candidates SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','priority_decisions','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct priority_decisions SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','usefulness_events','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct usefulness_events SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','next_action_decisions','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct next_action_decisions SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','delivery_resolution_events','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct delivery_resolution_events SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','v_delivery_current_state','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct delivery current-state SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','v_psi_orchestration_receipt','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct orchestration view SELECT'; END IF;
    IF NOT has_function_privilege('psi_dashboard_reader','api_orchestration_receipt(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader lacks receipt API execute'; END IF;
    IF NOT has_function_privilege('psi_dashboard_reader','api_orchestration_attention()','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader lacks attention API execute'; END IF;
  END IF;

  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  IF u IS NULL THEN RAISE EXCEPTION 'runtime baseline user fixture missing'; END IF;
  PERFORM set_config('app.user_id',u::text,true);
  BEGIN
    PERFORM psi_current_user_from_auth();
    RAISE EXCEPTION 'forged app.user_id was accepted without verified auth context';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='forged app.user_id was accepted without verified auth context' THEN RAISE; END IF;
  END;
END $$;
