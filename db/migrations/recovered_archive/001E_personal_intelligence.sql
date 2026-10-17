-- PSI-CIM-001E — Personal Intelligence & Decision Plane
BEGIN;

CREATE TABLE IF NOT EXISTS personal_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  insight_type text NOT NULL CHECK (insight_type IN (
    'change_detected','experiment_result','evidence_context',
    'safety_attention','uncertainty','next_attention'
  )),
  subject_type text NOT NULL,
  subject_id uuid,
  title text NOT NULL,
  summary text NOT NULL,
  confidence numeric NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  authority_class text NOT NULL CHECK (authority_class IN ('informational','advisory','reserved')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','dismissed','superseded','resolved')),
  generated_at timestamptz NOT NULL DEFAULT now(),
  supersedes_insight_id uuid REFERENCES personal_insights(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_personal_insights_user_status
  ON personal_insights(user_id,status,generated_at DESC);

CREATE TABLE IF NOT EXISTS insight_confidence_components (
  insight_id uuid NOT NULL REFERENCES personal_insights(id) ON DELETE CASCADE,
  component text NOT NULL CHECK (component IN (
    'data_quality','temporal_alignment','protocol_adherence','confounder_control',
    'scientific_certainty','population_match','dose_match','formulation_match','endpoint_match'
  )),
  score numeric NOT NULL CHECK (score BETWEEN 0 AND 1),
  rationale text,
  PRIMARY KEY(insight_id,component)
);

CREATE TABLE IF NOT EXISTS insight_evidence_links (
  insight_id uuid NOT NULL REFERENCES personal_insights(id) ON DELETE CASCADE,
  evidence_type text NOT NULL CHECK (evidence_type IN (
    'claim','study','outcome','observation_set','interaction',
    'decision','goal','pathway','ingredient','experiment'
  )),
  evidence_id uuid NOT NULL,
  relation text NOT NULL,
  PRIMARY KEY(insight_id,evidence_type,evidence_id,relation)
);

CREATE TABLE IF NOT EXISTS attention_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_insight_id uuid REFERENCES personal_insights(id) ON DELETE SET NULL,
  category text NOT NULL CHECK(category IN (
    'safety','experiment','data_quality','evidence_gap','redundancy','follow_up','goal_progress'
  )),
  priority smallint NOT NULL CHECK(priority BETWEEN 1 AND 5),
  title text NOT NULL,
  reason text NOT NULL,
  recommended_action text NOT NULL,
  authority_class text NOT NULL CHECK(authority_class IN ('informational','advisory','reserved')),
  status text NOT NULL DEFAULT 'open'
    CHECK(status IN ('open','acknowledged','resolved','dismissed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_attention_user_priority
  ON attention_items(user_id,status,priority DESC,created_at DESC);

CREATE OR REPLACE FUNCTION psi_insight_confidence(
  p_data numeric,
  p_temporal numeric,
  p_adherence numeric,
  p_confounder_control numeric,
  p_science numeric,
  p_population numeric,
  p_dose numeric,
  p_formulation numeric,
  p_endpoint numeric
) RETURNS numeric
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT LEAST(1,GREATEST(0,
    sqrt(GREATEST(0,p_data*p_temporal*p_adherence*p_confounder_control))
    *
    sqrt(GREATEST(0,p_science*p_population*p_dose*p_formulation*p_endpoint))
  ));
$$;

CREATE OR REPLACE FUNCTION psi_authority_guard(p_authority text,p_action text)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT CASE
    WHEN p_authority='reserved' THEN 'REQUIRES_USER_OR_CLINICIAN'
    WHEN p_authority='advisory' THEN 'PRESENT_FOR_USER_DECISION'
    ELSE 'INFORMATIONAL_ONLY'
  END;
$$;

CREATE OR REPLACE VIEW v_user_insight_feed WITH (security_invoker=true) AS
SELECT
  i.id,
  i.user_id,
  i.insight_type,
  i.title,
  i.summary,
  i.confidence,
  i.authority_class,
  i.status,
  i.generated_at,
  COALESCE(
    jsonb_agg(
      DISTINCT jsonb_build_object(
        'component',c.component,
        'score',c.score,
        'rationale',c.rationale
      )
    ) FILTER (WHERE c.component IS NOT NULL),
    '[]'::jsonb
  ) AS confidence_breakdown
FROM personal_insights i
LEFT JOIN insight_confidence_components c ON c.insight_id=i.id
GROUP BY i.id;

CREATE OR REPLACE VIEW v_user_attention_queue WITH (security_invoker=true) AS
SELECT
  id,user_id,category,priority,title,reason,recommended_action,
  authority_class,status,created_at
FROM attention_items;

CREATE OR REPLACE FUNCTION api_dashboard_insights()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
  SELECT COALESCE(
    jsonb_agg(to_jsonb(v) ORDER BY v.generated_at DESC),
    '[]'::jsonb
  )
  FROM v_user_insight_feed v
  WHERE v.user_id=psi_current_user_from_auth()
    AND v.status='active'
$$;

CREATE OR REPLACE FUNCTION api_dashboard_attention()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
  SELECT COALESCE(
    jsonb_agg(to_jsonb(v) ORDER BY v.priority DESC,v.created_at DESC),
    '[]'::jsonb
  )
  FROM v_user_attention_queue v
  WHERE v.user_id=psi_current_user_from_auth()
    AND v.status='open'
$$;

REVOKE ALL ON personal_insights,insight_confidence_components,
  insight_evidence_links,attention_items FROM psi_dashboard_reader;

REVOKE SELECT ON v_user_insight_feed,v_user_attention_queue
  FROM psi_dashboard_reader;

REVOKE ALL ON FUNCTION api_dashboard_insights(),api_dashboard_attention() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api_dashboard_insights(),api_dashboard_attention()
  TO psi_dashboard_reader;

COMMIT;
