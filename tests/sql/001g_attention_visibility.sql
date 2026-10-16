DO $$
DECLARE
  u uuid;
  c_visible uuid;
  c_suppressed uuid;
  delivery_id uuid;
  feed jsonb;
BEGIN
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'experiment_result','experiment',gen_random_uuid(),'Visible T1','Delivered attention','advisory')
  RETURNING id INTO c_visible;
  INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c_visible,'ELIGIBLE','none','advisory','none','001G-R1');
  PERFORM psi_rank_candidate(c_visible,0);
  PERFORM psi_delivery_decision(c_visible,'in_app',clock_timestamp());
  SELECT id INTO delivery_id FROM delivery_events WHERE candidate_id=c_visible ORDER BY delivered_at DESC LIMIT 1;

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
  VALUES (u,'change_detected','metric',gen_random_uuid(),'Suppressed candidate','Must never surface','advisory')
  RETURNING id INTO c_suppressed;
  INSERT INTO eligibility_decisions(candidate_id,decision,reasons,cooldown_state,authority_state,safety_state,policy_version)
  VALUES (c_suppressed,'SUPPRESS_LOW_VALUE','["fixture"]','none','advisory','none','001G-R1');

  SELECT psi_orchestration_attention_for_user(u) INTO feed;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(feed) x WHERE (x->>'candidate_id')::uuid=c_visible
  ) THEN RAISE EXCEPTION 'delivered active attention item missing from feed'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(feed) x WHERE (x->>'candidate_id')::uuid=c_suppressed
  ) THEN RAISE EXCEPTION 'suppressed/undelivered candidate leaked into attention feed'; END IF;

  PERFORM psi_resolve_delivery(delivery_id,'resolved','attention-visibility-test',NULL);
  SELECT psi_orchestration_attention_for_user(u) INTO feed;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(feed) x WHERE (x->>'candidate_id')::uuid=c_visible
  ) THEN RAISE EXCEPTION 'resolved attention item remained in active feed'; END IF;
END $$;
