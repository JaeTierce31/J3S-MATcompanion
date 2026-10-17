CREATE TABLE IF NOT EXISTS delivery_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id uuid NOT NULL REFERENCES insight_candidates(id),
  priority_decision_id uuid REFERENCES priority_decisions(id),
  user_id uuid NOT NULL,
  tier text NOT NULL CHECK (tier IN ('T0','T1','T2','T3')),
  surface text NOT NULL,
  delivery_type text NOT NULL CHECK (delivery_type IN ('DELIVER_NOW','DELIVER_IN_APP','DEFER_DIGEST','COLLAPSE','BLOCKED')),
  delivered boolean NOT NULL,
  primary_attention boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT false,
  cooldown_family text,
  budget_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivery_reason text NOT NULL,
  policy_version text NOT NULL REFERENCES psi_orchestration_policy(policy_version),
  delivered_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_delivery_user_tier_active ON delivery_events(user_id,tier,active) WHERE active;
DROP TRIGGER IF EXISTS trg_delivery_immutable ON delivery_events;
CREATE TRIGGER trg_delivery_immutable BEFORE UPDATE OR DELETE ON delivery_events FOR EACH ROW EXECUTE FUNCTION psi_receipt_immutable();

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
    SELECT count(*) INTO active_count FROM delivery_events WHERE user_id=c.user_id AND tier='T1' AND active AND primary_attention AND delivered;
    IF active_count >= pol.t1_active_limit THEN
      outcome := 'BLOCKED'; reason := 't1_active_limit';
    ELSE
      outcome := 'DELIVER_NOW'; is_delivered := true; is_primary := true; is_active := true; reason := 't1_budget_available';
    END IF;
  ELSIF pr.tier='T2' THEN
    SELECT count(*) INTO active_count FROM delivery_events WHERE user_id=c.user_id AND tier='T2' AND active AND delivered;
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
