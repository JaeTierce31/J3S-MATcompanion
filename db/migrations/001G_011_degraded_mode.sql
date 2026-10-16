CREATE TABLE IF NOT EXISTS orchestration_runtime_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id uuid NOT NULL REFERENCES insight_candidates(id),
  event_type text NOT NULL CHECK (event_type IN ('adaptive_failure','degraded_mode_entered')),
  error_sqlstate text,
  error_message text,
  fallback_mode text NOT NULL,
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_runtime_event_immutable ON orchestration_runtime_events;
CREATE TRIGGER trg_runtime_event_immutable BEFORE UPDATE OR DELETE ON orchestration_runtime_events FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_rank_candidate_safe(p_candidate_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  ed eligibility_decisions%ROWTYPE;
  pol psi_orchestration_policy%ROWTYPE;
  tier_value text;
  dim text;
  pref preference_state_versions%ROWTYPE;
  adjustment numeric := 0;
  result numeric;
  failure_state text;
  failure_message text;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();

  SELECT * INTO ed FROM eligibility_decisions WHERE candidate_id=p_candidate_id ORDER BY evaluated_at DESC LIMIT 1;
  IF NOT FOUND OR ed.decision NOT IN ('ELIGIBLE','ESCALATE','SUPERSEDE_EXISTING') THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='candidate is not deterministically eligible for ranking';
  END IF;

  -- Deterministic tiering is deliberately outside the adaptive failure boundary.
  tier_value := psi_priority_tier(p_candidate_id);

  dim := CASE
    WHEN c.candidate_type IN ('evidence_context','research_update','education') THEN 'research_detail'
    WHEN c.candidate_type IN ('experiment_result','optimization') THEN 'experiment_action_affinity'
    ELSE 'topic_affinity'
  END;

  BEGIN
    SELECT * INTO pref
    FROM preference_state_versions
    WHERE user_id=c.user_id AND dimension=dim
    ORDER BY effective_at DESC,id DESC LIMIT 1;

    IF FOUND THEN
      IF pref.version NOT LIKE '001G-R1:%' THEN
        RAISE EXCEPTION USING ERRCODE='22000', MESSAGE='invalid preference state version: '||pref.version;
      END IF;
      adjustment := psi_candidate_preference_adjustment(p_candidate_id,now());
    ELSE
      adjustment := 0;
    END IF;

    result := psi_rank_candidate(p_candidate_id,adjustment);
    RETURN result;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_state = RETURNED_SQLSTATE, failure_message = MESSAGE_TEXT;
    INSERT INTO orchestration_runtime_events(candidate_id,event_type,error_sqlstate,error_message,fallback_mode,policy_version)
    VALUES (p_candidate_id,'adaptive_failure',failure_state,failure_message,'deterministic_tier_neutral_preference',pol.policy_version);
    result := psi_rank_candidate(p_candidate_id,0);
    RETURN result;
  END;
END;
$$;
