CREATE TEMP TABLE IF NOT EXISTS invariant_results(id text PRIMARY KEY);
TRUNCATE invariant_results;

-- INV-G-001 through INV-G-004, INV-G-013, INV-G-020
DO $$
DECLARE
  u uuid; pi uuid; s uuid; c uuid; inter uuid;
  a_type text; a_id uuid; b_type text; b_id uuid;
  elig_before text; elig_after text;
  conf_before numeric; conf_after numeric;
  auth_before text; auth_after text;
  sev_before text; sev_after text;
  before_learning integer; after_learning integer;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Invariant learning','Learning boundary fixture',0.60,'advisory') RETURNING id INTO pi;

  SELECT entity_type,entity_id INTO a_type,a_id FROM entity_registry ORDER BY entity_type,entity_id LIMIT 1;
  SELECT entity_type,entity_id INTO b_type,b_id FROM entity_registry WHERE (entity_type,entity_id)<>(a_type,a_id) ORDER BY entity_type,entity_id LIMIT 1;
  INSERT INTO interactions(actor_a_type,actor_a_id,actor_b_type,actor_b_id,interaction_type,severity,confidence)
  VALUES (a_type,a_id,b_type,b_id,'additive_effect','moderate',0.50) RETURNING id INTO inter;

  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002001',0.01,'down',0.80,3,0.20,'low','["inv:1"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002001','Below threshold','Below threshold','advisory','down',0.60,'inv-learning','low',s,pi) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  SELECT psi_evaluate_eligibility(c,now()) INTO elig_before;
  SELECT confidence,authority_class INTO conf_before,auth_before FROM personal_insights WHERE id=pi;
  SELECT severity INTO sev_before FROM interactions WHERE id=inter;

  PERFORM psi_record_usefulness_event(u,pi,'HELPFUL','invariant_fixture',now());

  SELECT decision INTO elig_after FROM eligibility_decisions WHERE candidate_id=c ORDER BY evaluated_at DESC LIMIT 1;
  SELECT confidence,authority_class INTO conf_after,auth_after FROM personal_insights WHERE id=pi;
  SELECT severity INTO sev_after FROM interactions WHERE id=inter;

  IF elig_before <> 'SUPPRESS_LOW_VALUE' OR elig_after <> elig_before THEN RAISE EXCEPTION 'INV-G-001 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-001');
  IF conf_after IS DISTINCT FROM conf_before THEN RAISE EXCEPTION 'INV-G-002 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-002');
  IF sev_after IS DISTINCT FROM sev_before THEN RAISE EXCEPTION 'INV-G-003 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-003');
  IF auth_after IS DISTINCT FROM auth_before THEN RAISE EXCEPTION 'INV-G-004 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-004');

  BEGIN
    PERFORM psi_record_usefulness_event(u,pi,'DWELL_TIME','telemetry',now());
    RAISE EXCEPTION 'INV-G-013 failed: dwell accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  INSERT INTO invariant_results VALUES ('INV-G-013');

  SELECT count(*) INTO before_learning FROM usefulness_events WHERE insight_id=pi;
  BEGIN
    PERFORM psi_record_usefulness_event(u,pi,'UNOBSERVED_INTERNAL_EVENT','internal',now());
    RAISE EXCEPTION 'INV-G-020 failed: unobserved signal accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  SELECT count(*) INTO after_learning FROM usefulness_events WHERE insight_id=pi;
  IF after_learning <> before_learning THEN RAISE EXCEPTION 'INV-G-020 failed: learning changed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-020');
END $$;

-- INV-G-005, INV-G-006, INV-G-010
DO $$
DECLARE u uuid; s uuid; c uuid; r text; mat text;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,current_state,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'SAFETY_CHANGE','interaction','00000000-0000-0000-0000-000000002005','{"severity":"critical"}',0,'none',0.4,1,0.2,'critical','["inv:safety"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'safety_attention','interaction','00000000-0000-0000-0000-000000002005','Critical','Critical safety','reserved','none',0.5,'inv-critical','critical',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at) VALUES (u,'safety',now());
  INSERT INTO user_topic_suppression(user_id,context_key,muted) VALUES (u,'inv-critical',true);
  SELECT psi_evaluate_eligibility(c,now()) INTO r;
  IF r <> 'ESCALATE' THEN RAISE EXCEPTION 'INV-G-005/006 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-005');
  INSERT INTO invariant_results VALUES ('INV-G-006');

  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002010',0.35,'down',0.8,3,0.6,'low','["inv:cooldown"]') RETURNING id INTO s;
  SELECT psi_evaluate_materiality(s) INTO mat;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002010','Trend','Material but cooldown','advisory','down',0.7,'inv-cooldown','low',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at) VALUES (u,'personal_trend',now()) ON CONFLICT (user_id,cooldown_family) DO UPDATE SET last_delivered_at=excluded.last_delivered_at;
  SELECT psi_evaluate_eligibility(c,now()) INTO r;
  IF mat <> 'MATERIAL' OR r <> 'DEFER_COOLDOWN' THEN RAISE EXCEPTION 'INV-G-010 failed: materiality %, eligibility %',mat,r; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-010');
END $$;

