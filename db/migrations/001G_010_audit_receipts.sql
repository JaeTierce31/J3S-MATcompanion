ALTER TABLE insight_candidates
  ADD COLUMN IF NOT EXISTS materialized_insight_id uuid REFERENCES personal_insights(id) ON DELETE SET NULL;

CREATE OR REPLACE VIEW v_psi_orchestration_receipt AS
SELECT
  c.id AS candidate_id,
  c.user_id,
  c.source_signal_id,
  c.materialized_insight_id,
  rr.id AS redundancy_receipt_id,
  rr.classification AS redundancy_classification,
  rr.matched_candidate_id,
  ed.id AS eligibility_decision_id,
  ed.decision AS eligibility_decision,
  pd.id AS priority_decision_id,
  pd.tier,
  pd.final_priority,
  de.id AS delivery_event_id,
  de.delivery_type,
  nad.id AS next_action_decision_id,
  nad.selected_candidate_id AS next_action_candidate_id
FROM insight_candidates c
LEFT JOIN LATERAL (
  SELECT * FROM redundancy_receipts x WHERE x.candidate_id=c.id ORDER BY x.evaluated_at DESC LIMIT 1
) rr ON true
LEFT JOIN LATERAL (
  SELECT * FROM eligibility_decisions x WHERE x.candidate_id=c.id ORDER BY x.evaluated_at DESC LIMIT 1
) ed ON true
LEFT JOIN LATERAL (
  SELECT * FROM priority_decisions x WHERE x.candidate_id=c.id ORDER BY x.decided_at DESC LIMIT 1
) pd ON true
LEFT JOIN LATERAL (
  SELECT * FROM delivery_events x WHERE x.candidate_id=c.id ORDER BY x.delivered_at DESC LIMIT 1
) de ON true
LEFT JOIN next_action_decisions nad ON nad.insight_id=c.materialized_insight_id;

