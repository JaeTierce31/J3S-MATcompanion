DO $$
DECLARE s uuid; c uuid; r text;
BEGIN
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001','METRIC_SHIFT','metric','00000000-0000-0000-0000-000000000301',0.30,'down',0.80,3,0.60,'low','["obs:e1"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000301','Trend','Trend changed','advisory','down',0.70,'elig-new','low',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  SELECT psi_evaluate_eligibility(c, now()) INTO r;
  IF r <> 'ELIGIBLE' THEN RAISE EXCEPTION 'expected ELIGIBLE, got %',r; END IF;
END $$;

DO $$
DECLARE s uuid; c1 uuid; c2 uuid; r text;
BEGIN
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001','METRIC_SHIFT','metric','00000000-0000-0000-0000-000000000302',0.30,'down',0.80,3,0.60,'low','["obs:e2"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000302','Trend','Duplicate trend','advisory','down',0.70,'elig-dup','low',s) RETURNING id INTO c1;
  PERFORM psi_classify_candidate(c1);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  SELECT user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id FROM insight_candidates WHERE id=c1 RETURNING id INTO c2;
  PERFORM psi_classify_candidate(c2);
  SELECT psi_evaluate_eligibility(c2, now()) INTO r;
  IF r <> 'SUPPRESS_DUPLICATE' THEN RAISE EXCEPTION 'expected SUPPRESS_DUPLICATE, got %',r; END IF;
END $$;

DO $$
DECLARE s uuid; c uuid; r text;
BEGIN
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001','METRIC_SHIFT','metric','00000000-0000-0000-0000-000000000303',0.30,'down',0.80,3,0.60,'low','["obs:e3"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000303','Trend','Cooldown trend','advisory','down',0.70,'elig-cool','low',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at) VALUES ('00000000-0000-0000-0000-000000000001','personal_trend',now()) ON CONFLICT (user_id,cooldown_family) DO UPDATE SET last_delivered_at=excluded.last_delivered_at;
  SELECT psi_evaluate_eligibility(c, now()) INTO r;
  IF r <> 'DEFER_COOLDOWN' THEN RAISE EXCEPTION 'expected DEFER_COOLDOWN, got %',r; END IF;
END $$;

DO $$
DECLARE s uuid; c uuid; r text;
BEGIN
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,current_state,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001','SAFETY_CHANGE','interaction','00000000-0000-0000-0000-000000000304','{"severity":"critical"}',0,'none',0.40,1,0.20,'critical','["interaction:e4"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','safety_attention','interaction','00000000-0000-0000-0000-000000000304','Critical safety','Critical safety change','reserved','none',0.50,'safety-critical','critical',s) RETURNING id INTO c;
  PERFORM psi_classify_candidate(c);
  INSERT INTO user_topic_suppression(user_id,context_key,muted) VALUES ('00000000-0000-0000-0000-000000000001','safety-critical',true) ON CONFLICT (user_id,context_key) DO UPDATE SET muted=true;
  SELECT psi_evaluate_eligibility(c, now()) INTO r;
  IF r <> 'ESCALATE' THEN RAISE EXCEPTION 'critical safety must bypass mute/cooldown, got %',r; END IF;
END $$;

DO $$
DECLARE s uuid; c1 uuid; c2 uuid; r text;
BEGIN
  INSERT INTO change_signals(user_id,signal_type,subject_type,subject_id,magnitude,direction,confidence,persistence,novelty,safety_relevance,source_refs)
  VALUES ('00000000-0000-0000-0000-000000000001','METRIC_SHIFT','metric','00000000-0000-0000-0000-000000000305',0.30,'down',0.80,3,0.60,'low','["obs:e5"]') RETURNING id INTO s;
  PERFORM psi_evaluate_materiality(s);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000305','Trend','Improved','advisory','down',0.70,'elig-contradict','low',s) RETURNING id INTO c1;
  PERFORM psi_classify_candidate(c1);
  INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class,direction,candidate_confidence,context_key,safety_relevance,source_signal_id)
  VALUES ('00000000-0000-0000-0000-000000000001','change_detected','metric','00000000-0000-0000-0000-000000000305','Trend','Worsened','advisory','up',0.70,'elig-contradict','low',s) RETURNING id INTO c2;
  PERFORM psi_classify_candidate(c2);
  SELECT psi_evaluate_eligibility(c2, now()) INTO r;
  IF r <> 'SUPERSEDE_EXISTING' THEN RAISE EXCEPTION 'contradiction must supersede, got %',r; END IF;
END $$;
