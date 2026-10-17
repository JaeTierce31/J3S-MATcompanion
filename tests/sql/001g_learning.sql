DO $$
DECLARE
  u uuid;
  i uuid;
  a_type text; a_id uuid;
  b_type text; b_id uuid;
  inter uuid;
  science_before numeric;
  science_after numeric;
  safety_before text;
  safety_after text;
  one_open numeric;
  repeated_open numeric;
  decayed numeric;
  explicit_now numeric;
  explicit_future numeric;
  t timestamptz := '2026-10-17T00:00:00Z'::timestamptz;
BEGIN
  -- Isolate learning from any prior fixture state.
  INSERT INTO users DEFAULT VALUES RETURNING id INTO u;
  INSERT INTO personal_insights(user_id,insight_type,subject_type,title,summary,confidence,authority_class,status)
  VALUES (u,'change_detected','test','Learning-order probe','Synthetic learning fixture',0.50,'informational','active')
  RETURNING id,confidence INTO i,science_before;

  SELECT entity_type,entity_id INTO a_type,a_id FROM entity_registry ORDER BY entity_type,entity_id LIMIT 1;
  SELECT entity_type,entity_id INTO b_type,b_id FROM entity_registry WHERE (entity_type,entity_id)<>(a_type,a_id) ORDER BY entity_type,entity_id LIMIT 1;
  IF a_id IS NULL OR b_id IS NULL THEN RAISE EXCEPTION 'entity registry fixtures required'; END IF;
  INSERT INTO interactions(actor_a_type,actor_a_id,actor_b_type,actor_b_id,interaction_type,severity,confidence)
  VALUES (a_type,a_id,b_type,b_id,'additive_effect','moderate',0.50)
  RETURNING id,severity INTO inter,safety_before;

  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',t);
  SELECT psi_effective_preference(u,'research_detail',t) INTO one_open;
  IF abs(one_open-0.02) > 0.0000001 THEN RAISE EXCEPTION 'single evidence-open adjustment expected 0.02, got %',one_open; END IF;

  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',t);
  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',t);
  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',t);
  SELECT psi_effective_preference(u,'research_detail',t) INTO repeated_open;
  IF abs(repeated_open-0.08) > 0.0000001 THEN RAISE EXCEPTION 'four same-timestamp evidence opens expected 0.08, got %',repeated_open; END IF;
  SELECT psi_effective_preference(u,'research_detail',t+interval '90 days') INTO decayed;
  IF decayed >= repeated_open OR decayed <= 0 THEN RAISE EXCEPTION 'behavioral preference must decay toward neutral, got % from %',decayed,repeated_open; END IF;

  PERFORM psi_record_usefulness_event(u,i,'SHOW_MORE_LIKE_THIS','explicit_control',t);
  SELECT psi_effective_preference(u,'topic_affinity',t) INTO explicit_now;
  SELECT psi_effective_preference(u,'topic_affinity',t+interval '365 days') INTO explicit_future;
  IF explicit_now <> explicit_future THEN RAISE EXCEPTION 'explicit preference must persist'; END IF;

  SELECT confidence INTO science_after FROM personal_insights WHERE id=i;
  SELECT severity INTO safety_after FROM interactions WHERE id=inter;
  IF science_after IS DISTINCT FROM science_before THEN RAISE EXCEPTION 'G-LEARN-002 scientific certainty changed'; END IF;
  IF safety_after IS DISTINCT FROM safety_before THEN RAISE EXCEPTION 'G-LEARN-003 safety severity changed'; END IF;

  BEGIN
    PERFORM psi_record_usefulness_event(u,i,'DWELL_TIME','telemetry',t);
    RAISE EXCEPTION 'dwell time accepted as usefulness signal';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;

DO $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  BEGIN
    INSERT INTO preference_state_versions(user_id,dimension,explicit_value,behavioral_value,source_kind,source_mix,confidence,effective_at,decay_policy,version)
    VALUES (u,'topic_affinity',2,0,'explicit','{}',1,now(),'persist','bad');
    RAISE EXCEPTION 'out-of-range preference accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
