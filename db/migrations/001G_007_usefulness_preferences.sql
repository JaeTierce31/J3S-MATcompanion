CREATE TABLE IF NOT EXISTS usefulness_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  insight_id uuid NOT NULL REFERENCES personal_insights(id),
  signal_type text NOT NULL,
  signal_source text NOT NULL,
  explicit_or_behavioral text NOT NULL CHECK (explicit_or_behavioral IN ('explicit','behavioral')),
  dimension text NOT NULL CHECK (dimension IN ('explanation_depth','research_detail','experiment_action_affinity','notification_frequency','topic_affinity','uncertainty_tolerance','safety_visibility')),
  weight numeric NOT NULL CHECK (weight >= -1 AND weight <= 1),
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL
);
DROP TRIGGER IF EXISTS trg_usefulness_event_immutable ON usefulness_events;
CREATE TRIGGER trg_usefulness_event_immutable BEFORE UPDATE OR DELETE ON usefulness_events FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE TABLE IF NOT EXISTS preference_state_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  dimension text NOT NULL CHECK (dimension IN ('explanation_depth','research_detail','experiment_action_affinity','notification_frequency','topic_affinity','uncertainty_tolerance','safety_visibility')),
  explicit_value numeric NOT NULL CHECK (explicit_value >= -1 AND explicit_value <= 1),
  behavioral_value numeric NOT NULL CHECK (behavioral_value >= -1 AND behavioral_value <= 1),
  source_kind text NOT NULL CHECK (source_kind IN ('explicit','behavioral')),
  source_mix jsonb NOT NULL DEFAULT '{}'::jsonb,
  confidence numeric NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  derived_from_event_id uuid REFERENCES usefulness_events(id),
  effective_at timestamptz NOT NULL,
  decay_policy text NOT NULL,
  version text NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_preference_user_dimension_time ON preference_state_versions(user_id,dimension,effective_at DESC);
DROP TRIGGER IF EXISTS trg_preference_version_immutable ON preference_state_versions;
CREATE TRIGGER trg_preference_version_immutable BEFORE UPDATE OR DELETE ON preference_state_versions FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE FUNCTION psi_effective_preference(p_user_id uuid,p_dimension text,p_as_of timestamptz)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  s preference_state_versions%ROWTYPE;
  pol psi_orchestration_policy%ROWTYPE;
  age_days numeric;
  decayed_behavioral numeric;
BEGIN
  SELECT * INTO s FROM preference_state_versions
  WHERE user_id=p_user_id AND dimension=p_dimension AND effective_at <= p_as_of
  ORDER BY effective_at DESC,id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  age_days := greatest(0,extract(epoch FROM (p_as_of-s.effective_at))/86400.0);
  decayed_behavioral := s.behavioral_value * power(0.5,age_days/pol.behavioral_decay_days);
  RETURN greatest(-1,least(1,s.explicit_value+decayed_behavioral));
END;
$$;

