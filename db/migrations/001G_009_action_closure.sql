CREATE TABLE IF NOT EXISTS action_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id uuid NOT NULL REFERENCES next_action_decisions(id) ON DELETE RESTRICT,
  status text NOT NULL CHECK (status IN ('planned','in_progress','completed','declined','cancelled')),
  closure_state jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(closure_state)='object'),
  user_response text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_execution_per_action_decision
  ON action_executions(decision_id)
  WHERE status IN ('planned','in_progress');

CREATE TABLE IF NOT EXISTS action_outcomes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id uuid NOT NULL UNIQUE REFERENCES action_executions(id) ON DELETE RESTRICT,
  resolution_type text NOT NULL CHECK (resolution_type IN ('resolved','no_action','escalated','superseded')),
  new_evidence_refs jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(new_evidence_refs)='array'),
  decision_refs jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(decision_refs)='array'),
  uncertainty_delta numeric NOT NULL CHECK (uncertainty_delta >= -1 AND uncertainty_delta <= 1),
  closed_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_action_outcome_immutable ON action_outcomes;
CREATE TRIGGER trg_action_outcome_immutable
BEFORE UPDATE OR DELETE ON action_outcomes
FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_close_action(
  p_execution_id uuid,
  p_resolution_type text,
  p_uncertainty_delta numeric,
  p_new_evidence_refs jsonb,
  p_decision_refs jsonb
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  ex action_executions%ROWTYPE;
  nad next_action_decisions%ROWTYPE;
  nac next_action_candidates%ROWTYPE;
  ins personal_insights%ROWTYPE;
  outcome_id uuid;
  expected_decisions integer := 0;
  found_decisions integer := 0;
  learning_signal text;
BEGIN
  SELECT * INTO STRICT ex FROM action_executions WHERE id=p_execution_id FOR UPDATE;
  IF ex.status <> 'in_progress' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='action execution must be in_progress before closure';
  END IF;

  SELECT * INTO STRICT nad FROM next_action_decisions WHERE id=ex.decision_id;
  SELECT * INTO STRICT nac FROM next_action_candidates WHERE id=nad.selected_candidate_id;
  SELECT * INTO STRICT ins FROM personal_insights WHERE id=nad.insight_id;

  IF p_resolution_type NOT IN ('resolved','no_action','escalated','superseded') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid resolution_type';
  END IF;
  IF jsonb_typeof(coalesce(p_new_evidence_refs,'[]'::jsonb)) <> 'array'
     OR jsonb_typeof(coalesce(p_decision_refs,'[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='closure refs must be JSON arrays';
  END IF;

  CASE nac.action_type
    WHEN 'COLLECT_MORE_DATA' THEN
      IF coalesce((ex.closure_state->>'observation_threshold_met')::boolean,false) IS NOT TRUE THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='observation threshold not met';
      END IF;
    WHEN 'REPEAT_EXPERIMENT' THEN
      IF coalesce(ex.closure_state->>'experiment_state','') NOT IN ('analyzed','decision') THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='experiment must reach analyzed or decision state';
      END IF;
    WHEN 'RECORD_USER_DECISION' THEN
      expected_decisions := jsonb_array_length(coalesce(p_decision_refs,'[]'::jsonb));
      IF expected_decisions = 0 THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='decision reference required';
      END IF;
      SELECT count(*) INTO found_decisions
      FROM decisions d
      WHERE d.id IN (
        SELECT value::uuid FROM jsonb_array_elements_text(p_decision_refs)
      );
      IF found_decisions <> expected_decisions THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='one or more decision references do not exist';
      END IF;
    WHEN 'NO_ACTION' THEN
      IF p_resolution_type <> 'no_action' THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='NO_ACTION must close as no_action';
      END IF;
    WHEN 'ESCALATE_TO_CLINICIAN' THEN
      IF p_resolution_type <> 'escalated' THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='clinician escalation must close as escalated';
      END IF;
    ELSE
      NULL;
  END CASE;

  INSERT INTO action_outcomes(execution_id,resolution_type,new_evidence_refs,decision_refs,uncertainty_delta)
  VALUES (ex.id,p_resolution_type,coalesce(p_new_evidence_refs,'[]'::jsonb),coalesce(p_decision_refs,'[]'::jsonb),p_uncertainty_delta)
  RETURNING id INTO outcome_id;

  UPDATE action_executions
  SET status='completed', completed_at=now()
  WHERE id=ex.id;

  learning_signal := CASE
    WHEN nac.action_type='REPEAT_EXPERIMENT' THEN 'COMPLETED_EXPERIMENT'
    WHEN nac.action_type IN ('COLLECT_MORE_DATA','REVIEW_EVIDENCE','REVIEW_INTERACTION','CLARIFY_CONFOUNDER','RECORD_USER_DECISION') THEN 'COMPLETED_ADVISORY_ACTION'
    ELSE NULL
  END;

  IF learning_signal IS NOT NULL THEN
    PERFORM psi_record_usefulness_event(ins.user_id,ins.id,learning_signal,'action_closure',now());
  END IF;

  RETURN outcome_id;
END;
$$;