-- INV-G-007, INV-G-008, INV-G-009, INV-G-014
DO $$
DECLARE u uuid; s uuid; c1 uuid; c2 uuid; c3 uuid; r text; cls text; matched uuid; reasons jsonb;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002020',0.35,'down',0.8,3,0.6,'low','["inv:dup"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002020','Trend','Same','advisory','down',0.6,'inv-family','low',s) RETURNING id INTO c1;
  PERFORM psi_classify_candidate(c1);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  SELECT user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id FROM insight_candidates WHERE id=c1 RETURNING id INTO c2;
  SELECT psi_classify_candidate(c2) INTO cls;
  SELECT psi_evaluate_eligibility(c2,now()) INTO r;
  SELECT reasons INTO reasons FROM eligibility_decisions WHERE candidate_id=c2 ORDER BY evaluated_at DESC LIMIT 1;
  IF cls <> 'EXACT_DUPLICATE' OR r <> 'SUPPRESS_DUPLICATE' THEN RAISE EXCEPTION 'INV-G-007 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-007');
  IF jsonb_array_length(reasons)=0 THEN RAISE EXCEPTION 'INV-G-014 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-014');

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002020','Trend','Opposite','advisory','up',0.6,'inv-family','low',s) RETURNING id INTO c3;
  SELECT psi_classify_candidate(c3) INTO cls;
  SELECT matched_candidate_id INTO matched FROM redundancy_receipts WHERE candidate_id=c3;
  SELECT psi_evaluate_eligibility(c3,now()) INTO r;
  IF cls <> 'CONTRADICTION' OR r <> 'SUPERSEDE_EXISTING' THEN RAISE EXCEPTION 'INV-G-008 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-008');
  IF matched IS NULL THEN RAISE EXCEPTION 'INV-G-009 failed: no prior lineage'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-009');
END $$;

-- INV-G-011, INV-G-012, INV-G-015
DO $$
DECLARE u uuid; c2 uuid; c1 uuid; c3 uuid; r2 numeric; r1 numeric; r3 numeric; adj numeric; de_priority uuid;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'optimization','metric','00000000-0000-0000-0000-000000002030','Opt','Opt','advisory') RETURNING id INTO c2;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c2,'ELIGIBLE','none','advisory','none','001G-R1');
  SELECT psi_rank_candidate(c2,999) INTO r2;
  SELECT adaptive_adjustment INTO adj FROM priority_decisions WHERE candidate_id=c2 ORDER BY decided_at DESC LIMIT 1;
  IF adj <> 0.15 THEN RAISE EXCEPTION 'INV-G-011 failed: %',adj; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-011');

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'experiment_result','experiment','00000000-0000-0000-0000-000000002031','T1','T1','advisory') RETURNING id INTO c1;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c1,'ELIGIBLE','none','advisory','none','001G-R1');
  SELECT psi_rank_candidate(c1,-0.15) INTO r1;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'evidence_context','claim','00000000-0000-0000-0000-000000002032','T3','T3','informational') RETURNING id INTO c3;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c3,'ELIGIBLE','none','informational','none','001G-R1');
  SELECT psi_rank_candidate(c3,0.15) INTO r3;
  IF r1 <= r3 THEN RAISE EXCEPTION 'INV-G-012 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-012');

  PERFORM psi_delivery_decision(c2,'in_app',now());
  SELECT priority_decision_id INTO de_priority FROM delivery_events WHERE candidate_id=c2 ORDER BY delivered_at DESC LIMIT 1;
  IF de_priority IS NULL OR NOT EXISTS (SELECT 1 FROM priority_decisions WHERE id=de_priority) THEN RAISE EXCEPTION 'INV-G-015 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-015');
END $$;

-- INV-G-016 through INV-G-019
DO $$
DECLARE u uuid; pi uuid; selected uuid; atype text; nad uuid; nac2 uuid; reserved_i uuid; reserved_selected uuid; reserved_decision uuid;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Resolved','No action needed',0.9,'informational') RETURNING id INTO pi;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES
    (pi,'data_quality',0.9,'good'),(pi,'population_match',0.9,'good'),(pi,'scientific_certainty',0.9,'good');
  SELECT psi_select_next_action(pi) INTO selected;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=selected;
  SELECT id INTO nad FROM next_action_decisions WHERE insight_id=pi;
  IF NOT EXISTS (SELECT 1 FROM next_action_decisions WHERE id=nad AND policy_version='001G-R1') THEN RAISE EXCEPTION 'INV-G-016 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-016');
  IF atype <> 'NO_ACTION' THEN RAISE EXCEPTION 'INV-G-018 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-018');

  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (pi,'OBSERVE_ONLY','informational',0.1,0.1,'B0',0,true,NULL,'second') RETURNING id INTO nac2;
  BEGIN
    INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version) VALUES (pi,nac2,'illegal second','001G-R1');
    RAISE EXCEPTION 'INV-G-017 failed: second primary action accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO invariant_results VALUES ('INV-G-017');

  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'safety_attention','interaction','Reserved','Reserved safety',0.5,'reserved') RETURNING id INTO reserved_i;
  SELECT psi_select_next_action(reserved_i) INTO reserved_selected;
  SELECT action_type INTO atype FROM next_action_candidates WHERE id=reserved_selected;
  SELECT id INTO reserved_decision FROM next_action_decisions WHERE insight_id=reserved_i;
  IF atype <> 'ESCALATE_TO_CLINICIAN' OR EXISTS (SELECT 1 FROM action_executions WHERE decision_id=reserved_decision) THEN RAISE EXCEPTION 'INV-G-019 failed'; END IF;
  INSERT INTO invariant_results VALUES ('INV-G-019');
END $$;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM invariant_results;
  IF n <> 20 THEN RAISE EXCEPTION 'expected 20/20 invariant passes, got %',n; END IF;
  RAISE NOTICE 'PSI-CIM-001G invariants: %/20 PASS',n;
END $$;
