DO $$
DECLARE c0 uuid; c1 uuid; c2 uuid; c3 uuid; t text; r0 numeric; r1 numeric; r3 numeric;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','safety_attention','interaction','00000000-0000-0000-0000-000000000401','Safety','High safety','reserved','high') RETURNING id INTO c0;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c0,'ESCALATE','bypassed','reserved','high','001G-R1');
  SELECT psi_priority_tier(c0) INTO t;
  IF t <> 'T0' THEN RAISE EXCEPTION 'safety must be T0, got %',t; END IF;
  SELECT psi_rank_candidate(c0,-999) INTO r0;
  IF r0 < 399.85 OR r0 > 400.15 THEN RAISE EXCEPTION 'T0 adaptive bound violated: %',r0; END IF;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000001','experiment_result','experiment','00000000-0000-0000-0000-000000000402','Experiment','Completed','advisory') RETURNING id INTO c1;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c1,'ELIGIBLE','none','advisory','none','001G-R1');
  IF psi_priority_tier(c1) <> 'T1' THEN RAISE EXCEPTION 'experiment result must be T1'; END IF;
  SELECT psi_rank_candidate(c1,0.99) INTO r1;
  IF r1 <> 300.15 THEN RAISE EXCEPTION 'positive adaptive clamp expected 300.15, got %',r1; END IF;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000001','optimization','metric','00000000-0000-0000-0000-000000000403','Optimization','Optimization','advisory') RETURNING id INTO c2;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c2,'ELIGIBLE','none','advisory','none','001G-R1');
  IF psi_priority_tier(c2) <> 'T2' THEN RAISE EXCEPTION 'optimization must be T2'; END IF;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000001','evidence_context','claim','00000000-0000-0000-0000-000000000404','Research','Background','informational') RETURNING id INTO c3;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c3,'ELIGIBLE','none','informational','none','001G-R1');
  IF psi_priority_tier(c3) <> 'T3' THEN RAISE EXCEPTION 'research must be T3'; END IF;
  SELECT psi_rank_candidate(c3,0.15) INTO r3;
  IF r3 >= r1 THEN RAISE EXCEPTION 'T3 must not outrank T1'; END IF;
END $$;

DO $$
DECLARE c uuid;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000001','unknown_type','metric','00000000-0000-0000-0000-000000000405','Unknown','Unknown','informational') RETURNING id INTO c;
  BEGIN
    PERFORM psi_priority_tier(c);
    RAISE EXCEPTION 'unknown candidate type accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;
