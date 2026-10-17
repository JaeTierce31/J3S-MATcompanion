DO $$
DECLARE c1 uuid; c2 uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000011','experiment_result','experiment','00000000-0000-0000-0000-000000000501','Exp1','Completed','advisory') RETURNING id INTO c1;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c1,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c1,0);
  SELECT psi_delivery_decision(c1,'in_app',now()) INTO r;
  IF r <> 'DELIVER_NOW' THEN RAISE EXCEPTION 'first T1 should deliver now, got %',r; END IF;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000011','experiment_result','experiment','00000000-0000-0000-0000-000000000502','Exp2','Completed','advisory') RETURNING id INTO c2;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c2,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c2,0);
  SELECT psi_delivery_decision(c2,'in_app',now()) INTO r;
  IF r <> 'BLOCKED' THEN RAISE EXCEPTION 'second active T1 must block, got %',r; END IF;
END $$;

DO $$
DECLARE c uuid; r text; i integer;
BEGIN
  FOR i IN 1..4 LOOP
    INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
    VALUES ('00000000-0000-0000-0000-000000000012','optimization','metric',('00000000-0000-0000-0000-'||lpad((600+i)::text,12,'0'))::uuid,'Opt','Optimization','advisory') RETURNING id INTO c;
    INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c,'ELIGIBLE','none','advisory','none','001G-R1');
    PERFORM psi_rank_candidate(c,0);
    SELECT psi_delivery_decision(c,'in_app',now()) INTO r;
    IF i <= 3 AND r <> 'DELIVER_IN_APP' THEN RAISE EXCEPTION 'T2 item % should be visible, got %',i,r; END IF;
    IF i = 4 AND r <> 'COLLAPSE' THEN RAISE EXCEPTION 'fourth T2 should collapse, got %',r; END IF;
  END LOOP;
END $$;

DO $$
DECLARE c uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES ('00000000-0000-0000-0000-000000000013','evidence_context','claim','00000000-0000-0000-0000-000000000701','Research','Background','informational') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c,'ELIGIBLE','none','informational','none','001G-R1');
  PERFORM psi_rank_candidate(c,0);
  SELECT psi_delivery_decision(c,'notification',now()) INTO r;
  IF r <> 'DEFER_DIGEST' THEN RAISE EXCEPTION 'T3 notification should defer to digest, got %',r; END IF;
END $$;

DO $$
DECLARE c uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000014','safety_attention','interaction','00000000-0000-0000-0000-000000000801','Safety','Critical','reserved','critical') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c,'ESCALATE','bypassed','reserved','critical','001G-R1');
  PERFORM psi_rank_candidate(c,0);
  SELECT psi_delivery_decision(c,'notification',now()) INTO r;
  IF r <> 'DELIVER_NOW' THEN RAISE EXCEPTION 'T0 must bypass budget, got %',r; END IF;
END $$;
