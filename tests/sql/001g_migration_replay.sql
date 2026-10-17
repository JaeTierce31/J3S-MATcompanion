DO $$
DECLARE
  active_policies integer;
BEGIN
  SELECT count(*) INTO active_policies FROM psi_orchestration_policy WHERE active;
  IF active_policies <> 1 THEN RAISE EXCEPTION 'expected exactly one active 001G policy after replay'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='change_signals' AND relkind='r') THEN RAISE EXCEPTION 'change_signals missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='insight_fingerprints' AND relkind='r') THEN RAISE EXCEPTION 'insight_fingerprints missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='eligibility_decisions' AND relkind='r') THEN RAISE EXCEPTION 'eligibility_decisions missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='priority_decisions' AND relkind='r') THEN RAISE EXCEPTION 'priority_decisions missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='delivery_events' AND relkind='r') THEN RAISE EXCEPTION 'delivery_events missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='delivery_resolution_events' AND relkind='r') THEN RAISE EXCEPTION 'delivery_resolution_events missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='usefulness_events' AND relkind='r') THEN RAISE EXCEPTION 'usefulness_events missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='next_action_decisions' AND relkind='r') THEN RAISE EXCEPTION 'next_action_decisions missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='action_outcomes' AND relkind='r') THEN RAISE EXCEPTION 'action_outcomes missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='orchestration_runtime_events' AND relkind='r') THEN RAISE EXCEPTION 'orchestration_runtime_events missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='v_delivery_current_state' AND relkind='v') THEN RAISE EXCEPTION 'delivery current-state view missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='v_psi_orchestration_receipt' AND relkind='v') THEN RAISE EXCEPTION 'orchestration receipt view missing'; END IF;

  IF to_regprocedure('psi_evaluate_materiality(uuid)') IS NULL THEN RAISE EXCEPTION 'materiality oracle missing'; END IF;
  IF to_regprocedure('psi_classify_candidate(uuid)') IS NULL THEN RAISE EXCEPTION 'redundancy oracle missing'; END IF;
  IF to_regprocedure('psi_evaluate_eligibility(uuid,timestamptz)') IS NULL THEN RAISE EXCEPTION 'eligibility oracle missing'; END IF;
  IF to_regprocedure('psi_rank_candidate_safe(uuid)') IS NULL THEN RAISE EXCEPTION 'safe ranking oracle missing'; END IF;
  IF to_regprocedure('psi_delivery_decision(uuid,text,timestamptz)') IS NULL THEN RAISE EXCEPTION 'delivery oracle missing'; END IF;
  IF to_regprocedure('psi_resolve_delivery(uuid,text,text,uuid)') IS NULL THEN RAISE EXCEPTION 'delivery resolution oracle missing'; END IF;
  IF to_regprocedure('psi_orchestration_attention_for_user(uuid)') IS NULL THEN RAISE EXCEPTION 'active attention projection missing'; END IF;
  IF to_regprocedure('psi_select_next_action(uuid)') IS NULL THEN RAISE EXCEPTION 'next-action oracle missing'; END IF;
  IF to_regprocedure('psi_close_action(uuid,text,numeric,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'action closure oracle missing'; END IF;
  IF to_regprocedure('api_orchestration_receipt(uuid)') IS NULL THEN RAISE EXCEPTION 'receipt API missing'; END IF;
  IF to_regprocedure('api_orchestration_attention()') IS NULL THEN RAISE EXCEPTION 'attention API missing'; END IF;
END $$;
