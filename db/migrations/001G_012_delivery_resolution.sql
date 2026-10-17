CREATE TABLE IF NOT EXISTS delivery_resolution_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_event_id uuid NOT NULL UNIQUE REFERENCES delivery_events(id) ON DELETE RESTRICT,
  resolution_type text NOT NULL CHECK (resolution_type IN ('resolved','dismissed','superseded','expired','action_closed')),
  resolution_source text NOT NULL CHECK (length(trim(resolution_source)) > 0),
  related_action_outcome_id uuid REFERENCES action_outcomes(id) ON DELETE RESTRICT,
  policy_version text NOT NULL DEFAULT '001G-R1' REFERENCES psi_orchestration_policy(policy_version),
  resolved_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_delivery_resolution_immutable ON delivery_resolution_events;
CREATE TRIGGER trg_delivery_resolution_immutable
BEFORE UPDATE OR DELETE ON delivery_resolution_events
FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

CREATE OR REPLACE VIEW v_delivery_current_state AS
SELECT
  de.*,
  dr.id AS resolution_id,
  dr.resolution_type,
  dr.resolution_source,
  dr.related_action_outcome_id,
  dr.resolved_at,
  (de.delivered AND de.active AND dr.id IS NULL) AS currently_active
FROM delivery_events de
LEFT JOIN delivery_resolution_events dr ON dr.delivery_event_id=de.id;

CREATE OR REPLACE FUNCTION psi_resolve_delivery(
  p_delivery_event_id uuid,
  p_resolution_type text,
  p_resolution_source text,
  p_related_action_outcome_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  de delivery_events%ROWTYPE;
  existing_id uuid;
  result_id uuid;
  pol psi_orchestration_policy%ROWTYPE;
BEGIN
  SELECT * INTO STRICT de FROM delivery_events WHERE id=p_delivery_event_id;
  IF NOT de.delivered OR NOT de.active THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='only delivered active attention items can be resolved';
  END IF;
  IF p_resolution_type NOT IN ('resolved','dismissed','superseded','expired','action_closed') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid delivery resolution type';
  END IF;
  IF length(trim(coalesce(p_resolution_source,'')))=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='delivery resolution source is required';
  END IF;

  SELECT id INTO existing_id FROM delivery_resolution_events WHERE delivery_event_id=p_delivery_event_id;
  IF existing_id IS NOT NULL THEN
    RETURN existing_id;
  END IF;

  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  INSERT INTO delivery_resolution_events(
    delivery_event_id,resolution_type,resolution_source,related_action_outcome_id,policy_version
  ) VALUES (
    de.id,p_resolution_type,p_resolution_source,p_related_action_outcome_id,pol.policy_version
  ) RETURNING id INTO result_id;

  RETURN result_id;
END;
$$;

CREATE OR REPLACE FUNCTION psi_delivery_decision(p_candidate_id uuid, p_surface text, p_now timestamptz)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  c insight_candidates%ROWTYPE;
  pr priority_decisions%ROWTYPE;
  pol psi_orchestration_policy%ROWTYPE;
  cp psi_delivery_cooldown_policy%ROWTYPE;
  active_count integer := 0;
  outcome text;
  is_delivered boolean := false;
  is_primary boolean := false;
  is_active boolean := false;
  reason text;
BEGIN
  SELECT * INTO STRICT c FROM insight_candidates WHERE id=p_candidate_id;
  SELECT * INTO STRICT pol FROM psi_active_orchestration_policy();
  SELECT * INTO pr FROM priority_decisions WHERE candidate_id=p_candidate_id ORDER BY decided_at DESC LIMIT 1;
  IF NOT FOUND THEN
    PERFORM psi_rank_candidate(p_candidate_id,0);
    SELECT * INTO STRICT pr FROM priority_decisions WHERE candidate_id=p_candidate_id ORDER BY decided_at DESC LIMIT 1;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(c.user_id::text || ':' || pr.tier,0));

  IF pr.tier='T0' THEN
    outcome := 'DELIVER_NOW'; is_delivered := true; is_primary := true; is_active := true; reason := 'safety_bypass';
  ELSIF pr.tier='T1' THEN
    SELECT count(*) INTO active_count
    FROM v_delivery_current_state
    WHERE user_id=c.user_id AND tier='T1' AND currently_active AND primary_attention;
    IF active_count >= pol.t1_active_limit THEN
      outcome := 'BLOCKED'; reason := 't1_active_limit';
    ELSE
      outcome := 'DELIVER_NOW'; is_delivered := true; is_primary := true; is_active := true; reason := 't1_budget_available';
    END IF;
  ELSIF pr.tier='T2' THEN
    SELECT count(*) INTO active_count
    FROM v_delivery_current_state
    WHERE user_id=c.user_id AND tier='T2' AND currently_active;
    IF active_count >= pol.t2_visible_limit THEN
      outcome := 'COLLAPSE'; reason := 't2_visible_limit';
    ELSE
      outcome := 'DELIVER_IN_APP'; is_delivered := true; is_active := true; reason := 't2_budget_available';
    END IF;
  ELSE
    IF p_surface='in_app' THEN
      outcome := 'DELIVER_IN_APP'; is_delivered := true; reason := 't3_in_app_only';
    ELSE
      outcome := 'DEFER_DIGEST'; reason := 't3_digest_default';
    END IF;
  END IF;

  SELECT * INTO cp FROM psi_delivery_cooldown_policy WHERE policy_version=pol.policy_version AND candidate_type=c.candidate_type;

  INSERT INTO delivery_events(candidate_id,priority_decision_id,user_id,tier,surface,delivery_type,delivered,primary_attention,active,cooldown_family,budget_state,delivery_reason,policy_version,delivered_at)
  VALUES (c.id,pr.id,c.user_id,pr.tier,p_surface,outcome,is_delivered,is_primary,is_active,cp.cooldown_family,
          jsonb_build_object('active_count_before',active_count,'t1_limit',pol.t1_active_limit,'t2_limit',pol.t2_visible_limit),reason,pol.policy_version,p_now);

  IF is_delivered AND cp.cooldown_family IS NOT NULL THEN
    INSERT INTO delivery_cooldown_state(user_id,cooldown_family,last_delivered_at)
    VALUES (c.user_id,cp.cooldown_family,p_now)
    ON CONFLICT (user_id,cooldown_family) DO UPDATE SET last_delivered_at=excluded.last_delivered_at;
  END IF;

  RETURN outcome;
