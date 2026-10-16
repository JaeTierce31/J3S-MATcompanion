DO $$
DECLARE
  u uuid;
  i uuid;
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
BEGIN
  SELECT id INTO u FROM users ORDER BY created_at LIMIT 1;
  SELECT id,confidence INTO i,science_before FROM personal_insights WHERE user_id=u ORDER BY generated_at LIMIT 1;
  SELECT id,severity INTO inter,safety_before FROM interactions ORDER BY id LIMIT 1;
  IF u IS NULL OR i IS NULL OR inter IS NULL THEN RAISE EXCEPTION '001D-001F runtime fixtures required'; END IF;

  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',now());
  SELECT psi_effective_preference(u,'research_detail',now()) INTO one_open;
  IF one_open <= 0 OR one_open > 0.03 THEN RAISE EXCEPTION 'single evidence-open adjustment must be small, got %',one_open; END IF;

  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',now());
  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',now());
  PERFORM psi_record_usefulness_event(u,i,'OPENED_EVIDENCE','insight_evidence',now());
  SELECT psi_effective_preference(u,'research_detail',now()) INTO repeated_open;
  IF repeated_open <= one_open THEN RAISE EXCEPTION 'repeated bounded behavior must exceed single signal'; END IF;
  SELECT psi_effective_preference(u,'research_detail',now()+interval '90 days') INTO decayed;
  IF decayed >= repeated_open THEN RAISE EXCEPTION 'behavioral preference must decay toward neutral'; END IF;

  PERFORM psi_record_usefulness_event(u,i,'SHOW_MORE_LIKE_THIS','explicit_control',now());
  SELECT psi_effective_preference(u,'topic_affinity',now()) INTO explicit_now;
  SELECT psi_effective_preference(u,'topic_affinity',now()+interval '365 days') INTO explicit_future;
  IF explicit_now <> explicit_future THEN RAISE EXCEPTION 'explicit preference must persist'; END IF;

  SELECT confidence INTO science_after FROM personal_insights WHERE id=i;
  SELECT severity INTO safety_after FROM interactions WHERE id=inter;
  IF science_after IS DISTINCT FROM science_before THEN RAISE EXCEPTION 'G-LEARN-002 scientific certainty changed'; END IF;
  IF safety_after IS DISTINCT FROM safety_before THEN RAISE EXCEPTION 'G-LEARN-003 safety severity changed'; END IF;

  BEGIN
    PERFORM psi_record_usefulness_event(u,i,'DWELL_TIME','telemetry',now());
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
