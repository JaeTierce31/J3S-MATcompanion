CREATE TEMP TABLE IF NOT EXISTS invariant_results(id text PRIMARY KEY);
TRUNCATE invariant_results;

CREATE OR REPLACE FUNCTION pg_temp.assert_inv(p_id text,p_ok boolean,p_msg text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(p_ok,false) IS NOT TRUE THEN RAISE EXCEPTION '% failed: %',p_id,p_msg; END IF;
  INSERT INTO invariant_results(id) VALUES (p_id);
END;
$$;

DO $$
DECLARE
  u uuid; u2 uuid; pi uuid; inter uuid; a_type text; a_id uuid; b_type text; b_id uuid;
  s uuid; c uuid; c1 uuid; c2 uuid; c3 uuid; c4 uuid;
  elig_before text; elig_after text; conf_before numeric; conf_after numeric; auth_before text; auth_after text; sev_before text; sev_after text;
  cls text; decision_text text; matched uuid; elig_reasons jsonb; mat text;
  score_t1 numeric; score_t3 numeric; adj numeric; delivery_priority uuid;
  selected uuid; selected_type text; nad uuid; nac2 uuid; reserved_i uuid; reserved_selected uuid; reserved_decision uuid;
  learn_before integer; learn_after integer;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Learning boundary','fixture',0.60,'advisory') RETURNING id INTO pi;
  SELECT entity_type,entity_id INTO a_type,a_id FROM entity_registry ORDER BY entity_type,entity_id LIMIT 1;
  SELECT entity_type,entity_id INTO b_type,b_id FROM entity_registry WHERE (entity_type,entity_id)<>(a_type,a_id) ORDER BY entity_type,entity_id LIMIT 1;
  INSERT INTO interactions(actor_a_type,actor_a_id,actor_b_type,actor_b_id,interaction_type,severity,confidence)
  VALUES (a_type,a_id,b_type,b_id,'additive_effect','moderate',0.5) RETURNING id INTO inter;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002001',0.01,'down',0.8,3,0.2,'low','["inv:1"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002001','Below threshold','Below threshold','advisory','down',0.6,'inv-learning','low',s,pi) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  SELECT psi_evaluate_eligibility(c,now()) INTO elig_before;
  SELECT confidence,authority_class INTO conf_before,auth_before FROM personal_insights WHERE id=pi;
  SELECT severity INTO sev_before FROM interactions WHERE id=inter;
  PERFORM psi_record_usefulness_event(u,pi,'HELPFUL','invariant_fixture',now());
  SELECT decision INTO elig_after FROM eligibility_decisions WHERE candidate_id=c ORDER BY evaluated_at DESC LIMIT 1;
  SELECT confidence,authority_class INTO conf_after,auth_after FROM personal_insights WHERE id=pi;
  SELECT severity INTO sev_after FROM interactions WHERE id=inter;
  PERFORM pg_temp.assert_inv('INV-G-001',elig_before='SUPPRESS_LOW_VALUE' AND elig_after=elig_before,'feedback changed eligibility');
  PERFORM pg_temp.assert_inv('INV-G-002',conf_after IS NOT DISTINCT FROM conf_before,'feedback changed scientific confidence');
  PERFORM pg_temp.assert_inv('INV-G-003',sev_after IS NOT DISTINCT FROM sev_before,'feedback changed safety severity');
  PERFORM pg_temp.assert_inv('INV-G-004',auth_after IS NOT DISTINCT FROM auth_before,'feedback changed authority');
  BEGIN PERFORM psi_record_usefulness_event(u,pi,'DWELL_TIME','telemetry',now()); RAISE EXCEPTION 'dwell accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM pg_temp.assert_inv('INV-G-013',true,'dwell time was not rejected');
  SELECT count(*) INTO learn_before FROM usefulness_events WHERE insight_id=pi;
  BEGIN PERFORM psi_record_usefulness_event(u,pi,'UNOBSERVED_INTERNAL_EVENT','internal',now()); RAISE EXCEPTION 'unobserved event accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  SELECT count(*) INTO learn_after FROM usefulness_events WHERE insight_id=pi;
  PERFORM pg_temp.assert_inv('INV-G-020',learn_after=learn_before,'unobserved event created learning');

  INSERT INTO users DEFAULT VALUES RETURNING id INTO u2;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,current_state,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u2,'SAFETY_CHANGE','interaction','00000000-0000-0000-0000-000000002005','{"severity":"critical"}',0,'none',0.4,1,0.2,'critical','["inv:safety"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u2,'safety_attention','interaction','00000000-0000-0000-0000-000000002005','Critical','Critical safety','reserved','none',0.5,'inv-critical','critical',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at) VALUES (u2,'safety',now());
  INSERT INTO user_topic_suppression(user_id,context_key,muted) VALUES (u2,'inv-critical',true);
  SELECT psi_evaluate_eligibility(c,now()) INTO decision_text;
  PERFORM pg_temp.assert_inv('INV-G-005',decision_text='ESCALATE','critical safety did not bypass cooldown');
  PERFORM pg_temp.assert_inv('INV-G-006',decision_text='ESCALATE','critical safety was muted');
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u2,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002010',0.35,'down',0.8,3,0.6,'low','["inv:cooldown"]') RETURNING id INTO s;
  SELECT psi_evaluate_materiality(s) INTO mat;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u2,'change_detected','metric','00000000-0000-0000-0000-000000002010','Trend','Material but cooldown','advisory','down',0.7,'inv-cooldown','low',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at) VALUES (u2,'personal_trend',now()) ON CONFLICT (user_id,cooldown_family) DO UPDATE SET last_delivered_at=excluded.last_delivered_at;
  SELECT psi_evaluate_eligibility(c,now()) INTO decision_text;
  PERFORM pg_temp.assert_inv('INV-G-010',mat='MATERIAL' AND decision_text='DEFER_COOLDOWN','cooldown changed analysis/materiality');

  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000002020',0.35,'down',0.8,3,0.6,'low','["inv:dup"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002020','Trend','Same','advisory','down',0.60,'inv-family','low',s) RETURNING id INTO c1;
  PERFORM psi_classify_candidate(c1);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  SELECT user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id FROM insight_candidates WHERE id=c1 RETURNING id INTO c2;
  SELECT psi_classify_candidate(c2) INTO cls;
  SELECT psi_evaluate_eligibility(c2,now()) INTO decision_text;
  SELECT ed.reasons INTO elig_reasons FROM eligibility_decisions ed WHERE ed.candidate_id=c2 ORDER BY ed.evaluated_at DESC LIMIT 1;
  PERFORM pg_temp.assert_inv('INV-G-007',cls='EXACT_DUPLICATE' AND decision_text='SUPPRESS_DUPLICATE','duplicate was not suppressed');
  PERFORM pg_temp.assert_inv('INV-G-014',jsonb_array_length(elig_reasons)>0,'suppression lacked reason receipt');

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002020','Trend revised','Material confidence revision','advisory','down',0.95,'inv-family','low',s) RETURNING id INTO c4;
  SELECT psi_classify_candidate(c4) INTO cls;
  SELECT matched_candidate_id INTO matched FROM redundancy_receipts WHERE candidate_id=c4;
  PERFORM pg_temp.assert_inv('INV-G-009',cls='MATERIAL_REVISION' AND matched IS NOT NULL,'material revision lost prior lineage');

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000002020','Trend','Opposite','advisory','up',0.60,'inv-family','low',s) RETURNING id INTO c3;
  SELECT psi_classify_candidate(c3) INTO cls;
  SELECT psi_evaluate_eligibility(c3,now()) INTO decision_text;
  PERFORM pg_temp.assert_inv('INV-G-008',cls='CONTRADICTION' AND decision_text='SUPERSEDE_EXISTING','contradiction suppressed as duplicate');

  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'optimization','metric','00000000-0000-0000-0000-000000002030','Opt','Opt','advisory') RETURNING id INTO c;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c,999);
  SELECT adaptive_adjustment INTO adj FROM priority_decisions WHERE candidate_id=c ORDER BY decided_at DESC LIMIT 1;
  PERFORM pg_temp.assert_inv('INV-G-011',adj=0.15,'adaptive adjustment escaped bound');
  PERFORM psi_delivery_decision(c,'in_app',now());
  SELECT priority_decision_id INTO delivery_priority FROM delivery_events WHERE candidate_id=c ORDER BY delivered_at DESC LIMIT 1;
  PERFORM pg_temp.assert_inv('INV-G-015',delivery_priority IS NOT NULL AND EXISTS(SELECT 1 FROM priority_decisions WHERE id=delivery_priority),'delivery missing ranking receipt');
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'experiment_result','experiment','00000000-0000-0000-0000-000000002031','T1','T1','advisory') RETURNING id INTO c1;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c1,'ELIGIBLE','none','advisory','none','001G-R1');
  SELECT psi_rank_candidate(c1,-0.15) INTO score_t1;
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'evidence_context','claim','00000000-0000-0000-0000-000000002032','T3','T3','informational') RETURNING id INTO c3;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version) VALUES (c3,'ELIGIBLE','none','informational','none','001G-R1');
  SELECT psi_rank_candidate(c3,0.15) INTO score_t3;
  PERFORM pg_temp.assert_inv('INV-G-012',score_t1>score_t3,'adaptive ranking crossed hard tiers');

  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','Resolved','No action needed',0.9,'informational') RETURNING id INTO pi;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES (pi,'data_quality',0.9,'good'),(pi,'population_match',0.9,'good'),(pi,'scientific_certainty',0.9,'good');
  SELECT psi_select_next_action(pi) INTO selected;
  SELECT action_type INTO selected_type FROM next_action_candidates WHERE id=selected;
  SELECT id INTO nad FROM next_action_decisions WHERE insight_id=pi;
  PERFORM pg_temp.assert_inv('INV-G-016',EXISTS(SELECT 1 FROM next_action_decisions WHERE id=nad AND policy_version='001G-R1'),'action decision missing policy receipt');
  PERFORM pg_temp.assert_inv('INV-G-018',selected_type='NO_ACTION','NO_ACTION not selected as valid outcome');
  INSERT INTO next_action_candidates(insight_id,action_type,authority_class,expected_information_gain,decision_relevance,burden_class,safety_priority,eligibility,dominant_uncertainty,rationale)
  VALUES (pi,'OBSERVE_ONLY','informational',0.1,0.1,'B0',0,true,NULL,'second') RETURNING id INTO nac2;
  BEGIN INSERT INTO next_action_decisions(insight_id,selected_candidate_id,selection_reason,policy_version) VALUES (pi,nac2,'illegal second','001G-R1'); RAISE EXCEPTION 'second primary action accepted'; EXCEPTION WHEN unique_violation THEN NULL; END;
  PERFORM pg_temp.assert_inv('INV-G-017',true,'one-primary-action uniqueness absent');
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class)
  VALUES (u,'safety_attention','interaction','Reserved','Reserved safety',0.5,'reserved') RETURNING id INTO reserved_i;
  SELECT psi_select_next_action(reserved_i) INTO reserved_selected;
  SELECT action_type INTO selected_type FROM next_action_candidates WHERE id=reserved_selected;
  SELECT id INTO reserved_decision FROM next_action_decisions WHERE insight_id=reserved_i;
  PERFORM pg_temp.assert_inv('INV-G-019',selected_type='ESCALATE_TO_CLINICIAN' AND NOT EXISTS(SELECT 1 FROM action_executions WHERE decision_id=reserved_decision),'reserved action auto-executed');
END $$;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM invariant_results;
  IF n<>20 THEN RAISE EXCEPTION 'expected 20/20 invariant passes, got %',n; END IF;
  RAISE NOTICE 'PSI-CIM-001G invariants: %/20 PASS',n;
END $$;
