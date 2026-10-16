CREATE TABLE IF NOT EXISTS psi_delivery_cooldown_policy (
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  candidate_type text NOT NULL,
  cooldown_family text NOT NULL,
  cooldown_interval interval NOT NULL CHECK (cooldown_interval >= interval '0'),
  PRIMARY KEY(policy_version,candidate_type)
);

INSERT INTO psi_delivery_cooldown_policy(policy_version,candidate_type,cooldown_family,cooldown_interval) VALUES
 ('001G-R1','safety_attention','safety',interval '0'),
 ('001G-R1','change_detected','personal_trend',interval '72 hours'),
 ('001G-R1','data_quality','data_quality',interval '24 hours'),
 ('001G-R1','goal_progress','goal_progress',interval '7 days'),
 ('001G-R1','optimization','optimization',interval '7 days'),
 ('001G-R1','redundancy','optimization',interval '7 days'),
 ('001G-R1','evidence_context','research_update',interval '14 days'),
 ('001G-R1','experiment_result','experiment_transition',interval '0')
ON CONFLICT (policy_version,candidate_type) DO UPDATE SET cooldown_family=excluded.cooldown_family,cooldown_interval=excluded.cooldown_interval;

CREATE TABLE IF NOT EXISTS delivery_cooldown_state (
  user_id uuid NOT NULL,
  cooldown_family text NOT NULL,
  last_delivered_at timestamptz NOT NULL,
  PRIMARY KEY(user_id,cooldown_family)
);

CREATE TABLE IF NOT EXISTS user_topic_suppression (
  user_id uuid NOT NULL,
  context_key text NOT NULL,
  muted boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,context_key)
);

CREATE TABLE IF NOT EXISTS eligibility_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id uuid NOT NULL REFERENCES insight_candidates(id),
  decision text NOT NULL CHECK (decision IN ('ELIGIBLE','SUPPRESS_DUPLICATE','SUPPRESS_LOW_VALUE','DEFER_COOLDOWN','DEFER_MORE_DATA','SUPERSEDE_EXISTING','ESCALATE')),
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
  materiality_result text,
  duplicate_class text,
  cooldown_state text NOT NULL,
  authority_state text NOT NULL,
  safety_state text NOT NULL,
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  evaluated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_eligibility_candidate_time ON eligibility_decisions(candidate_id,evaluated_at DESC);
DROP TRIGGER IF EXISTS trg_eligibility_immutable ON eligibility_decisions;
CREATE TRIGGER trg_eligibility_immutable BEFORE UPDATE OR DELETE ON eligibility_decisions FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_evaluate_eligibility(p_candidate_id uuid, p_now timestamptz)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  rr redundancy_receipts%ROWTYPE;
  mr materiality_receipts%ROWTYPE;
  cp psi_delivery_cooldown_policy%ROWTYPE;
  last_delivery timestamptz;
  muted_flag boolean := false;
  outcome text;
  reasons jsonb := '[]'::jsonb;
  cooldown_state text := 'none';
  safety_state text;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;

  SELECT * INTO rr FROM redundancy_receipts WHERE candidate_id=c.id ORDER BY evaluated_at DESC LIMIT 1;
  IF NOT FOUND THEN
    PERFORM psi_classify_candidate(c.id);
    SELECT * INTO rr FROM redundancy_receipts WHERE candidate_id=c.id ORDER BY evaluated_at DESC LIMIT 1;
  END IF;

  IF c.source_signal_id IS NOT NULL THEN
    SELECT * INTO mr FROM materiality_receipts WHERE signal_id=c.source_signal_id ORDER BY evaluated_at DESC LIMIT 1;
    IF NOT FOUND THEN
      PERFORM psi_evaluate_materiality(c.source_signal_id);
      SELECT * INTO mr FROM materiality_receipts WHERE signal_id=c.source_signal_id ORDER BY evaluated_at DESC LIMIT 1;
    END IF;
  END IF;

  safety_state := c.safety_relevance;

  IF c.safety_relevance IN ('high','critical') OR coalesce(mr.result,'')='SAFETY_OVERRIDE' OR rr.classification='ESCALATION' THEN
    outcome := 'ESCALATE';
    reasons := reasons || '"safety_precedence"'::jsonb;
    cooldown_state := 'bypassed';
  ELSE
    SELECT muted INTO muted_flag FROM user_topic_suppression WHERE user_id=c.user_id AND context_key=c.context_key;
    muted_flag := coalesce(muted_flag,false);

    IF muted_flag THEN
      outcome := 'SUPPRESS_LOW_VALUE';
      reasons := reasons || '"user_topic_muted"'::jsonb;
    ELSIF rr.classification='EXACT_DUPLICATE' THEN
      outcome := 'SUPPRESS_DUPLICATE';
      reasons := reasons || '"exact_duplicate"'::jsonb;
    ELSIF rr.classification IN ('CONTRADICTION','MATERIAL_REVISION') THEN
      outcome := 'SUPERSEDE_EXISTING';
      reasons := reasons || '"material_revision_or_contradiction"'::jsonb;
    ELSIF rr.classification='STATE_REFRESH' THEN
      outcome := 'SUPPRESS_LOW_VALUE';
      reasons := reasons || '"state_refresh_no_new_feed_item"'::jsonb;
    ELSIF c.source_signal_id IS NULL OR mr.id IS NULL THEN
      outcome := 'DEFER_MORE_DATA';
      reasons := reasons || '"missing_materiality_receipt"'::jsonb;
    ELSIF mr.result='WAIT_FOR_PERSISTENCE' THEN
      outcome := 'DEFER_MORE_DATA';
      reasons := reasons || '"wait_for_persistence"'::jsonb;
    ELSIF mr.result='BELOW_THRESHOLD' THEN
      outcome := 'SUPPRESS_LOW_VALUE';
      reasons := reasons || '"below_materiality_threshold"'::jsonb;
    ELSE
      SELECT * INTO cp FROM psi_delivery_cooldown_policy WHERE policy_version=c.policy_version AND candidate_type=c.candidate_type;
      IF FOUND AND cp.cooldown_interval > interval '0' THEN
        SELECT last_delivered_at INTO last_delivery FROM delivery_cooldown_state WHERE user_id=c.user_id AND cooldown_family=cp.cooldown_family;
        IF last_delivery IS NOT NULL AND p_now < last_delivery + cp.cooldown_interval THEN
          outcome := 'DEFER_COOLDOWN';
          cooldown_state := 'active';
          reasons := reasons || '"delivery_cooldown_active"'::jsonb;
        ELSE
          outcome := 'ELIGIBLE';
          cooldown_state := 'clear';
        END IF;
      ELSE
        outcome := 'ELIGIBLE';
        cooldown_state := 'none';
      END IF;
    END IF;
  END IF;

  INSERT INTO eligibility_decisions(candidate_id,decision,reasons,materiality_result,duplicate_class,cooldown_state,authority_state,safety_state,policy_version,evaluated_at)
  VALUES (c.id,outcome,reasons,mr.result,rr.classification,cooldown_state,c.authority_class,safety_state,c.policy_version,p_now);

  RETURN outcome;
END;
$$;
