-- PSI-CIM-001F-DEFINITION-RECONCILIATION-002
-- RUNTIME_RECOVERED — NOT original signed history.
-- Definitions below are transcribed from pg_get_functiondef()/pg_get_viewdef()
-- on verified runtime polished-resonance-55615569 / br-shiny-mode-b807pp2e.
-- Purpose: reconcile same-name definition drift after exact signed 001B–001F replay.

BEGIN;

CREATE OR REPLACE VIEW v_personalized_knowledge_graph WITH (security_invoker=true) AS
 SELECT subject_type,
    subject_id,
    predicate,
    object_type,
    object_id,
    confidence,
    provenance_source_id,
    valid_from,
    valid_to
   FROM knowledge_edges ke;

CREATE OR REPLACE FUNCTION public.api_dashboard_attention()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.priority DESC,v.created_at DESC),'[]'::jsonb) FROM v_user_attention_queue v WHERE v.user_id=psi_current_user_from_auth() AND v.status='open' $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_decision_feed()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.generated_at DESC),'[]'::jsonb) FROM v_user_decision_feed v WHERE v.user_id=psi_current_user_from_auth() AND v.status='active' $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_dossiers()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.canonical_name),'[]'::jsonb) FROM v_dashboard_dossiers v $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_experiments()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.start_date DESC NULLS LAST),'[]'::jsonb) FROM v_dashboard_experiments v WHERE v.user_id=psi_current_user_from_auth() $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_insights()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.generated_at DESC),'[]'::jsonb) FROM v_user_insight_feed v WHERE v.user_id=psi_current_user_from_auth() AND v.status='active' $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_interactions()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.priority DESC),'[]'::jsonb) FROM v_dashboard_interactions v $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_outcomes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.created_at DESC),'[]'::jsonb) FROM v_dashboard_outcomes v JOIN experiments e ON e.id=v.experiment_id WHERE e.user_id=psi_current_user_from_auth() $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_research()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.year DESC NULLS LAST),'[]'::jsonb) FROM v_dashboard_research v $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_safety()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.safety_priority DESC),'[]'::jsonb) FROM v_dashboard_safety v $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_stack()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.start_date NULLS LAST),'[]'::jsonb) FROM v_dashboard_stack v WHERE v.user_id=psi_current_user_from_auth() $function$;

CREATE OR REPLACE FUNCTION public.api_dashboard_today()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(to_jsonb(v),'{}'::jsonb) FROM v_dashboard_today v WHERE v.user_id=psi_current_user_from_auth() $function$;

CREATE OR REPLACE FUNCTION public.api_claim_applicability(p_ingredient uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(jsonb_build_object('claim_id',c.id,'claim_type',c.claim_type,'predicate',c.predicate,'object_text',c.object_text,'study_id',s.id,'study_title',s.title,'pmid',s.pmid,'doi',s.doi,'dimension',m.dimension,'applicability',m.applicability,'rationale',m.rationale) ORDER BY c.object_text,s.year DESC,m.dimension),'[]'::jsonb) FROM claims c JOIN claim_applicability_matrices m ON m.claim_id=c.id JOIN studies s ON s.id=m.study_id WHERE c.subject_type='ingredient' AND c.subject_id=p_ingredient $function$;

