DO $$
DECLARE u uuid; c uuid; score numeric; failures integer;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,context_key)
  VALUES (u,'optimization','metric','00000000-0000-0000-0000-000000001101','Fallback','Neutral fallback','advisory','degraded-neutral') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c,'ELIGIBLE','none','advisory','none','001G-R1');
  SELECT psi_rank_candidate_safe(c) INTO score;
  IF score <> 200 THEN RAISE EXCEPTION 'neutral degraded-safe rank expected 200, got %',score; END IF;
  SELECT count(*) INTO failures FROM orchestration_runtime_events WHERE candidate_id=c AND event_type='adaptive_failure';
  IF failures <> 0 THEN RAISE EXCEPTION 'neutral/no-preference path should not emit failure'; END IF;
END $$;

DO $$
DECLARE u uuid; c uuid; score numeric; failures integer; v uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  v := gen_random_uuid();
  INSERT INTO preference_state_versions(id,user_id,dimension,explicit_value,behavioral_value,source_kind,source_mix,confidence,effective_at,decay_policy,version)
  VALUES (v,u,'experiment_action_affinity',0,0.5,'behavioral','{}',0.5,now(),'behavioral_half_life_days:45','invalid-version:'||v::text);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,context_key)
  VALUES (u,'optimization','metric','00000000-0000-0000-0000-000000001102','Fallback','Invalid preference version','advisory','degraded-invalid') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c,'ELIGIBLE','none','advisory','none','001G-R1');
  SELECT psi_rank_candidate_safe(c) INTO score;
  IF score <> 200 THEN RAISE EXCEPTION 'adaptive failure must fall back to neutral 200, got %',score; END IF;
  SELECT count(*) INTO failures FROM orchestration_runtime_events WHERE candidate_id=c AND event_type='adaptive_failure' AND fallback_mode='deterministic_tier_neutral_preference';
  IF failures <> 1 THEN RAISE EXCEPTION 'adaptive failure receipt missing'; END IF;
END $$;

DO $$
DECLARE u uuid; c uuid; score numeric;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,safety_relevance,context_key)
  VALUES (u,'safety_attention','interaction','00000000-0000-0000-0000-000000001103','Safety fallback','Critical safety','reserved','critical','degraded-safety') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c,'ESCALATE','bypassed','reserved','critical','001G-R1');
  SELECT psi_rank_candidate_safe(c) INTO score;
  IF score < 399.85 THEN RAISE EXCEPTION 'T0 safety degraded below hard tier: %',score; END IF;
END $$;

DO $$
DECLARE u uuid; c uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'unknown_type','metric','00000000-0000-0000-0000-000000001104','Unknown','Must fail hard','informational') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c,'ELIGIBLE','none','informational','none','001G-R1');
  BEGIN
    PERFORM psi_rank_candidate_safe(c);
    RAISE EXCEPTION 'deterministic tier error was swallowed';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;
