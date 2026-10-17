DO $$
DECLARE
  base_id uuid;
  next_id uuid;
  r text;
  receipt_count integer;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,scientific_claim_refs,personal_evidence_refs,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000201','Stress changed','Stress decreased','advisory','["claim:1"]','["obs:1"]','down',0.60,'stress','low') RETURNING id INTO base_id;
  PERFORM psi_register_candidate_fingerprint(base_id);

  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,scientific_claim_refs,personal_evidence_refs,direction,candidate_confidence,context_key,safety_relevance)
  SELECT user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,scientific_claim_refs,personal_evidence_refs,direction,candidate_confidence,context_key,safety_relevance FROM insight_candidates WHERE id=base_id
  RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'EXACT_DUPLICATE' THEN RAISE EXCEPTION 'G-DUP-001 expected EXACT_DUPLICATE, got %',r; END IF;
  SELECT count(*) INTO receipt_count FROM redundancy_receipts WHERE candidate_id=next_id;
  IF receipt_count <> 1 THEN RAISE EXCEPTION 'candidate must have exactly one redundancy receipt, got %',receipt_count; END IF;
END $$;

DO $$
DECLARE base_id uuid; next_id uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,scientific_claim_refs,personal_evidence_refs,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000202','Sleep changed','Sleep improved','advisory','["claim:2"]','["obs:2"]','up',0.61,'sleep','low') RETURNING id INTO base_id;
  PERFORM psi_register_candidate_fingerprint(base_id);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,scientific_claim_refs,personal_evidence_refs,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000202','Sleep changed','Sleep improved','advisory','["claim:2"]','["obs:2","obs:3"]','up',0.62,'sleep','low') RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'STATE_REFRESH' THEN RAISE EXCEPTION 'G-DUP-002 expected STATE_REFRESH, got %',r; END IF;
END $$;

DO $$
DECLARE base_id uuid; next_id uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000203','Energy changed','Possible energy improvement','advisory','up',0.35,'energy','low') RETURNING id INTO base_id;
  PERFORM psi_register_candidate_fingerprint(base_id);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000203','Energy changed','Energy improvement now persists','advisory','up',0.72,'energy','low') RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'MATERIAL_REVISION' THEN RAISE EXCEPTION 'G-DUP-003 expected MATERIAL_REVISION, got %',r; END IF;
END $$;

DO $$
DECLARE base_id uuid; next_id uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000204','Stress changed','Stress improved','advisory','down',0.70,'stress-contradiction','low') RETURNING id INTO base_id;
  PERFORM psi_register_candidate_fingerprint(base_id);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000204','Stress changed','Stress worsened','advisory','up',0.70,'stress-contradiction','low') RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'CONTRADICTION' THEN RAISE EXCEPTION 'G-DUP-004 expected CONTRADICTION, got %',r; END IF;
END $$;

DO $$
DECLARE base_id uuid; next_id uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','safety_attention','interaction','00000000-0000-0000-0000-000000000205','Interaction','Interaction uncertainty','advisory','none',0.50,'interaction','moderate') RETURNING id INTO base_id;
  PERFORM psi_register_candidate_fingerprint(base_id);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','safety_attention','interaction','00000000-0000-0000-0000-000000000205','Interaction','Interaction now high severity','advisory','none',0.60,'interaction','high') RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'ESCALATION' THEN RAISE EXCEPTION 'G-DUP-005 expected ESCALATION, got %',r; END IF;
END $$;

DO $$
DECLARE next_id uuid; r text;
BEGIN
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance)
  VALUES ('00000000-0000-0000-0000-000000000001','evidence_context','ingredient','00000000-0000-0000-0000-000000000206','New evidence','New evidence context','informational','none',0.50,'new-evidence','none') RETURNING id INTO next_id;
  SELECT psi_classify_candidate(next_id) INTO r;
  IF r <> 'NEW' THEN RAISE EXCEPTION 'expected NEW, got %',r; END IF;
END $$;
