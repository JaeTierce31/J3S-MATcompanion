DO $$
DECLARE u uuid; i uuid; nac uuid; nad uuid; ex uuid; out_id uuid; before_count integer; after_count integer;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Collect baseline','Need more observations',0.40,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'COLLECT_MORE_DATA','advisory',0.7,0.8,'B2',0,true,'data_quality','collect baseline') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status,closure_state,user_response)
  VALUES (nad,'in_progress','{"observation_threshold_met":false}'::jsonb,'opened') RETURNING id INTO ex;
  SELECT count(*) INTO before_count FROM usefulness_events WHERE insight_id=i;
  BEGIN
    PERFORM psi_close_action(ex,'resolved',0.1,'[]'::jsonb,'[]'::jsonb);
    RAISE EXCEPTION 'collect-data action closed before observation threshold';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  SELECT count(*) INTO after_count FROM usefulness_events WHERE insight_id=i;
  IF after_count <> before_count THEN RAISE EXCEPTION 'learning emitted before closure'; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; nac uuid; nad uuid; ex uuid; out_id uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Collect baseline complete','Enough observations',0.55,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'COLLECT_MORE_DATA','advisory',0.7,0.8,'B2',0,true,'data_quality','collect baseline') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status,closure_state,user_response)
  VALUES (nad,'in_progress','{"observation_threshold_met":true}'::jsonb,'completed') RETURNING id INTO ex;
  SELECT psi_close_action(ex,'resolved',0.2,'["obs:threshold"]'::jsonb,'[]'::jsonb) INTO out_id;
  IF out_id IS NULL THEN RAISE EXCEPTION 'valid collect-data closure failed'; END IF;
END $$;

DO $$
DECLARE u uuid; i uuid; nac uuid; nad uuid; ex uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','experiment','Repeat experiment','Repeat required',0.50,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'REPEAT_EXPERIMENT','advisory',0.8,0.9,'B4',0,true,'confounder_control','repeat') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status,closure_state)
  VALUES (nad,'in_progress','{"experiment_state":"active"}'::jsonb) RETURNING id INTO ex;
  BEGIN
    PERFORM psi_close_action(ex,'resolved',0.2,'[]'::jsonb,'[]'::jsonb);
    RAISE EXCEPTION 'repeat experiment closed before analyzed/decision state';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  UPDATE action_executions SET closure_state='{"experiment_state":"analyzed"}'::jsonb WHERE id=ex;
  PERFORM psi_close_action(ex,'resolved',0.3,'["experiment:analyzed"]'::jsonb,'[]'::jsonb);
END $$;

DO $$
DECLARE u uuid; i uuid; nac uuid; nad uuid; ex uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'experiment_result','experiment','Decision needed','Awaiting user decision',0.70,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'RECORD_USER_DECISION','advisory',0.8,1,'B1',0,true,NULL,'record decision') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status,closure_state)
  VALUES (nad,'in_progress','{}'::jsonb) RETURNING id INTO ex;
  BEGIN
    PERFORM psi_close_action(ex,'resolved',0.2,'[]'::jsonb,'[]'::jsonb);
    RAISE EXCEPTION 'record-decision action closed without a decision ref';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END $$;

DO $$
DECLARE u uuid; i uuid; nac uuid; nad uuid; ex uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Invalid transition','Invalid closure',0.50,'advisory') RETURNING id INTO i;
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (i,'OBSERVE_ONLY','informational',0.1,0.1,'B0',0,true,NULL,'observe') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status,closure_state)
  VALUES (nad,'cancelled','{}'::jsonb) RETURNING id INTO ex;
  BEGIN
    PERFORM psi_close_action(ex,'resolved',0,'[]'::jsonb,'[]'::jsonb);
    RAISE EXCEPTION 'cancelled execution closed as resolved';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END $$;
