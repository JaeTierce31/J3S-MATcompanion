DO $$
DECLARE
  p record;
BEGIN
  SELECT * INTO p FROM psi_active_orchestration_policy();
  IF p.policy_version <> '001G-R1' THEN RAISE EXCEPTION 'policy_version mismatch: %', p.policy_version; END IF;
  IF p.adaptive_min <> -0.15 THEN RAISE EXCEPTION 'adaptive_min mismatch: %', p.adaptive_min; END IF;
  IF p.adaptive_max <> 0.15 THEN RAISE EXCEPTION 'adaptive_max mismatch: %', p.adaptive_max; END IF;
  IF p.t1_active_limit <> 1 THEN RAISE EXCEPTION 't1_active_limit mismatch: %', p.t1_active_limit; END IF;
  IF p.t2_visible_limit <> 3 THEN RAISE EXCEPTION 't2_visible_limit mismatch: %', p.t2_visible_limit; END IF;
  IF p.behavioral_decay_days <= 0 THEN RAISE EXCEPTION 'behavioral_decay_days must be positive'; END IF;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO psi_orchestration_policy(policy_version, adaptive_min, adaptive_max, behavioral_decay_days, t1_active_limit, t2_visible_limit, active)
    VALUES ('bad-bounds', 0.20, 0.10, 30, 1, 3, false);
    RAISE EXCEPTION 'invalid adaptive bounds accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
