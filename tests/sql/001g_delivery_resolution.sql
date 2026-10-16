DO $$
DECLARE
  u uuid;
  i uuid;
  c1 uuid;
  c2 uuid;
  c3 uuid;
  first_delivery uuid;
  r text;
  resolution_id uuid;
  open_count integer;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'experiment_result','experiment','Resolution fixture','T1 delivery lifecycle',0.7,'advisory') RETURNING id INTO i;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,materialized_insight_id)
  VALUES (u,'experiment_result','experiment',gen_random_uuid(),'First T1','First T1','advisory',i) RETURNING id INTO c1;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c1,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c1,0);
  SELECT psi_delivery_decision(c1,'in_app',clock_timestamp()) INTO r;
  IF r <> 'DELIVER_NOW' THEN RAISE EXCEPTION 'first T1 should deliver, got %',r; END IF;
  SELECT id INTO first_delivery FROM delivery_events WHERE candidate_id=c1 ORDER BY delivered_at DESC LIMIT 1;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'experiment_result','experiment',gen_random_uuid(),'Second T1','Second T1','advisory') RETURNING id INTO c2;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c2,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c2,0);
  SELECT psi_delivery_decision(c2,'in_app',clock_timestamp()) INTO r;
  IF r <> 'BLOCKED' THEN RAISE EXCEPTION 'second T1 must be blocked while first active, got %',r; END IF;

  SELECT psi_resolve_delivery(first_delivery,'resolved','test',NULL) INTO resolution_id;
  IF resolution_id IS NULL THEN RAISE EXCEPTION 'resolution receipt missing'; END IF;
  SELECT count(*) INTO open_count FROM v_delivery_current_state WHERE user_id=u AND tier='T1' AND currently_active;
  IF open_count <> 0 THEN RAISE EXCEPTION 'resolved T1 still consumes active budget'; END IF;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'experiment_result','experiment',gen_random_uuid(),'Third T1','Third T1','advisory') RETURNING id INTO c3;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c3,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c3,0);
  SELECT psi_delivery_decision(c3,'in_app',clock_timestamp()) INTO r;
  IF r <> 'DELIVER_NOW' THEN RAISE EXCEPTION 'resolved first T1 must release budget, got %',r; END IF;
END $$;

DO $$
DECLARE
  u uuid;
  i uuid;
  c uuid;
  de uuid;
  nac uuid;
  nad uuid;
  ex uuid;
  outcome uuid;
  n integer;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Closure resolution','Closure resolution fixture',0.9,'informational') RETURNING id INTO i;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,materialized_insight_id)
  VALUES (u,'experiment_result','experiment',gen_random_uuid(),'Mapped T1','Mapped T1','advisory',i) RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c,0);
  PERFORM psi_delivery_decision(c,'in_app',clock_timestamp());
  SELECT id INTO de FROM delivery_events WHERE candidate_id=c ORDER BY delivered_at DESC LIMIT 1;

  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,rationale)
  VALUES (i,'NO_ACTION','informational',0,0,'B0',0,true,'fixture') RETURNING id INTO nac;
  INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version)
  VALUES (i,nac,'fixture','001G-R1') RETURNING id INTO nad;
  INSERT INTO action_executions(decision_id,status)
  VALUES (nad,'in_progress') RETURNING id INTO ex;
  SELECT psi_close_action(ex,'no_action',0,'[]'::jsonb,'[]'::jsonb) INTO outcome;
  IF outcome IS NULL THEN RAISE EXCEPTION 'action outcome missing'; END IF;
  SELECT count(*) INTO n FROM delivery_resolution_events WHERE delivery_event_id=de AND related_action_outcome_id=outcome;
  IF n <> 1 THEN RAISE EXCEPTION 'action closure did not resolve active delivery'; END IF;
END $$;
