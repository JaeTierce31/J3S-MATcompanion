CREATE TABLE IF NOT EXISTS priority_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id uuid NOT NULL REFERENCES insight_candidates(id),
  tier text NOT NULL CHECK (tier IN ('T0','T1','T2','T3')),
  base_priority numeric NOT NULL,
  priority_reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
  adaptive_adjustment numeric NOT NULL,
  adaptive_sources jsonb NOT NULL DEFAULT '[]'::jsonb,
  final_priority numeric NOT NULL,
  safety_override boolean NOT NULL DEFAULT false,
  ranking_model_version text NOT NULL DEFAULT '001G-R1',
  preference_state_version text NOT NULL DEFAULT 'neutral',
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  decided_at timestamptz NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_priority_immutable ON priority_decisions;
CREATE TRIGGER trg_priority_immutable BEFORE UPDATE OR DELETE ON priority_decisions FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_priority_tier(p_candidate_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  e eligibility_decisions%ROWTYPE;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;
  SELECT * INTO e FROM eligibility_decisions WHERE candidate_id=p_candidate_id ORDER BY evaluated_at DESC LIMIT 1;

  IF c.safety_relevance IN ('high','critical') OR coalesce(e.decision,'')='ESCALATE' OR c.candidate_type='safety_attention' THEN
    RETURN 'T0';
  ELSIF c.candidate_type IN ('experiment_result','decision_critical','uncertainty') THEN
    RETURN 'T1';
  ELSIF c.candidate_type IN ('change_detected','optimization','redundancy','goal_progress','data_quality') THEN
    RETURN 'T2';
  ELSIF c.candidate_type IN ('evidence_context','research_update','education') THEN
    RETURN 'T3';
  ELSE
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='unknown candidate type for priority tier: ' || c.candidate_type;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION psi_rank_candidate(p_candidate_id uuid, p_preference_adjustment numeric DEFAULT 0)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  pol psi_orchestration_policy%ROWTYPE;
  tier_value text;
  base_value numeric;
  bounded numeric;
  final_value numeric;
  safety boolean;
BEGIN
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  tier_value := psi_priority_tier(p_candidate_id);
  base_value := CASE tier_value WHEN 'T0' THEN 400 WHEN 'T1' THEN 300 WHEN 'T2' THEN 200 WHEN 'T3' THEN 100 END;
  bounded := greatest(pol.adaptive_min, least(pol.adaptive_max, coalesce(p_preference_adjustment,0)));
  final_value := base_value + bounded;
  safety := tier_value='T0';

  INSERT INTO priority_decisions(candidate_id,tier,base_priority,priority_reasons,adaptive_adjustment,adaptive_sources,final_priority,safety_override,ranking_model_version,preference_state_version,policy_version)
  VALUES (p_candidate_id,tier_value,base_value,jsonb_build_array('hard_tier_'||tier_value),bounded,'[]'::jsonb,final_value,safety,'001G-R1','neutral',pol.policy_version);

  RETURN final_value;
END;
$$;
