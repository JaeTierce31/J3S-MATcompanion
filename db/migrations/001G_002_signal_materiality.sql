CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS psi_materiality_policy (
  policy_version text PRIMARY KEY REFERENCES psi_orchestration_policy(policy_version),
  min_effect_magnitude numeric NOT NULL CHECK (min_effect_magnitude >= 0),
  min_persistence integer NOT NULL CHECK (min_persistence > 0),
  min_confidence numeric NOT NULL CHECK (min_confidence >= 0 AND min_confidence <= 1),
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO psi_materiality_policy(policy_version, min_effect_magnitude, min_persistence, min_confidence)
VALUES ('001G-R1', 0.20, 2, 0.50)
ON CONFLICT (policy_version) DO UPDATE SET
  min_effect_magnitude = EXCLUDED.min_effect_magnitude,
  min_persistence = EXCLUDED.min_persistence,
  min_confidence = EXCLUDED.min_confidence;

CREATE TABLE IF NOT EXISTS change_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  signal_type text NOT NULL CHECK (signal_type IN (
    'METRIC_SHIFT','TREND_REVERSAL','VARIABILITY_CHANGE','EXPERIMENT_PHASE_CHANGE',
    'ADHERENCE_CHANGE','CONFOUNDER_CHANGE','SAFETY_CHANGE','INTERACTION_CHANGE',
    'EVIDENCE_CHANGE','APPLICABILITY_CHANGE','GOAL_PROGRESS_CHANGE','DATA_QUALITY_CHANGE'
  )),
  subject_type text NOT NULL CHECK (length(trim(subject_type)) > 0),
  subject_id uuid NOT NULL,
  previous_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  magnitude numeric NOT NULL DEFAULT 0,
  direction text NOT NULL CHECK (direction IN ('up','down','none','mixed')),
  confidence numeric NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  persistence integer NOT NULL CHECK (persistence > 0),
  novelty numeric NOT NULL CHECK (novelty >= 0 AND novelty <= 1),
  safety_relevance text NOT NULL CHECK (safety_relevance IN ('none','low','moderate','high','critical')),
  source_refs jsonb NOT NULL CHECK (jsonb_typeof(source_refs) = 'array' AND jsonb_array_length(source_refs) > 0),
  detected_at timestamptz NOT NULL DEFAULT now(),
  policy_version text NOT NULL DEFAULT '001G-R1' REFERENCES psi_orchestration_policy(policy_version)
);

CREATE TABLE IF NOT EXISTS insight_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  candidate_type text NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid NOT NULL,
  proposed_title text NOT NULL,
  proposed_summary text NOT NULL,
  authority_class text NOT NULL CHECK (authority_class IN ('informational','advisory','reserved')),
  scientific_claim_refs jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(scientific_claim_refs) = 'array'),
  personal_evidence_refs jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(personal_evidence_refs) = 'array'),
  candidate_status text NOT NULL DEFAULT 'candidate' CHECK (candidate_status IN ('candidate','eligible','suppressed','deferred','superseded','delivered','expired')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS materiality_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id uuid NOT NULL REFERENCES change_signals(id),
  result text NOT NULL CHECK (result IN ('MATERIAL','BELOW_THRESHOLD','WAIT_FOR_PERSISTENCE','SAFETY_OVERRIDE')),
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  evaluated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION psi_receipt_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'receipt rows are immutable';
END;
$$;

DROP TRIGGER IF EXISTS trg_materiality_receipt_immutable ON materiality_receipts;
CREATE TRIGGER trg_materiality_receipt_immutable
BEFORE UPDATE OR DELETE ON materiality_receipts
FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_evaluate_materiality(p_signal_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  s change_signals%ROWTYPE;
  p psi_materiality_policy%ROWTYPE;
  outcome text;
  reasons jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO STRICT s FROM change_signals WHERE id = p_signal_id;
  SELECT * INTO STRICT p FROM psi_materiality_policy WHERE policy_version = s.policy_version;

  IF s.safety_relevance IN ('high','critical') OR s.signal_type = 'SAFETY_CHANGE' AND coalesce(s.current_state->>'severity','') IN ('high','critical') THEN
    outcome := 'SAFETY_OVERRIDE';
    reasons := reasons || '"safety_override"'::jsonb;
  ELSIF s.signal_type = 'EXPERIMENT_PHASE_CHANGE' AND coalesce(s.current_state->>'phase','') = 'completed' THEN
    outcome := 'MATERIAL';
    reasons := reasons || '"state_transition_material"'::jsonb;
  ELSIF abs(s.magnitude) < p.min_effect_magnitude THEN
    outcome := 'BELOW_THRESHOLD';
    reasons := reasons || '"below_effect_threshold"'::jsonb;
  ELSIF s.persistence < p.min_persistence THEN
    outcome := 'WAIT_FOR_PERSISTENCE';
    reasons := reasons || '"insufficient_persistence"'::jsonb;
  ELSIF s.confidence < p.min_confidence THEN
    outcome := 'BELOW_THRESHOLD';
    reasons := reasons || '"insufficient_confidence"'::jsonb;
  ELSE
    outcome := 'MATERIAL';
    reasons := reasons || '"material_thresholds_met"'::jsonb;
  END IF;

  INSERT INTO materiality_receipts(signal_id, result, reasons, policy_version)
  VALUES (s.id, outcome, reasons, s.policy_version);

  RETURN outcome;
END;
$$;