END;
$$;

CREATE OR REPLACE FUNCTION psi_resolve_delivery_from_action_outcome()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  insight_id_value uuid;
  delivery_id_value uuid;
BEGIN
  SELECT nad.insight_id INTO insight_id_value
  FROM action_executions ae
  JOIN next_action_decisions nad ON nad.id=ae.decision_id
  WHERE ae.id=NEW.execution_id;

  IF insight_id_value IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT vcs.id INTO delivery_id_value
  FROM v_delivery_current_state vcs
  JOIN insight_candidates c ON c.id=vcs.candidate_id
  WHERE c.materialized_insight_id=insight_id_value
    AND vcs.currently_active
  ORDER BY vcs.delivered_at DESC, vcs.id DESC
  LIMIT 1;

  IF delivery_id_value IS NOT NULL THEN
    PERFORM psi_resolve_delivery(delivery_id_value,'action_closed','action_outcome',NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_action_outcome_resolve_delivery ON action_outcomes;
CREATE TRIGGER trg_action_outcome_resolve_delivery
AFTER INSERT ON action_outcomes
FOR EACH ROW EXECUTE FUNCTION psi_resolve_delivery_from_action_outcome();

CREATE OR REPLACE FUNCTION api_orchestration_receipt(p_insight_or_candidate_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path=public
AS $$
  WITH base AS (
    SELECT psi_orchestration_receipt(p_insight_or_candidate_id,psi_current_user_from_auth()) AS receipt
  ), resolution AS (
    SELECT to_jsonb(dr) AS resolution
    FROM insight_candidates c
    JOIN delivery_events de ON de.candidate_id=c.id
    JOIN delivery_resolution_events dr ON dr.delivery_event_id=de.id
    WHERE c.user_id=psi_current_user_from_auth()
      AND (c.id=p_insight_or_candidate_id OR c.materialized_insight_id=p_insight_or_candidate_id)
    ORDER BY dr.resolved_at DESC,dr.id DESC
    LIMIT 1
  )
  SELECT base.receipt || jsonb_build_object('delivery_resolution',(SELECT resolution FROM resolution))
  FROM base;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    REVOKE ALL ON delivery_resolution_events FROM psi_dashboard_reader;
    REVOKE ALL ON v_delivery_current_state FROM psi_dashboard_reader;
  END IF;
END $$;
