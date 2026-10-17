-- PSI-CIM-001D — Longitudinal Intelligence Plane
-- Canonical additive migration over PSI-CIM-001C.
-- Focus: immutable rollups, adaptive N-of-1 analytics, auth-bound API reads,
-- claim applicability matrices, and recommendation lineage.

BEGIN;

CREATE TABLE IF NOT EXISTS observation_daily_rollups (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  metric text NOT NULL,
  day date NOT NULL,
  n bigint NOT NULL CHECK(n>=0),
  avg_value numeric,
  min_value numeric,
  max_value numeric,
  stddev_value numeric,
  first_value numeric,
  last_value numeric,
  first_observed_at timestamptz,
  last_observed_at timestamptz,
  source_mix jsonb NOT NULL DEFAULT '{}'::jsonb,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,metric,day)
);
CREATE INDEX IF NOT EXISTS idx_daily_rollups_user_metric_day
  ON observation_daily_rollups(user_id,metric,day DESC);

CREATE TABLE IF NOT EXISTS observation_weekly_rollups (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  metric text NOT NULL,
  week_start date NOT NULL,
  n bigint NOT NULL CHECK(n>=0),
  avg_value numeric,
  min_value numeric,
  max_value numeric,
  stddev_value numeric,
  first_value numeric,
  last_value numeric,
  first_observed_at timestamptz,
  last_observed_at timestamptz,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,metric,week_start)
);
CREATE INDEX IF NOT EXISTS idx_weekly_rollups_user_metric_week
  ON observation_weekly_rollups(user_id,metric,week_start DESC);

CREATE TABLE IF NOT EXISTS experiment_protocols (
  experiment_id uuid PRIMARY KEY REFERENCES experiments(id) ON DELETE CASCADE,
  min_baseline_days integer NOT NULL DEFAULT 7 CHECK(min_baseline_days>=0),
  min_baseline_observations integer NOT NULL DEFAULT 5 CHECK(min_baseline_observations>=1),
  min_intervention_observations integer NOT NULL DEFAULT 5 CHECK(min_intervention_observations>=1),
  washout_days integer NOT NULL DEFAULT 0 CHECK(washout_days>=0),
  max_confounder_score numeric NOT NULL DEFAULT 0.35 CHECK(max_confounder_score BETWEEN 0 AND 1),
  adherence_floor numeric NOT NULL DEFAULT 0.80 CHECK(adherence_floor BETWEEN 0 AND 1),
  stopping_rules jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS experiment_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  experiment_id uuid NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
  checkin_day date NOT NULL,
  adherence numeric NOT NULL CHECK(adherence BETWEEN 0 AND 1),
  confounder_score numeric NOT NULL DEFAULT 0 CHECK(confounder_score BETWEEN 0 AND 1),
  adverse_event boolean NOT NULL DEFAULT false,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(experiment_id,checkin_day)
);

CREATE TABLE IF NOT EXISTS claim_applicability_matrices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id uuid NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
  study_id uuid NOT NULL REFERENCES studies(id) ON DELETE CASCADE,
  dimension text NOT NULL CHECK(dimension IN ('population','dose','formulation','endpoint')),
  applicability text NOT NULL CHECK(applicability IN ('direct','partial','indirect','unknown','not_applicable')),
  rationale text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(claim_id,study_id,dimension)
);
CREATE INDEX IF NOT EXISTS idx_claim_applicability_claim
  ON claim_applicability_matrices(claim_id,dimension);

CREATE TABLE IF NOT EXISTS terminology_resolution_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  vocabulary text NOT NULL,
  requested_label text NOT NULL,
  status text NOT NULL CHECK(status IN ('unresolved','candidate','verified','no_exact_concept','deprecated')),
  reason text,
  checked_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(entity_type,entity_id,vocabulary)
);

CREATE TABLE IF NOT EXISTS user_auth_identities (
  auth_provider text NOT NULL,
  auth_subject text NOT NULL,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(auth_provider,auth_subject),
  UNIQUE(user_id,auth_provider)
);

CREATE OR REPLACE VIEW v_experiment_temporal_analytics
WITH (security_invoker=true) AS
SELECT e.id experiment_id,e.user_id,e.hypothesis,e.status,e.primary_metric,
       coalesce(avg(c.adherence),1.0) adherence_score,
       coalesce(avg(c.confounder_score),0.0) mean_confounder_score,
       bool_or(coalesce(c.adverse_event,false)) adverse_event_seen,
       count(c.id) checkin_count
FROM experiments e
LEFT JOIN experiment_checkins c ON c.experiment_id=e.id
GROUP BY e.id,e.user_id,e.hypothesis,e.status,e.primary_metric;

CREATE OR REPLACE VIEW v_user_metric_daily WITH (security_invoker=true) AS
SELECT user_id,metric,day,n,avg_value,min_value,max_value,stddev_value,
       first_value,last_value,last_observed_at
FROM observation_daily_rollups;

CREATE OR REPLACE VIEW v_user_metric_weekly WITH (security_invoker=true) AS
SELECT user_id,metric,week_start,n,avg_value,min_value,max_value,stddev_value,
       first_value,last_value,last_observed_at
FROM observation_weekly_rollups;

CREATE OR REPLACE VIEW v_personalized_knowledge_graph
WITH (security_invoker=true) AS
SELECT subject_type,subject_id,predicate,object_type,object_id,
       confidence,provenance_source_id,valid_from,valid_to
FROM knowledge_edges;

-- User-scoped API identity is resolved from the verified Neon Auth JWT session.
CREATE OR REPLACE FUNCTION psi_current_user_from_auth()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
DECLARE
  sub text;
  uid uuid;
BEGIN
  sub := auth.user_id();
  IF sub IS NULL OR sub='' THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT user_id INTO uid
  FROM user_auth_identities
  WHERE auth_provider='neon_auth'
    AND auth_subject=sub
    AND active;

  IF uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_SUBJECT_UNMAPPED';
  END IF;

  RETURN uid;
END $$;

REVOKE ALL ON user_auth_identities FROM PUBLIC;
REVOKE ALL ON user_auth_identities FROM psi_dashboard_reader;
REVOKE ALL ON FUNCTION psi_current_user_from_auth() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION psi_current_user_from_auth() TO psi_dashboard_reader;

COMMIT;
