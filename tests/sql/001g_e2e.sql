DO $$
DECLARE
  u uuid; s uuid; c uuid; c2 uuid; pi uuid; selected uuid;
  mat text; dup text; elig text; tier text; delivery text; action_type text; dup_elig text;
  adjustment numeric; pref_before numeric; pref_after numeric;
  science_before numeric; science_after numeric; safety_before text; safety_after text;
  inter uuid; a_type text; a_id uuid; b_type text; b_id uuid;
  actual jsonb; expected jsonb;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;

  SELECT entity_type,entity_id INTO a_type,a_id FROM entity_registry ORDER BY entity_type,entity_id LIMIT 1;
  SELECT entity_type,entity_id INTO b_type,b_id FROM entity_registry WHERE (entity_type,entity_id)<>(a_type,a_id) ORDER BY entity_type,entity_id LIMIT 1;
  INSERT INTO interactions(actor_a_type,actor_a_id,actor_b_type,actor_b_id,interaction_type,severity,confidence)
  VALUES (a_type,a_id,b_type,b_id,'additive_effect','moderate',0.50) RETURNING id,severity INTO inter,safety_before;

  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000003001',0.30,'down',0.80,3,0.70,'low','["e2e:obs1","e2e:obs2","e2e:obs3"]') RETURNING id INTO s;
  SELECT psi_evaluate_materiality(s) INTO mat;

  INSERT INTO personal_insights(user_id,insight_type,subject_type,subject_id,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','00000000-0000-0000-0000-000000003001','Stress trend','Stress decreased; population applicability remains uncertain',0.50,'advisory') RETURNING id INTO pi;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale) VALUES
    (pi,'data_quality',0.90,'three persistent observations'),
    (pi,'population_match',0.30,'external evidence population mismatch');
  SELECT confidence INTO science_before FROM personal_insights WHERE id=pi;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000003001','Stress trend','Stress decreased; population applicability remains uncertain','advisory','down',0.50,'e2e-stress','low',s,pi) RETURNING id INTO c;

  SELECT psi_classify_candidate(c) INTO dup;
  SELECT psi_evaluate_eligibility(c,now()) INTO elig;
  SELECT psi_priority_tier(c) INTO tier;
  PERFORM psi_rank_candidate_safe(c);
  SELECT adaptive_adjustment INTO adjustment FROM priority_decisions WHERE candidate_id=c ORDER BY decided_at DESC LIMIT 1;
  SELECT psi_delivery_decision(c,'in_app',now()) INTO delivery;

  SELECT psi_select_next_action(pi) INTO selected;
  SELECT nac.action_type INTO action_type FROM next_action_candidates nac WHERE nac.id=selected;

  SELECT psi_effective_preference(u,'topic_affinity',now()) INTO pref_before;
  PERFORM psi_record_usefulness_event(u,pi,'HELPFUL','e2e_fixture',now());
  SELECT psi_effective_preference(u,'topic_affinity',now()) INTO pref_after;

  SELECT confidence INTO science_after FROM personal_insights WHERE id=pi;
  SELECT severity INTO safety_after FROM interactions WHERE id=inter;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id)
  SELECT user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id FROM insight_candidates WHERE id=c RETURNING id INTO c2;
  PERFORM psi_classify_candidate(c2);
  SELECT psi_evaluate_eligibility(c2,now()) INTO dup_elig;

  actual := jsonb_build_object(
    'materiality',mat,
    'redundancy',dup,
    'eligibility',elig,
    'tier',tier,
    'adaptive_adjustment',adjustment,
    'delivery',delivery,
    'action',action_type,
    'feedback','HELPFUL',
    'preference_changed',pref_after>pref_before,
    'scientific_confidence_unchanged',science_after IS NOT DISTINCT FROM science_before,
    'safety_severity_unchanged',safety_after IS NOT DISTINCT FROM safety_before,
    'duplicate_eligibility',dup_elig,
    'policy_version','001G-R1'
  );

  expected := '{"materiality":"MATERIAL","redundancy":"NEW","eligibility":"ELIGIBLE","tier":"T2","adaptive_adjustment":0,"delivery":"DELIVER_IN_APP","action":"REVIEW_EVIDENCE","feedback":"HELPFUL","preference_changed":true,"scientific_confidence_unchanged":true,"safety_severity_unchanged":true,"duplicate_eligibility":"SUPPRESS_DUPLICATE","policy_version":"001G-R1"}'::jsonb;

  IF actual <> expected THEN
    RAISE EXCEPTION '001G E2E semantic mismatch. expected %, actual %',expected,actual;
  END IF;
END $$;
