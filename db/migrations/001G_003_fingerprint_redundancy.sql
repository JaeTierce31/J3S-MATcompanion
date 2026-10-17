ALTER TABLE insight_candidates
  ADD COLUMN IF NOT EXISTS direction text NOT NULL DEFAULT 'none' CHECK (direction IN ('up','down','none','mixed')),
  ADD COLUMN IF NOT EXISTS candidate_confidence numeric NOT NULL DEFAULT 0.5 CHECK (candidate_confidence >= 0 AND candidate_confidence <= 1),
  ADD COLUMN IF NOT EXISTS context_key text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS safety_relevance text NOT NULL DEFAULT 'none' CHECK (safety_relevance IN ('none','low','moderate','high','critical')),
  ADD COLUMN IF NOT EXISTS source_signal_id uuid REFERENCES change_signals(id);

CREATE TABLE IF NOT EXISTS insight_fingerprints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seq bigserial UNIQUE,
  candidate_id uuid NOT NULL UNIQUE REFERENCES insight_candidates(id),
  family_hash text NOT NULL,
  interpretation_hash text NOT NULL,
  evidence_hash text NOT NULL,
  direction text NOT NULL,
  candidate_confidence numeric NOT NULL,
  safety_relevance text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_insight_fingerprints_family_seq ON insight_fingerprints(family_hash, seq DESC);

CREATE TABLE IF NOT EXISTS redundancy_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id uuid NOT NULL UNIQUE REFERENCES insight_candidates(id),
  matched_candidate_id uuid REFERENCES insight_candidates(id),
  classification text NOT NULL CHECK (classification IN ('NEW','EXACT_DUPLICATE','STATE_REFRESH','MATERIAL_REVISION','CONTRADICTION','ESCALATION')),
  family_hash text NOT NULL,
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
  policy_version text NOT NULL DEFAULT '001G-R1' REFERENCES psi_orchestration_policy(policy_version),
  evaluated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_redundancy_receipt_immutable ON redundancy_receipts;
CREATE TRIGGER trg_redundancy_receipt_immutable
BEFORE UPDATE OR DELETE ON redundancy_receipts
FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_register_candidate_fingerprint(p_candidate_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  fid uuid;
  fhash text;
  ihash text;
  ehash text;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id = p_candidate_id;

  fhash := encode(digest(concat_ws('|', c.user_id::text, lower(c.subject_type), c.subject_id::text, lower(c.candidate_type), lower(c.context_key), lower(c.authority_class)), 'sha256'), 'hex');
  ihash := encode(digest(concat_ws('|', lower(trim(c.proposed_title)), lower(trim(c.proposed_summary)), lower(c.direction), lower(c.authority_class)), 'sha256'), 'hex');
  ehash := encode(digest(concat_ws('|', c.scientific_claim_refs::text, c.personal_evidence_refs::text), 'sha256'), 'hex');

  INSERT INTO insight_fingerprints(candidate_id, family_hash, interpretation_hash, evidence_hash, direction, candidate_confidence, safety_relevance)
  VALUES (c.id, fhash, ihash, ehash, c.direction, c.candidate_confidence, c.safety_relevance)
  ON CONFLICT (candidate_id) DO UPDATE SET
    family_hash = EXCLUDED.family_hash,
    interpretation_hash = EXCLUDED.interpretation_hash,
    evidence_hash = EXCLUDED.evidence_hash,
    direction = EXCLUDED.direction,
    candidate_confidence = EXCLUDED.candidate_confidence,
    safety_relevance = EXCLUDED.safety_relevance
  RETURNING id INTO fid;

  RETURN fid;
END;
$$;

CREATE OR REPLACE FUNCTION psi_safety_rank(p text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p
    WHEN 'none' THEN 0 WHEN 'low' THEN 1 WHEN 'moderate' THEN 2
    WHEN 'high' THEN 3 WHEN 'critical' THEN 4 ELSE -1 END;
$$;

CREATE OR REPLACE FUNCTION psi_classify_candidate(p_candidate_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  cur insight_fingerprints%ROWTYPE;
  prev insight_fingerprints%ROWTYPE;
  classification text;
  reasons jsonb := '[]'::jsonb;
BEGIN
  PERFORM psi_register_candidate_fingerprint(p_candidate_id);
  SELECT * INTO STRICT cur FROM insight_fingerprints WHERE candidate_id = p_candidate_id;
  SELECT * INTO prev
  FROM insight_fingerprints
  WHERE family_hash = cur.family_hash AND candidate_id <> p_candidate_id AND seq < cur.seq
  ORDER BY seq DESC LIMIT 1;

  IF NOT FOUND THEN
    classification := 'NEW';
    reasons := reasons || '"no_prior_family_member"'::jsonb;
  ELSIF psi_safety_rank(cur.safety_relevance) > psi_safety_rank(prev.safety_relevance)
        AND psi_safety_rank(cur.safety_relevance) >= 3 THEN
    classification := 'ESCALATION';
    reasons := reasons || '"safety_severity_increased"'::jsonb;
  ELSIF cur.direction IN ('up','down') AND prev.direction IN ('up','down') AND cur.direction <> prev.direction THEN
    classification := 'CONTRADICTION';
    reasons := reasons || '"direction_reversed"'::jsonb;
  ELSIF cur.interpretation_hash = prev.interpretation_hash
        AND cur.evidence_hash = prev.evidence_hash
        AND abs(cur.candidate_confidence - prev.candidate_confidence) < 0.000001 THEN
    classification := 'EXACT_DUPLICATE';
    reasons := reasons || '"same_interpretation_evidence_confidence"'::jsonb;
  ELSIF cur.interpretation_hash = prev.interpretation_hash
        AND abs(cur.candidate_confidence - prev.candidate_confidence) < 0.20 THEN
    classification := 'STATE_REFRESH';
    reasons := reasons || '"same_interpretation_updated_state"'::jsonb;
  ELSE
    classification := 'MATERIAL_REVISION';
    reasons := reasons || '"material_interpretation_or_confidence_change"'::jsonb;
  END IF;

  INSERT INTO redundancy_receipts(candidate_id, matched_candidate_id, classification, family_hash, reasons)
  VALUES (p_candidate_id, CASE WHEN prev.id IS NULL THEN NULL ELSE prev.candidate_id END, classification, cur.family_hash, reasons)
  ON CONFLICT (candidate_id) DO NOTHING;

  RETURN classification;
END;
$$;
