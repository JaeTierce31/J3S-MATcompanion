CREATE TABLE IF NOT EXISTS psi_orchestration_policy (
  policy_version text PRIMARY KEY,
  adaptive_min numeric NOT NULL,
  adaptive_max numeric NOT NULL,
  behavioral_decay_days integer NOT NULL,
  t1_active_limit integer NOT NULL,
  t2_visible_limit integer NOT NULL,
  active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT psi_orchestration_policy_bounds CHECK (
    adaptive_min <= adaptive_max
    AND adaptive_min >= -1
    AND adaptive_max <= 1
    AND behavioral_decay_days > 0
    AND t1_active_limit > 0
    AND t2_visible_limit > 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS psi_one_active_orchestration_policy
  ON psi_orchestration_policy ((active)) WHERE active;

INSERT INTO psi_orchestration_policy (
  policy_version, adaptive_min, adaptive_max, behavioral_decay_days,
  t1_active_limit, t2_visible_limit, active
)
VALUES ('001G-R1', -0.15, 0.15, 45, 1, 3, true)
ON CONFLICT (policy_version) DO UPDATE SET
  adaptive_min = EXCLUDED.adaptive_min,
  adaptive_max = EXCLUDED.adaptive_max,
  behavioral_decay_days = EXCLUDED.behavioral_decay_days,
  t1_active_limit = EXCLUDED.t1_active_limit,
  t2_visible_limit = EXCLUDED.t2_visible_limit,
  active = EXCLUDED.active;

CREATE OR REPLACE FUNCTION psi_active_orchestration_policy()
RETURNS SETOF psi_orchestration_policy
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n FROM psi_orchestration_policy WHERE active;
  IF n <> 1 THEN
    RAISE EXCEPTION 'expected exactly one active orchestration policy, found %', n;
  END IF;
  RETURN QUERY SELECT * FROM psi_orchestration_policy WHERE active;
END;
$$;