CREATE OR REPLACE FUNCTION psi_record_usefulness_event(
  p_user_id uuid,
  p_insight_id uuid,
  p_signal_type text,
  p_source text,
  p_occurred_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  kind text;
  dim text;
  w numeric;
  prev preference_state_versions%ROWTYPE;
  pol psi_orchestration_policy%ROWTYPE;
  current_behavioral numeric := 0;
  new_explicit numeric := 0;
  new_behavioral numeric := 0;
  ev uuid;
  version_id uuid;
  age_days numeric;
BEGIN
  CASE p_signal_type
    WHEN 'HELPFUL' THEN kind:='explicit'; dim:='topic_affinity'; w:=0.10;
    WHEN 'NOT_HELPFUL' THEN kind:='explicit'; dim:='topic_affinity'; w:=-0.10;
    WHEN 'SAVE_FOR_LATER' THEN kind:='explicit'; dim:='notification_frequency'; w:=-0.05;
    WHEN 'DISMISS' THEN kind:='explicit'; dim:='topic_affinity'; w:=-0.08;
    WHEN 'SHOW_MORE_LIKE_THIS' THEN kind:='explicit'; dim:='topic_affinity'; w:=0.15;
    WHEN 'SHOW_LESS_LIKE_THIS' THEN kind:='explicit'; dim:='topic_affinity'; w:=-0.15;
    WHEN 'MUTE_TOPIC' THEN kind:='explicit'; dim:='topic_affinity'; w:=-1.00;
    WHEN 'FOLLOW_UP_REQUESTED' THEN kind:='explicit'; dim:='experiment_action_affinity'; w:=0.10;
    WHEN 'OPENED_EVIDENCE' THEN kind:='behavioral'; dim:='research_detail'; w:=0.02;
    WHEN 'COMPLETED_EXPERIMENT' THEN kind:='behavioral'; dim:='experiment_action_affinity'; w:=0.04;
    WHEN 'COMPLETED_ADVISORY_ACTION' THEN kind:='behavioral'; dim:='experiment_action_affinity'; w:=0.03;
    WHEN 'REPEATED_CATEGORY_DISMISSAL' THEN kind:='behavioral'; dim:='topic_affinity'; w:=-0.05;
    WHEN 'REOPENED_SAME_UNCERTAINTY' THEN kind:='behavioral'; dim:='explanation_depth'; w:=0.03;
    ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='disallowed usefulness signal: '||p_signal_type;
  END CASE;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':'||dim,0));
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  SELECT * INTO prev FROM preference_state_versions WHERE user_id=p_user_id AND dimension=dim ORDER BY effective_at DESC,id DESC LIMIT 1;
  IF FOUND THEN
    age_days := greatest(0,extract(epoch FROM (p_occurred_at-prev.effective_at))/86400.0);
    current_behavioral := prev.behavioral_value * power(0.5,age_days/pol.behavioral_decay_days);
    new_explicit := prev.explicit_value;
  END IF;

  IF kind='explicit' THEN
    new_explicit := greatest(-1,least(1,new_explicit+w));
    new_behavioral := current_behavioral;
  ELSE
    new_behavioral := greatest(-1,least(1,current_behavioral+w));
  END IF;

  INSERT INTO usefulness_events(user_id,insight_id,signal_type,signal_source,explicit_or_behavioral,dimension,weight,occurred_at)
  VALUES (p_user_id,p_insight_id,p_signal_type,p_source,kind,dim,w,p_occurred_at)
  RETURNING id INTO ev;

  version_id := gen_random_uuid();
  INSERT INTO preference_state_versions(id,user_id,dimension,explicit_value,behavioral_value,source_kind,source_mix,confidence,derived_from_event_id,effective_at,decay_policy,version)
  VALUES (version_id,p_user_id,dim,new_explicit,new_behavioral,kind,jsonb_build_object('signal_type',p_signal_type,'source',p_source),CASE WHEN kind='explicit' THEN 1 ELSE 0.6 END,ev,p_occurred_at,CASE WHEN kind='explicit' THEN 'explicit_persists_behavioral_decays' ELSE 'behavioral_half_life_days:'||pol.behavioral_decay_days END,'001G-R1:'||version_id::text);

  RETURN ev;
END;
$$;

CREATE OR REPLACE FUNCTION psi_candidate_preference_adjustment(p_candidate_id uuid,p_as_of timestamptz DEFAULT now())
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  pol psi_orchestration_policy%ROWTYPE;
  dim text;
  pref numeric;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  dim := CASE
    WHEN c.candidate_type IN ('evidence_context','research_update','education') THEN 'research_detail'
    WHEN c.candidate_type IN ('experiment_result','optimization') THEN 'experiment_action_affinity'
    ELSE 'topic_affinity' END;
  pref := psi_effective_preference(c.user_id,dim,p_as_of);
  RETURN greatest(pol.adaptive_min,least(pol.adaptive_max,pref*pol.adaptive_max));
END;
$$;

CREATE OR REPLACE FUNCTION psi_rank_candidate(p_candidate_id uuid, p_preference_adjustment numeric DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  pol psi_orchestration_policy%ROWTYPE;
  tier_value text;
  base_value numeric;
  requested numeric;
  bounded numeric;
  final_value numeric;
  safety boolean;
  pref_version text := 'neutral';
  c insight_candidates%ROWTYPE;
BEGIN
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;
  tier_value := psi_priority_tier(p_candidate_id);
  base_value := CASE tier_value WHEN 'T0' THEN 400 WHEN 'T1' THEN 300 WHEN 'T2' THEN 200 WHEN 'T3' THEN 100 END;
  requested := coalesce(p_preference_adjustment,psi_candidate_preference_adjustment(p_candidate_id,now()));
  bounded := greatest(pol.adaptive_min,least(pol.adaptive_max,requested));
  final_value := base_value+bounded;
  safety := tier_value='T0';
  SELECT version INTO pref_version FROM preference_state_versions WHERE user_id=c.user_id ORDER BY effective_at DESC,id DESC LIMIT 1;
  pref_version := coalesce(pref_version,'neutral');

  INSERT INTO priority_decisions(candidate_id,tier,base_priority,priority_reasons,adaptive_adjustment,adaptive_sources,final_priority,safety_override,ranking_model_version,preference_state_version,policy_version)
  VALUES (p_candidate_id,tier_value,base_value,jsonb_build_array('hard_tier_'||tier_value),bounded,CASE WHEN p_preference_adjustment IS NULL THEN jsonb_build_array('bounded_user_preference') ELSE '[]'::jsonb END,final_value,safety,'001G-R1',pref_version,pol.policy_version);
  RETURN final_value;
END;
$$;
