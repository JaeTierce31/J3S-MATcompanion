DO $$
DECLARE
  u uuid;
  s uuid;
  c uuid;
  pi uuid;
  a uuid;
  doc jsonb;
  pref_event uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;

  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000001001',0.30,'down',0.80,3,0.60,'low','["obs:audit"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);

  INSERT INTO personal_insights(user_id,insight_type,subject_type,subject_id,title,summary,confidence,authority_class)
  VALUES (u,'uncertainty','metric','00000000-0000-0000-0000-000000001001','Audit insight','Population applicability uncertain',0.50,'advisory') RETURNING id INTO pi;
  INSERT INTO insight_confidence_components(insight_id,component,score,rationale)
  VALUES (pi,'population_match',0.30,'audit fixture'),(pi,'data_quality',0.90,'audit fixture');

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id,materialized_insight_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000001001','Audit insight','Population applicability uncertain','advisory','down',0.50,'audit-lineage','low',s,pi) RETURNING id INTO c;

  PERFORM psi_classify_candidate(c);
  PERFORM psi_evaluate_eligibility(c,now());
  PERFORM psi_rank_candidate(c,0);
  PERFORM psi_delivery_decision(c,'in_app',now());
  SELECT psi_select_next_action(pi) INTO a;
  SELECT psi_record_usefulness_event(u,pi,'HELPFUL','audit_fixture',now()) INTO pref_event;

  SELECT psi_orchestration_receipt(c,u) INTO doc;

  IF doc->'signal'->>'id' IS DISTINCT FROM s::text THEN RAISE EXCEPTION 'G-AUD-001 signal/materiality lineage missing'; END IF;
  IF doc->'eligibility'->>'candidate_id' IS DISTINCT FROM c::text THEN RAISE EXCEPTION 'G-AUD-001 eligibility lineage missing'; END IF;
  IF doc->'priority'->>'candidate_id' IS DISTINCT FROM c::text THEN RAISE EXCEPTION 'G-AUD-002 ranking lineage missing'; END IF;
  IF doc->'next_action'->>'selected_candidate_id' IS DISTINCT FROM a::text THEN RAISE EXCEPTION 'G-AUD-003 action lineage missing'; END IF;
  IF jsonb_array_length(doc->'preference_lineage') < 1 THEN RAISE EXCEPTION 'G-AUD-005 feedback-to-preference lineage missing'; END IF;
  IF doc->'versions'->>'policy_version' IS NULL OR doc->'versions'->>'ranking_model_version' IS NULL OR doc->'versions'->>'preference_state_version' IS NULL OR doc->'versions'->>'materiality_rule_version' IS NULL OR doc->'versions'->>'action_policy_version' IS NULL THEN
    RAISE EXCEPTION 'audit receipt missing required version fields';
  END IF;
END $$;

DO $$
DECLARE u uuid; s uuid; c1 uuid; c2 uuid; doc jsonb;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES (u,'METRIC_SHIFT','metric','00000000-0000-0000-0000-000000001002',0.30,'down',0.80,3,0.60,'low','["obs:supersession"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000001002','Trend','Improved','advisory','down',0.70,'audit-super','low',s) RETURNING id INTO c1;
  PERFORM psi_classify_candidate(c1);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES (u,'change_detected','metric','00000000-0000-0000-0000-000000001002','Trend','Worsened','advisory','up',0.70,'audit-super','low',s) RETURNING id INTO c2;
  PERFORM psi_classify_candidate(c2);
  PERFORM psi_evaluate_eligibility(c2,now());
  SELECT psi_orchestration_receipt(c2,u) INTO doc;
  IF doc->'redundancy'->>'classification' <> 'CONTRADICTION' THEN RAISE EXCEPTION 'G-AUD-004 contradiction/supersession lineage missing'; END IF;
  IF doc->'redundancy'->>'matched_candidate_id' IS DISTINCT FROM c1::text THEN RAISE EXCEPTION 'G-AUD-004 matched prior candidate missing'; END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    IF has_table_privilege('psi_dashboard_reader','change_signals','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct change_signals SELECT'; END IF;
    IF has_table_privilege('psi_dashboard_reader','v_psi_orchestration_receipt','SELECT') THEN RAISE EXCEPTION 'dashboard reader has direct orchestration receipt view SELECT'; END IF;
    IF NOT has_function_privilege('psi_dashboard_reader','api_orchestration_receipt(uuid)','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader lacks governed receipt API execute'; END IF;
    IF NOT has_function_privilege('psi_dashboard_reader','api_orchestration_attention()','EXECUTE') THEN RAISE EXCEPTION 'dashboard reader lacks governed attention API execute'; END IF;
  END IF;
END $$;
