DO $$
DECLARE u uuid; i uuid; a uuid; atype text;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Weak baseline','Need more baseline',0.40,'advisory') RETURNING id INTO i;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES
    (i,'data_quality',0.30,'weak baseline'),(i,'population_match',0.80,'adequate');
  SELECT psi_select_next_action(i) INTO a;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=a;
  IF atype <> 'COLLECT_MORE_DATA' THEN RAISE EXCEPTION 'G-ACT-001 expected COLLECT_MORE_DATA, got %',atype; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; a uuid; atype text;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','claim','Population mismatch','Applicability uncertain',0.45,'advisory') RETURNING id INTO i;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES
    (i,'data_quality',0.90,'good'),(i,'population_match',0.30,'mismatch');
  SELECT psi_select_next_action(i) INTO a;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=a;
  IF atype <> 'REVIEW_EVIDENCE' THEN RAISE EXCEPTION 'G-ACT-002 expected REVIEW_EVIDENCE, got %',atype; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; a uuid; atype text;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'experiment_result','experiment','Experiment complete','Awaiting decision',0.70,'advisory') RETURNING id INTO i;
  SELECT psi_select_next_action(i) INTO a;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=a;
  IF atype <> 'RECORD_USER_DECISION' THEN RAISE EXCEPTION 'G-ACT-003 expected RECORD_USER_DECISION, got %',atype; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; a uuid; atype text;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'safety_attention','interaction','Safety','High-risk uncertainty',0.50,'reserved') RETURNING id INTO i;
  SELECT psi_select_next_action(i) INTO a;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=a;
  IF atype <> 'ESCALATE_TO_CLINICIAN' THEN RAISE EXCEPTION 'G-ACT-004 expected ESCALATE_TO_CLINICIAN, got %',atype; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; a uuid; atype text;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Resolved','No meaningful next step',0.90,'informational') RETURNING id INTO i;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES
    (i,'data_quality',0.90,'good'),(i,'population_match',0.90,'good'),(i,'scientific_certainty',0.90,'good');
  SELECT psi_select_next_action(i) INTO a;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=a;
  IF atype <> 'NO_ACTION' THEN RAISE EXCEPTION 'G-ACT-005 expected NO_ACTION, got %',atype; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; a1 uuid; a2 uuid; best uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Burden','Compare burden',0.50,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'COLLECT_MORE_DATA','advisory',0.70,0.70,'B2',0,true,'data_quality','lower burden') RETURNING id INTO a1;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'REPEAT_EXPERIMENT','advisory',0.70,0.70,'B4',0,true,'data_quality','higher burden') RETURNING id INTO a2;
  SELECT psi_choose_best_action(i) INTO best;
  IF best <> a1 THEN RAISE EXCEPTION 'G-ACT-006 lower burden should win'; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','medication','Reserved','Prescription boundary',0.50,'reserved') RETURNING id INTO i;
  BEGIN
    INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
    VALUES (i,'CHANGE_PRESCRIPTION','reserved',1,1,'B5',5,true,'safety','forbidden');
    RAISE EXCEPTION 'G-ACT-007 prescription change accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
