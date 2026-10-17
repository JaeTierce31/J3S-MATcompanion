-- PSI-CIM-001C runtime hardening patch
-- Apply AFTER 001B_base.sql.
-- Secrets are NOT provisioned here; deployment/CI provisions runtime keys separately.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    CREATE ROLE psi_dashboard_reader NOLOGIN;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_observations_observed_brin
  ON observations USING brin(observed_at);
CREATE INDEX IF NOT EXISTS idx_event_ledger_occurred_brin
  ON event_ledger USING brin(occurred_at);

-- Ensure serialization is per aggregate before prior-hash lookup.
CREATE OR REPLACE FUNCTION trg_event_chain() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE prior text;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended(NEW.aggregate_type || ':' || NEW.aggregate_id::text, 0)
  );

  SELECT event_hash INTO prior
  FROM event_ledger
  WHERE aggregate_type=NEW.aggregate_type
    AND aggregate_id=NEW.aggregate_id
  ORDER BY occurred_at DESC,id DESC
  LIMIT 1;

  NEW.previous_hash := prior;
  NEW.event_hash := canonical_event_hash(
    NEW.aggregate_type,NEW.aggregate_id,NEW.event_type,
    NEW.payload,NEW.previous_hash,NEW.occurred_at
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS event_chain_before_insert ON event_ledger;
CREATE TRIGGER event_chain_before_insert
BEFORE INSERT ON event_ledger
FOR EACH ROW EXECUTE FUNCTION trg_event_chain();

-- Cryptographic API-context verifier.
CREATE TABLE IF NOT EXISTS psi_auth_keys(
  key_id text PRIMARY KEY,
  secret bytea NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON psi_auth_keys FROM PUBLIC;
REVOKE ALL ON psi_auth_keys FROM psi_dashboard_reader;

CREATE OR REPLACE FUNCTION psi_verify_context(
  p_key_id text,
  p_user_id uuid,
  p_subject text,
  p_exp_epoch bigint,
  p_nonce text,
  p_sig_hex text
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM psi_auth_keys k
    WHERE k.key_id=p_key_id
      AND k.active
      AND p_exp_epoch >= extract(epoch from clock_timestamp())::bigint
      AND lower(p_sig_hex)=encode(
        hmac(
          convert_to(
            concat_ws('|',p_key_id,p_user_id::text,p_subject,p_exp_epoch::text,p_nonce),
            'UTF8'
          ),
          k.secret,
          'sha256'
        ),
        'hex'
      )
  )
$$;
REVOKE ALL ON FUNCTION psi_verify_context(text,uuid,text,bigint,text,text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION api_accept_context(
  p_key_id text,
  p_user_id uuid,
  p_subject text,
  p_exp_epoch bigint,
  p_nonce text,
  p_sig_hex text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT psi_verify_context(p_key_id,p_user_id,p_subject,p_exp_epoch,p_nonce,p_sig_hex) THEN
    RAISE EXCEPTION 'AUTHCTX_INVALID';
  END IF;

  PERFORM set_config('psi.auth_kid',p_key_id,true);
  PERFORM set_config('psi.auth_user_id',p_user_id::text,true);
  PERFORM set_config('psi.auth_sub',p_subject,true);
  PERFORM set_config('psi.auth_exp',p_exp_epoch::text,true);
  PERFORM set_config('psi.auth_nonce',p_nonce,true);
  PERFORM set_config('psi.auth_sig',lower(p_sig_hex),true);
END $$;
REVOKE ALL ON FUNCTION api_accept_context(text,uuid,text,bigint,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api_accept_context(text,uuid,text,bigint,text,text)
TO psi_dashboard_reader;

CREATE OR REPLACE FUNCTION psi_current_verified_user()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE
  kid text := current_setting('psi.auth_kid',true);
  uid_text text := current_setting('psi.auth_user_id',true);
  sub text := current_setting('psi.auth_sub',true);
  exp_text text := current_setting('psi.auth_exp',true);
  nonce text := current_setting('psi.auth_nonce',true);
  sig text := current_setting('psi.auth_sig',true);
  uid uuid;
  exp bigint;
BEGIN
  IF kid IS NULL OR uid_text IS NULL OR sub IS NULL OR exp_text IS NULL
     OR nonce IS NULL OR sig IS NULL
     OR kid='' OR uid_text='' OR sub='' OR exp_text='' OR nonce='' OR sig='' THEN
    RAISE EXCEPTION 'AUTHCTX_MISSING';
  END IF;

  uid := uid_text::uuid;
  exp := exp_text::bigint;

  IF NOT psi_verify_context(kid,uid,sub,exp,nonce,sig) THEN
    RAISE EXCEPTION 'AUTHCTX_INVALID';
  END IF;

  RETURN uid;
END $$;
REVOKE ALL ON FUNCTION psi_current_verified_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION psi_current_verified_user() TO psi_dashboard_reader;

-- User-scoped read APIs are bound to verified context.
CREATE OR REPLACE FUNCTION api_dashboard_stack()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.start_date NULLS LAST),'[]'::jsonb)
  FROM v_dashboard_stack v
  WHERE v.user_id=psi_current_verified_user()
$$;

CREATE OR REPLACE FUNCTION api_dashboard_experiments()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.start_date DESC NULLS LAST),'[]'::jsonb)
  FROM v_dashboard_experiments v
  WHERE v.user_id=psi_current_verified_user()
$$;

CREATE OR REPLACE FUNCTION api_dashboard_outcomes()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.created_at DESC),'[]'::jsonb)
  FROM v_dashboard_outcomes v
  JOIN experiments e ON e.id=v.experiment_id
  WHERE e.user_id=psi_current_verified_user()
$$;

CREATE OR REPLACE FUNCTION api_dashboard_today()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(to_jsonb(v),'{}'::jsonb)
  FROM v_dashboard_today v
  WHERE v.user_id=psi_current_verified_user()
$$;

-- Reference APIs remain global/reference-data surfaces.
CREATE OR REPLACE FUNCTION api_dashboard_dossiers()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.canonical_name),'[]'::jsonb)
  FROM v_dashboard_dossiers v
$$;

CREATE OR REPLACE FUNCTION api_dashboard_research()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.year DESC NULLS LAST),'[]'::jsonb)
  FROM v_dashboard_research v
$$;

CREATE OR REPLACE FUNCTION api_dashboard_safety()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.safety_priority DESC),'[]'::jsonb)
  FROM v_dashboard_safety v
$$;

CREATE OR REPLACE FUNCTION api_dashboard_interactions()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.priority DESC),'[]'::jsonb)
  FROM v_dashboard_interactions v
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM psi_dashboard_reader;
GRANT USAGE ON SCHEMA public TO psi_dashboard_reader;
REVOKE SELECT ON
  v_dashboard_stack,v_dashboard_dossiers,v_dashboard_interactions,
  v_dashboard_experiments,v_dashboard_outcomes,v_dashboard_safety,
  v_dashboard_research,v_dashboard_today
FROM psi_dashboard_reader;

REVOKE ALL ON FUNCTION
  api_dashboard_stack(),api_dashboard_experiments(),api_dashboard_outcomes(),
  api_dashboard_today(),api_dashboard_dossiers(),api_dashboard_research(),
  api_dashboard_safety(),api_dashboard_interactions()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  api_dashboard_stack(),api_dashboard_experiments(),api_dashboard_outcomes(),
  api_dashboard_today(),api_dashboard_dossiers(),api_dashboard_research(),
  api_dashboard_safety(),api_dashboard_interactions()
TO psi_dashboard_reader;

COMMIT;
