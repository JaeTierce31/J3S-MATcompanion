CREATE TABLE IF NOT EXISTS next_action_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  insight_id uuid NOT NULL REFERENCES personal_insights(id) ON DELETE CASCADE,
  action_type text NOT NULL CHECK (action_type IN ('OBSERVE_ONLY','COLLECT_MORE_DATA','REVIEW_EVIDENCE','REVIEW_INTERACTION','CLARIFY_CONFOUNDER','REPEAT_EXPERIMENT','RECORD_USER_DECISION','ESCALATE_TO_CLINICIAN','NO_ACTION')),
  authority_class text NOT NULL CHECK (authority_class IN ('informational','advisory','reserved')),
  expected_information_gain numeric NOT NULL CHECK (expected_information_gain >= 0 AND expected_information_gain <= 1),
  decision_relevance numeric NOT NULL CHECK (decision_relevance >= 0 AND decision_relevance <= 1),
  burden_class text NOT NULL CHECK (burden_class IN ('B0','B1','B2','B3','B4','B5')),
  safety_priority integer NOT NULL DEFAULT 0 CHECK (safety_priority >= 0 AND safety_priority <= 5),
  eligibility boolean NOT NULL DEFAULT true,
  dominant_uncertainty text,
  rationale text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS next_action_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  insight_id uuid NOT NULL UNIQUE REFERENCES personal_insights(id) ON DELETE CASCADE,
  selected_candidate_id uuid NOT NULL UNIQUE REFERENCES next_action_candidates(id),
  selection_reason text NOT NULL,
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  adaptive_adjustment numeric NOT NULL DEFAULT 0,
  decided_at timestamptz NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_next_action_decision_immutable ON next_action_decisions;
CREATE TRIGGER trg_next_action_decision_immutable BEFORE UPDATE OR DELETE ON next_action_decisions FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_burden_rank(p_burden text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_burden WHEN 'B0' THEN 0 WHEN 'B1' THEN 1 WHEN 'B2' THEN 2 WHEN 'B3' THEN 3 WHEN 'B4' THEN 4 WHEN 'B5' THEN 5 ELSE 99 END;
$$;

CREATE OR REPLACE FUNCTION psi_choose_best_action(p_insight_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE chosen uuid;
BEGIN
  SELECT id INTO chosen
  FROM next_action_candidates
  WHERE insight_id=p_insight_id AND eligibility
  ORDER BY safety_priority DESC,
           (expected_information_gain*decision_relevance) DESC,
           psi_burden_rank(burden_class) ASC,
           created_at ASC,
           id ASC
  LIMIT 1;
  IF chosen IS NULL THEN RAISE EXCEPTION 'no eligible next action candidates for insight %',p_insight_id; END IF;
  RETURN chosen;
END;
$$;

CREATE OR REPLACE FUNCTION psi_select_next_action(p_insight_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  ins personal_insights%ROWTYPE;
  dominant text;
  min_score numeric;
  action text;
  burden text;
  authority text;
  info_gain numeric;
  relevance numeric;
  safety integer := 0;
  candidate_id uuid;
  existing uuid;
  pol psi_orchestration_policy%ROWTYPE;
BEGIN
  SELECT selected_candidate_id INTO existing FROM next_action_decisions WHERE insight_id=p_insight_id;
  IF existing IS NOT NULL THEN RETURN existing; END IF;

  SELECT * INTO STRICT ins FROM personal_insights WHERE id=p_insight_id;
  SELECT component,score INTO dominant,min_score FROM insight_confidence_components WHERE insight_id=p_insight_id ORDER BY score ASC,component ASC LIMIT 1;

  IF ins.insight_type='safety_attention' OR ins.authority_class='reserved' THEN
    action:='ESCALATE_TO_CLINICIAN'; burden:='B5'; authority:='reserved'; info_gain:=0.90; relevance:=1.00; safety:=5;
  ELSIF ins.insight_type='experiment_result' THEN
    action:='RECORD_USER_DECISION'; burden:='B1'; authority:='advisory'; info_gain:=0.80; relevance:=1.00;
  ELSIF dominant IS NULL OR min_score >= 0.80 THEN
    action:='NO_ACTION'; burden:='B0'; authority:='informational'; info_gain:=0; relevance:=0;
  ELSIF dominant IN ('data_quality','temporal_alignment','protocol_adherence') THEN
    action:='COLLECT_MORE_DATA'; burden:='B2'; authority:='advisory'; info_gain:=0.70; relevance:=0.80;
  ELSIF dominant='confounder_control' THEN
    action:='CLARIFY_CONFOUNDER'; burden:='B2'; authority:='advisory'; info_gain:=0.75; relevance:=0.85;
  ELSIF dominant IN ('scientific_certainty','population_match','dose_match','formulation_match','endpoint_match') THEN
    action:='REVIEW_EVIDENCE'; burden:='B1'; authority:='informational'; info_gain:=0.75; relevance:=0.85;
  ELSE
    action:='OBSERVE_ONLY'; burden:='B0'; authority:='informational'; info_gain:=0.20; relevance:=0.30;
  END IF;

  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (p_insight_id,action,authority,info_gain,relevance,burden,safety,true,dominant,'selected from dominant uncertainty and authority boundary')
  RETURNING id INTO candidate_id;

  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (p_insight_id,candidate_id,'smallest sufficient action for dominant uncertainty',pol.policy_version);

  RETURN candidate_id;
END;
$$;
