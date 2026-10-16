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

    IF has_function_privilege('psi_dashboard_reader','psi_evaluate_materiality(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal materiality oracle'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_classify_candidate(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal redundancy oracle'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_evaluate_eligibility(uuid,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal eligibility oracle'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_rank_candidate(uuid,numeric)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal ranking mutation'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_delivery_decision(uuid,text,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal delivery mutation'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_record_usefulness_event(uuid,uuid,text,text,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal usefulness mutation'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_select_next_action(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal next-action mutation'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_close_action(uuid,text,numeric,jsonb,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal action closure'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_resolve_delivery(uuid,text,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal delivery resolution'; END IF;
    IF has_function_privilege('psi_dashboard_reader','psi_rank_candidate_safe(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader can execute internal degraded-mode ranker'; END IF;

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
