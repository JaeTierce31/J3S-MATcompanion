DO $$
DECLARE
  uid uuid := '00000000-0000-0000-0000-000000000001';
  sid uuid;
  result text;
BEGIN
  INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
  VALUES (uid, 'METRIC_SHIFT', 'metric', '00000000-0000-0000-0000-000000000101', '{}'::jsonb, '{}'::jsonb, 0.03, 'up', 0.80, 1, 0.10, 'low', '["obs:1"]'::jsonb)
  RETURNING id INTO sid;
  SELECT psi_evaluate_materiality(sid) INTO result;
  IF result <> 'BELOW_THRESHOLD' THEN RAISE EXCEPTION 'G-MAT-001 expected BELOW_THRESHOLD, got %', result; END IF;
END $$;

DO $$
DECLARE sid uuid; result text;
BEGIN
  INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001', 'METRIC_SHIFT', 'metric', '00000000-0000-0000-0000-000000000102', '{}'::jsonb, '{}'::jsonb, 0.30, 'down', 0.80, 3, 0.60, 'low', '["obs:2","obs:3"]'::jsonb)
  RETURNING id INTO sid;
  SELECT psi_evaluate_materiality(sid) INTO result;
  IF result <> 'MATERIAL' THEN RAISE EXCEPTION 'G-MAT-002 expected MATERIAL, got %', result; END IF;
END $$;

DO $$
DECLARE sid uuid; result text;
BEGIN
  INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001', 'SAFETY_CHANGE', 'interaction', '00000000-0000-0000-0000-000000000103', '{}'::jsonb, '{"severity":"high"}'::jsonb, 0, 'none', 0.40, 1, 0.20, 'high', '["interaction:1"]'::jsonb)
  RETURNING id INTO sid;
  SELECT psi_evaluate_materiality(sid) INTO result;
  IF result <> 'SAFETY_OVERRIDE' THEN RAISE EXCEPTION 'G-MAT-003 expected SAFETY_OVERRIDE, got %', result; END IF;
END $$;

DO $$
DECLARE sid uuid; result text;
BEGIN
  INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001', 'EXPERIMENT_PHASE_CHANGE', 'experiment', '00000000-0000-0000-0000-000000000104', '{"phase":"active"}'::jsonb, '{"phase":"completed"}'::jsonb, 0, 'none', 0.70, 1, 0.50, 'low', '["experiment:1"]'::jsonb)
  RETURNING id INTO sid;
  SELECT psi_evaluate_materiality(sid) INTO result;
  IF result <> 'MATERIAL' THEN RAISE EXCEPTION 'G-MAT-004 expected MATERIAL, got %', result; END IF;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
    VALUES ('00000000-0000-0000-0000-000000000001', 'NOT_A_SIGNAL', 'metric', '00000000-0000-0000-0000-000000000105', '{}'::jsonb, '{}'::jsonb, 0, 'none', 0.5, 1, 0, 'low', '["x"]'::jsonb);
    RAISE EXCEPTION 'malformed signal type accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO change_signals(user_id, signal_type, subject_type, subject_id, previous_state, current_state, magnitude, direction, confidence, persistence, novelty, safety_relevance, source_refs)
    VALUES ('00000000-0000-0000-0000-000000000001', 'METRIC_SHIFT', 'metric', '00000000-0000-0000-0000-000000000106', '{}'::jsonb, '{}'::jsonb, 0, 'none', 0.5, 1, 0, 'low', '[]'::jsonb);
    RAISE EXCEPTION 'empty source_refs accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