CREATE OR REPLACE FUNCTION psi_orchestration_receipt(p_insight_or_candidate_id uuid,p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  s change_signals%ROWTYPE;
  mr materiality_receipts%ROWTYPE;
  rr redundancy_receipts%ROWTYPE;
  ed eligibility_decisions%ROWTYPE;
  pd priority_decisions%ROWTYPE;
  de delivery_events%ROWTYPE;
  nad next_action_decisions%ROWTYPE;
  nac next_action_candidates%ROWTYPE;
  pi personal_insights%ROWTYPE;
  pref_version text := 'neutral';
  pref_lineage jsonb := '[]'::jsonb;
  policy_v text := '001G-R1';
BEGIN
  SELECT * INTO c
  FROM insight_candidates
  WHERE user_id=p_user_id AND (id=p_insight_or_candidate_id OR materialized_insight_id=p_insight_or_candidate_id)
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='orchestration candidate not found for user';
  END IF;

  IF c.source_signal_id IS NOT NULL THEN
    SELECT * INTO s FROM change_signals WHERE id=c.source_signal_id AND user_id=p_user_id;
    SELECT * INTO mr FROM materiality_receipts WHERE signal_id=c.source_signal_id ORDER BY evaluated_at DESC LIMIT 1;
  END IF;
  SELECT * INTO rr FROM redundancy_receipts WHERE candidate_id=c.id ORDER BY evaluated_at DESC LIMIT 1;
  SELECT * INTO ed FROM eligibility_decisions WHERE candidate_id=c.id ORDER BY evaluated_at DESC LIMIT 1;
  SELECT * INTO pd FROM priority_decisions WHERE candidate_id=c.id ORDER BY decided_at DESC LIMIT 1;
  SELECT * INTO de FROM delivery_events WHERE candidate_id=c.id ORDER BY delivered_at DESC LIMIT 1;
  IF c.materialized_insight_id IS NOT NULL THEN
    SELECT * INTO pi FROM personal_insights WHERE id=c.materialized_insight_id AND user_id=p_user_id;
    SELECT * INTO nad FROM next_action_decisions WHERE insight_id=c.materialized_insight_id;
    IF FOUND THEN SELECT * INTO nac FROM next_action_candidates WHERE id=nad.selected_candidate_id; END IF;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'event_id',ue.id,
           'signal_type',ue.signal_type,
           'explicit_or_behavioral',ue.explicit_or_behavioral,
           'dimension',ue.dimension,
           'weight',ue.weight,
           'occurred_at',ue.occurred_at,
           'preference_version',ps.version,
           'explicit_value',ps.explicit_value,
           'behavioral_value',ps.behavioral_value
         ) ORDER BY ue.occurred_at,ue.id),'[]'::jsonb),
         coalesce((SELECT ps2.version FROM preference_state_versions ps2 WHERE ps2.user_id=p_user_id ORDER BY ps2.effective_at DESC,ps2.id DESC LIMIT 1),'neutral')
  INTO pref_lineage,pref_version
  FROM usefulness_events ue
  JOIN preference_state_versions ps ON ps.derived_from_event_id=ue.id
  WHERE ue.user_id=p_user_id AND (c.materialized_insight_id IS NULL OR ue.insight_id=c.materialized_insight_id);

  policy_v := coalesce(ed.policy_version,pd.policy_version,rr.policy_version,mr.policy_version,'001G-R1');

  RETURN jsonb_build_object(
    'candidate',to_jsonb(c),
    'signal',CASE WHEN s.id IS NULL THEN NULL ELSE to_jsonb(s) || jsonb_build_object('materiality',to_jsonb(mr)) END,
    'redundancy',CASE WHEN rr.id IS NULL THEN NULL ELSE to_jsonb(rr) END,
    'eligibility',CASE WHEN ed.id IS NULL THEN NULL ELSE to_jsonb(ed) END,
    'priority',CASE WHEN pd.id IS NULL THEN NULL ELSE to_jsonb(pd) END,
    'delivery',CASE WHEN de.id IS NULL THEN NULL ELSE to_jsonb(de) END,
    'insight',CASE WHEN pi.id IS NULL THEN NULL ELSE to_jsonb(pi) END,
    'next_action',CASE WHEN nad.id IS NULL THEN NULL ELSE to_jsonb(nad) || jsonb_build_object('candidate',to_jsonb(nac)) END,
    'preference_lineage',pref_lineage,
    'versions',jsonb_build_object(
      'policy_version',policy_v,
      'ranking_model_version',coalesce(pd.ranking_model_version,'001G-R1'),
      'preference_state_version',pref_version,
      'materiality_rule_version',coalesce(mr.policy_version,'001G-R1'),
      'action_policy_version',coalesce(nad.policy_version,'001G-R1')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION api_orchestration_receipt(p_insight_or_candidate_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT psi_orchestration_receipt(p_insight_or_candidate_id,psi_current_user_from_auth());
$$;

CREATE OR REPLACE FUNCTION api_orchestration_attention()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'candidate_id',c.id,
    'insight_id',c.materialized_insight_id,
    'title',c.proposed_title,
    'authority_class',c.authority_class,
    'tier',pd.tier,
    'priority',pd.final_priority,
    'delivery_type',de.delivery_type,
    'delivered_at',de.delivered_at
  ) ORDER BY pd.final_priority DESC NULLS LAST,de.delivered_at DESC NULLS LAST),'[]'::jsonb)
  FROM insight_candidates c
  LEFT JOIN LATERAL (SELECT * FROM priority_decisions x WHERE x.candidate_id=c.id ORDER BY x.decided_at DESC LIMIT 1) pd ON true
  LEFT JOIN LATERAL (SELECT * FROM delivery_events x WHERE x.candidate_id=c.id ORDER BY x.delivered_at DESC LIMIT 1) de ON true
  WHERE c.user_id=psi_current_user_from_auth();
$$;

REVOKE ALL ON FUNCTION api_orchestration_receipt(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION api_orchestration_attention() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    REVOKE ALL ON change_signals,insight_candidates,materiality_receipts,insight_fingerprints,redundancy_receipts,eligibility_decisions,priority_decisions,delivery_events,usefulness_events,preference_state_versions,next_action_candidates,next_action_decisions,action_executions,action_outcomes FROM psi_dashboard_reader;
    REVOKE ALL ON v_psi_orchestration_receipt FROM psi_dashboard_reader;
    GRANT EXECUTE ON FUNCTION api_orchestration_receipt(uuid) TO psi_dashboard_reader;
    GRANT EXECUTE ON FUNCTION api_orchestration_attention() TO psi_dashboard_reader;
  END IF;
END $$;
