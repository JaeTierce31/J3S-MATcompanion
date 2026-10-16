-- Active attention must reflect delivery decisions, not the entire candidate set.
-- Suppressed/deferred/undelivered/resolved candidates remain in audit history but
-- are not part of the current user attention payload.

CREATE OR REPLACE FUNCTION psi_orchestration_attention_for_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'candidate_id',c.id,
    'insight_id',c.materialized_insight_id,
    'title',c.proposed_title,
    'authority_class',c.authority_class,
    'tier',vcs.tier,
    'priority',pd.final_priority,
    'delivery_type',vcs.delivery_type,
    'delivered_at',vcs.delivered_at,
    'currently_active',vcs.currently_active
  ) ORDER BY pd.final_priority DESC NULLS LAST,vcs.delivered_at DESC),'[]'::jsonb)
  FROM v_delivery_current_state vcs
  JOIN insight_candidates c ON c.id=vcs.candidate_id
  JOIN priority_decisions pd ON pd.id=vcs.priority_decision_id
  WHERE c.user_id=p_user_id
    AND vcs.currently_active;
$$;

CREATE OR REPLACE FUNCTION api_orchestration_attention()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT psi_orchestration_attention_for_user(psi_current_user_from_auth());
$$;

REVOKE EXECUTE ON FUNCTION psi_orchestration_attention_for_user(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION api_orchestration_attention() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    REVOKE EXECUTE ON FUNCTION psi_orchestration_attention_for_user(uuid) FROM psi_dashboard_reader;
    GRANT EXECUTE ON FUNCTION api_orchestration_attention() TO psi_dashboard_reader;
  END IF;
END $$;
