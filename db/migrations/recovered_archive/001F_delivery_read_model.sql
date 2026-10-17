-- PSI-CIM-001F — delivery read model
CREATE OR REPLACE VIEW v_user_decision_feed WITH (security_invoker=true) AS
SELECT i.id insight_id,i.user_id,i.insight_type,i.title,i.summary,
       i.confidence,i.authority_class,i.status,i.generated_at,
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
         'component',c.component,'score',c.score,'rationale',c.rationale
       ) ORDER BY c.component)
         FROM insight_confidence_components c WHERE c.insight_id=i.id),'[]'::jsonb)
         AS confidence_breakdown,
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
         'evidence_type',e.evidence_type,'evidence_id',e.evidence_id,'relation',e.relation
       ) ORDER BY e.evidence_type,e.relation)
         FROM insight_evidence_links e WHERE e.insight_id=i.id),'[]'::jsonb)
         AS evidence_links,
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
         'id',a.id,'category',a.category,'priority',a.priority,'title',a.title,
         'reason',a.reason,'recommended_action',a.recommended_action,
         'authority_class',a.authority_class,'status',a.status
       ) ORDER BY a.priority DESC,a.created_at DESC)
         FROM attention_items a WHERE a.source_insight_id=i.id),'[]'::jsonb)
         AS attention_items
FROM personal_insights i;

CREATE OR REPLACE FUNCTION api_dashboard_decision_feed()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.generated_at DESC),'[]'::jsonb)
  FROM v_user_decision_feed v
  WHERE v.user_id=psi_current_user_from_auth()
    AND v.status='active'
$$;

REVOKE SELECT ON v_user_decision_feed FROM psi_dashboard_reader;
REVOKE ALL ON FUNCTION api_dashboard_decision_feed() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api_dashboard_decision_feed() TO psi_dashboard_reader;
