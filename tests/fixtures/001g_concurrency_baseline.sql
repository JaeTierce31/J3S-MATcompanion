CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Minimal pre-001G dependency shapes required to apply the real 001G migration chain.
-- This fixture contains no copied 001G orchestration logic.
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE personal_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  insight_type text NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid,
  title text NOT NULL,
  summary text NOT NULL,
  confidence numeric NOT NULL DEFAULT 0.5,
  authority_class text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  generated_at timestamptz NOT NULL DEFAULT now(),
  supersedes_insight_id uuid REFERENCES personal_insights(id)
);

CREATE TABLE insight_confidence_components (
  insight_id uuid NOT NULL REFERENCES personal_insights(id) ON DELETE CASCADE,
  component text NOT NULL,
  score numeric NOT NULL,
  rationale text,
  PRIMARY KEY(insight_id,component)
);

CREATE TABLE decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id),
  action text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE interactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  severity text NOT NULL DEFAULT 'unknown',
  confidence numeric NOT NULL DEFAULT 0.5
);

CREATE OR REPLACE FUNCTION psi_current_user_from_auth()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT NULL::uuid $$;
