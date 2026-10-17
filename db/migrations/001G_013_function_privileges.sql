-- PSI-CIM-001G internal orchestration functions are server-side implementation
-- details. Dashboard/Data-API callers may use only explicitly governed API
-- functions. PostgreSQL grants EXECUTE on new functions to PUBLIC by default,
-- so remove that implicit authority explicitly.

REVOKE EXECUTE ON FUNCTION psi_active_orchestration_policy() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_receipt_immutable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_evaluate_materiality(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_register_candidate_fingerprint(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_safety_rank(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_classify_candidate(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_evaluate_eligibility(uuid,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_priority_tier(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_rank_candidate(uuid,numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_delivery_decision(uuid,text,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_effective_preference(uuid,text,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_record_usefulness_event(uuid,uuid,text,text,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_candidate_preference_adjustment(uuid,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_burden_rank(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_choose_best_action(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_select_next_action(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_close_action(uuid,text,numeric,jsonb,jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_orchestration_receipt(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_rank_candidate_safe(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_resolve_delivery(uuid,text,text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION psi_resolve_delivery_from_action_outcome() FROM PUBLIC;

-- Governed user-facing APIs remain unavailable to PUBLIC and are granted only
-- to the dashboard role when that role exists.
REVOKE EXECUTE ON FUNCTION api_orchestration_receipt(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION api_orchestration_attention() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    REVOKE EXECUTE ON FUNCTION psi_active_orchestration_policy() FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_receipt_immutable() FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_evaluate_materiality(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_register_candidate_fingerprint(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_safety_rank(text) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_classify_candidate(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_evaluate_eligibility(uuid,timestamptz) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_priority_tier(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_rank_candidate(uuid,numeric) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_delivery_decision(uuid,text,timestamptz) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_effective_preference(uuid,text,timestamptz) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_record_usefulness_event(uuid,uuid,text,text,timestamptz) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_candidate_preference_adjustment(uuid,timestamptz) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_burden_rank(text) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_choose_best_action(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_select_next_action(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_close_action(uuid,text,numeric,jsonb,jsonb) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_orchestration_receipt(uuid,uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_rank_candidate_safe(uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_resolve_delivery(uuid,text,text,uuid) FROM psi_dashboard_reader;
    REVOKE EXECUTE ON FUNCTION psi_resolve_delivery_from_action_outcome() FROM psi_dashboard_reader;

    GRANT EXECUTE ON FUNCTION api_orchestration_receipt(uuid) TO psi_dashboard_reader;
    GRANT EXECUTE ON FUNCTION api_orchestration_attention() TO psi_dashboard_reader;
  END IF;
END $$;