CREATE OR REPLACE FUNCTION public.api_experiment_readiness(p_experiment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ DECLARE uid uuid; owner_id uuid; BEGIN uid:=psi_current_user_from_auth(); SELECT user_id INTO owner_id FROM experiments WHERE id=p_experiment; IF owner_id IS NULL OR owner_id<>uid THEN RAISE EXCEPTION 'EXPERIMENT_NOT_ACCESSIBLE'; END IF; RETURN psi_experiment_readiness(p_experiment)||jsonb_build_object('next_action',psi_experiment_next_action(p_experiment)); END $function$;

CREATE OR REPLACE FUNCTION public.api_recommendation_trace(p_recommendation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ DECLARE uid uuid; owner_id uuid; BEGIN uid:=psi_current_user_from_auth(); SELECT user_id INTO owner_id FROM recommendations WHERE id=p_recommendation; IF owner_id IS NULL OR owner_id<>uid THEN RAISE EXCEPTION 'RECOMMENDATION_NOT_ACCESSIBLE'; END IF; RETURN psi_recommendation_trace(p_recommendation); END $function$;

CREATE OR REPLACE FUNCTION public.api_user_metric_daily(p_metric text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(jsonb_build_object('day',day,'n',n,'avg',avg_value,'min',min_value,'max',max_value,'last',last_value) ORDER BY day),'[]'::jsonb) FROM observation_daily_rollups WHERE user_id=psi_current_user_from_auth() AND metric=p_metric AND day BETWEEN p_from AND p_to $function$;

CREATE OR REPLACE FUNCTION public.api_user_metric_weekly(p_metric text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ SELECT COALESCE(jsonb_agg(jsonb_build_object('week_start',week_start,'n',n,'avg',avg_value,'min',min_value,'max',max_value,'last',last_value) ORDER BY week_start),'[]'::jsonb) FROM observation_weekly_rollups WHERE user_id=psi_current_user_from_auth() AND metric=p_metric AND week_start BETWEEN p_from AND p_to $function$;

CREATE OR REPLACE FUNCTION public.psi_authority_guard(p_authority text, p_action text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$ SELECT CASE WHEN p_authority='reserved' THEN 'REQUIRES_USER_OR_CLINICIAN' WHEN p_authority='advisory' THEN 'PRESENT_FOR_USER_DECISION' ELSE 'INFORMATIONAL_ONLY' END; $function$;

CREATE OR REPLACE FUNCTION public.psi_baseline_sufficiency(p_experiment uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ WITH p AS (SELECT e.id,e.start_date,coalesce(ep.min_baseline_days,7) min_days,coalesce(ep.min_baseline_observations,5) min_obs FROM experiments e LEFT JOIN experiment_protocols ep ON ep.experiment_id=e.id WHERE e.id=p_experiment), b AS (SELECT count(*) obs_count,count(DISTINCT (o.observed_at AT TIME ZONE 'UTC')::date) day_count FROM observations o,p WHERE o.experiment_id=p.id AND (p.start_date IS NULL OR o.observed_at::date < p.start_date)) SELECT jsonb_build_object('observation_count',b.obs_count,'day_count',b.day_count,'required_observations',p.min_obs,'required_days',p.min_days,'sufficient',(b.obs_count>=p.min_obs AND b.day_count>=p.min_days)) FROM p,b $function$;

CREATE OR REPLACE FUNCTION public.psi_current_user_from_auth()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$ DECLARE sub text; uid uuid; BEGIN sub:=auth.user_id(); IF sub IS NULL OR sub='' THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF; SELECT user_id INTO uid FROM user_auth_identities WHERE auth_provider='neon_auth' AND auth_subject=sub AND active; IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_SUBJECT_UNMAPPED'; END IF; RETURN uid; END $function$;

CREATE OR REPLACE FUNCTION public.psi_experiment_next_action(p_experiment uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$ DECLARE r jsonb; s text; BEGIN r:=psi_experiment_readiness(p_experiment); s:=r->>'status'; IF (r->'protocol_signal'->>'review_required')::boolean THEN RETURN 'REVIEW_PROTOCOL'; END IF; IF s='decision' THEN RETURN 'DECISION_RECORDED'; END IF; IF s='analyzed' THEN RETURN 'ELIGIBLE_FOR_DECISION'; END IF; IF s='completed' THEN RETURN 'ELIGIBLE_TO_ANALYZE'; END IF; IF NOT (r->'washout'->>'sufficient')::boolean THEN RETURN 'COMPLETE_WASHOUT'; END IF; IF NOT (r->'baseline'->>'sufficient')::boolean THEN RETURN 'COLLECT_BASELINE'; END IF; IF s='baseline' THEN RETURN 'ELIGIBLE_TO_ACTIVATE'; END IF; IF s='active' AND NOT (r->>'adherence_sufficient')::boolean THEN RETURN 'IMPROVE_ADHERENCE'; END IF; IF s='active' AND NOT (r->>'confounders_acceptable')::boolean THEN RETURN 'REDUCE_OR_ANNOTATE_CONFOUNDERS'; END IF; IF s='active' AND (r->>'intervention_observations_sufficient')::boolean THEN RETURN 'CONTINUE_OR_COMPLETE_PER_PROTOCOL'; END IF; RETURN 'CONTINUE_PROTOCOL'; END $function$;

CREATE OR REPLACE FUNCTION public.psi_experiment_readiness(p_experiment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$ DECLARE e experiments%ROWTYPE; p experiment_protocols%ROWTYPE; baseline jsonb; washout jsonb; signal jsonb; adh numeric; conf numeric; intervention_obs bigint; BEGIN SELECT * INTO e FROM experiments WHERE id=p_experiment; IF NOT FOUND THEN RAISE EXCEPTION 'EXPERIMENT_NOT_FOUND'; END IF; SELECT * INTO p FROM experiment_protocols WHERE experiment_id=p_experiment; IF NOT FOUND THEN p.min_baseline_days:=7; p.min_baseline_observations:=5; p.min_intervention_observations:=5; p.washout_days:=0; p.max_confounder_score:=0.35; p.adherence_floor:=0.80; END IF; baseline:=psi_baseline_sufficiency(p_experiment); washout:=psi_washout_sufficiency(p_experiment); signal:=psi_protocol_signal(p_experiment); SELECT coalesce(avg(adherence),1),coalesce(avg(confounder_score),0) INTO adh,conf FROM experiment_checkins WHERE experiment_id=p_experiment; SELECT count(*) INTO intervention_obs FROM observations o WHERE o.experiment_id=p_experiment AND (e.start_date IS NULL OR o.observed_at::date>=e.start_date); RETURN jsonb_build_object('experiment_id',p_experiment,'status',e.status,'baseline',baseline,'washout',washout,'protocol_signal',signal,'adherence_score',adh,'adherence_sufficient',adh>=p.adherence_floor,'confounder_score',conf,'confounders_acceptable',conf<=p.max_confounder_score,'intervention_observations',intervention_obs,'intervention_observations_sufficient',intervention_obs>=p.min_intervention_observations); END $function$;

CREATE OR REPLACE FUNCTION public.psi_insight_confidence(p_data numeric, p_temporal numeric, p_adherence numeric, p_confounder_control numeric, p_science numeric, p_population numeric, p_dose numeric, p_formulation numeric, p_endpoint numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$ SELECT LEAST(1,GREATEST(0, sqrt(GREATEST(0,p_data*p_temporal*p_adherence*p_confounder_control)) * sqrt(GREATEST(0,p_science*p_population*p_dose*p_formulation*p_endpoint)) )); $function$;

CREATE OR REPLACE FUNCTION public.psi_protocol_signal(p_experiment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$ DECLARE rules jsonb; adverse boolean; adh numeric; hard_floor numeric; review_on_adverse boolean; BEGIN SELECT coalesce(stopping_rules,'{}'::jsonb) INTO rules FROM experiment_protocols WHERE experiment_id=p_experiment; SELECT coalesce(bool_or(adverse_event),false),coalesce(avg(adherence),1) INTO adverse,adh FROM experiment_checkins WHERE experiment_id=p_experiment; review_on_adverse:=coalesce((rules->>'stop_on_adverse_event')::boolean,true); hard_floor:=coalesce((rules->>'min_adherence_hard_stop')::numeric,0); RETURN jsonb_build_object('review_required',((review_on_adverse AND adverse) OR (hard_floor>0 AND adh<hard_floor)),'adverse_event',adverse,'mean_adherence',adh,'reason',CASE WHEN review_on_adverse AND adverse THEN 'ADVERSE_EVENT' WHEN hard_floor>0 AND adh<hard_floor THEN 'ADHERENCE_BELOW_PROTOCOL_FLOOR' ELSE NULL END); END $function$;

CREATE OR REPLACE FUNCTION public.psi_recommendation_trace(p_recommendation uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ SELECT COALESCE(jsonb_agg(jsonb_build_object('depth',depth,'subject_type',subject_type,'subject_id',subject_id,'predicate',predicate,'object_type',object_type,'object_id',object_id) ORDER BY depth),'[]'::jsonb) FROM v_recommendation_trace_edges WHERE root_recommendation_id=p_recommendation $function$;

CREATE OR REPLACE FUNCTION public.psi_refresh_daily_rollups(p_from date, p_to date)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$ DECLARE affected bigint; BEGIN INSERT INTO observation_daily_rollups(user_id,metric,day,n,avg_value,min_value,max_value,stddev_value,first_value,last_value,first_observed_at,last_observed_at,source_mix,refreshed_at) SELECT o.user_id,o.metric,(o.observed_at AT TIME ZONE 'UTC')::date,count(*),avg(o.value_numeric),min(o.value_numeric),max(o.value_numeric),stddev_samp(o.value_numeric),(array_agg(o.value_numeric ORDER BY o.observed_at ASC) FILTER (WHERE o.value_numeric IS NOT NULL))[1],(array_agg(o.value_numeric ORDER BY o.observed_at DESC) FILTER (WHERE o.value_numeric IS NOT NULL))[1],min(o.observed_at),max(o.observed_at),'{}'::jsonb,now() FROM observations o WHERE o.observed_at >= p_from::timestamptz AND o.observed_at < (p_to+1)::timestamptz GROUP BY o.user_id,o.metric,(o.observed_at AT TIME ZONE 'UTC')::date ON CONFLICT(user_id,metric,day) DO UPDATE SET n=EXCLUDED.n,avg_value=EXCLUDED.avg_value,min_value=EXCLUDED.min_value,max_value=EXCLUDED.max_value,stddev_value=EXCLUDED.stddev_value,first_value=EXCLUDED.first_value,last_value=EXCLUDED.last_value,first_observed_at=EXCLUDED.first_observed_at,last_observed_at=EXCLUDED.last_observed_at,source_mix=EXCLUDED.source_mix,refreshed_at=now(); GET DIAGNOSTICS affected=ROW_COUNT; RETURN affected; END $function$;

CREATE OR REPLACE FUNCTION public.psi_refresh_weekly_rollups(p_from date, p_to date)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$ DECLARE affected bigint; BEGIN INSERT INTO observation_weekly_rollups(user_id,metric,week_start,n,avg_value,min_value,max_value,stddev_value,first_value,last_value,first_observed_at,last_observed_at,refreshed_at) SELECT d.user_id,d.metric,date_trunc('week',d.day)::date,sum(d.n),CASE WHEN sum(d.n)>0 THEN sum(d.avg_value*d.n)/sum(d.n) END,min(d.min_value),max(d.max_value),NULL,(array_agg(d.first_value ORDER BY d.day ASC) FILTER(WHERE d.first_value IS NOT NULL))[1],(array_agg(d.last_value ORDER BY d.day DESC) FILTER(WHERE d.last_value IS NOT NULL))[1],min(d.first_observed_at),max(d.last_observed_at),now() FROM observation_daily_rollups d WHERE d.day BETWEEN p_from AND p_to GROUP BY d.user_id,d.metric,date_trunc('week',d.day)::date ON CONFLICT(user_id,metric,week_start) DO UPDATE SET n=EXCLUDED.n,avg_value=EXCLUDED.avg_value,min_value=EXCLUDED.min_value,max_value=EXCLUDED.max_value,stddev_value=EXCLUDED.stddev_value,first_value=EXCLUDED.first_value,last_value=EXCLUDED.last_value,first_observed_at=EXCLUDED.first_observed_at,last_observed_at=EXCLUDED.last_observed_at,refreshed_at=now(); GET DIAGNOSTICS affected=ROW_COUNT; RETURN affected; END $function$;

CREATE OR REPLACE FUNCTION public.psi_washout_sufficiency(p_experiment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$ DECLARE e experiments%ROWTYPE; req int; min_gap int; BEGIN SELECT * INTO e FROM experiments WHERE id=p_experiment; IF NOT FOUND THEN RAISE EXCEPTION 'EXPERIMENT_NOT_FOUND'; END IF; SELECT coalesce(washout_days,0) INTO req FROM experiment_protocols WHERE experiment_id=p_experiment; req:=coalesce(req,0); IF req=0 OR e.start_date IS NULL THEN RETURN jsonb_build_object('required_days',req,'observed_gap_days',NULL,'sufficient',true); END IF; SELECT min(e.start_date - prior.end_date) INTO min_gap FROM experiment_interventions cur JOIN experiments prior ON prior.user_id=e.user_id AND prior.id<>e.id AND prior.end_date IS NOT NULL AND prior.end_date<e.start_date AND prior.status IN('completed','analyzed','decision') JOIN experiment_interventions pi ON pi.experiment_id=prior.id AND pi.intervention_type=cur.intervention_type AND pi.intervention_ref_id=cur.intervention_ref_id WHERE cur.experiment_id=e.id; RETURN jsonb_build_object('required_days',req,'observed_gap_days',min_gap,'sufficient',(min_gap IS NULL OR min_gap>=req)); END $function$;

CREATE OR REPLACE FUNCTION public.trg_decision_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE ac text; rt text;
BEGIN
  IF NEW.recommendation_id IS NOT NULL THEN
    SELECT authority_class,recommendation_type INTO ac,rt FROM recommendations WHERE id=NEW.recommendation_id;
    IF ac='reserved' AND NEW.actor_type NOT IN('user','clinician') THEN RAISE EXCEPTION 'INV-042/045 reserved action requires user or clinician'; END IF;
    IF rt='change_prescription' AND NEW.actor_type NOT IN('user','clinician') THEN RAISE EXCEPTION 'INV-041/042 prescription changes cannot be delegated to assistant automation'; END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.trg_event_chain()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE prior text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.aggregate_type||':'||NEW.aggregate_id::text,0));
  SELECT event_hash INTO prior FROM event_ledger
   WHERE aggregate_type=NEW.aggregate_type AND aggregate_id=NEW.aggregate_id
   ORDER BY occurred_at DESC,id DESC LIMIT 1;
  NEW.previous_hash:=prior;
  NEW.event_hash:=canonical_event_hash(
    NEW.aggregate_type,NEW.aggregate_id,NEW.event_type,NEW.payload,NEW.previous_hash,NEW.occurred_at
  );
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.trg_outcome_insert_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE cnt int; maxv int; expid uuid;
BEGIN
  SELECT experiment_id INTO expid FROM observation_sets WHERE id=NEW.observation_set_id;
  IF expid IS DISTINCT FROM NEW.experiment_id THEN
    RAISE EXCEPTION 'INV-039 outcome observation set belongs to different experiment';
  END IF;
  SELECT count(*) INTO cnt FROM observation_set_members WHERE observation_set_id=NEW.observation_set_id;
  IF cnt<1 THEN RAISE EXCEPTION 'INV-039 outcome requires identifiable observations'; END IF;
  SELECT COALESCE(max(version),0) INTO maxv FROM outcomes WHERE experiment_id=NEW.experiment_id AND metric=NEW.metric;
  IF NEW.version<>maxv+1 THEN RAISE EXCEPTION 'INV-040 outcome version must be %',maxv+1; END IF;
  IF NEW.attribution_confidence>=0.50 AND EXISTS(SELECT 1 FROM experiments e WHERE e.id=NEW.experiment_id AND COALESCE(e.baseline_days,0)=0) THEN
    RAISE EXCEPTION 'INV-037 no baseline cannot produce >=0.50 attribution';
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.trg_recommendation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE src_count int;
BEGIN
  IF NEW.authority_class='reserved' AND NEW.safety_gate_status='pass' THEN NEW.safety_gate_status:='review_required'; END IF;
  IF NEW.status IN('validated','presented') THEN
    SELECT count(*) INTO src_count FROM recommendation_sources WHERE recommendation_id=NEW.id;
    IF src_count<1 THEN RAISE EXCEPTION 'INV-046 validated/presented recommendation requires provenance'; END IF;
  END IF;
  RETURN NEW;
END $function$;

COMMIT;
