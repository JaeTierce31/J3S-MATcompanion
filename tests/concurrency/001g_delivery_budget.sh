#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

u=$(psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "INSERT INTO users DEFAULT VALUES RETURNING id")
mk_candidate() {
  psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "WITH c AS (
    INSERT INTO insight_candidates(user_id,candidate_type,subject_type,subject_id,proposed_title,proposed_summary,authority_class)
    VALUES ('$u','experiment_result','experiment',gen_random_uuid(),'Concurrent T1','Concurrency fixture','advisory') RETURNING id
  ), e AS (
    INSERT INTO eligibility_decisions(candidate_id,decision,cooldown_state,authority_state,safety_state,policy_version)
    SELECT id,'ELIGIBLE','none','advisory','none','001G-R1' FROM c RETURNING candidate_id
  )
  SELECT psi_rank_candidate(candidate_id,0) FROM e;
  SELECT candidate_id FROM eligibility_decisions WHERE authority_state='advisory' AND candidate_id IN (SELECT id FROM insight_candidates WHERE user_id='$u') ORDER BY evaluated_at DESC LIMIT 1;" | tail -n1
}

c1=$(mk_candidate)
c2=$(mk_candidate)
tmp1=$(mktemp)
tmp2=$(mktemp)
trap 'rm -f "$tmp1" "$tmp2"' EXIT

psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "SELECT psi_delivery_decision('$c1','in_app',clock_timestamp())" >"$tmp1" &
p1=$!
psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "SELECT psi_delivery_decision('$c2','in_app',clock_timestamp())" >"$tmp2" &
p2=$!
wait "$p1"
wait "$p2"

r1=$(tail -n1 "$tmp1" | tr -d '[:space:]')
r2=$(tail -n1 "$tmp2" | tr -d '[:space:]')
if [[ "$(printf '%s\n%s\n' "$r1" "$r2" | sort | tr '\n' ' ')" != "BLOCKED DELIVER_NOW " ]]; then
  echo "unexpected contention results: $r1 / $r2" >&2
  exit 1
fi

active=$(psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "SELECT count(*) FROM delivery_events WHERE user_id='$u' AND tier='T1' AND active AND primary_attention AND delivered")
[[ "$active" == "1" ]] || { echo "expected exactly one active T1, got $active" >&2; exit 1; }
echo "CONC-001G PASS: one DELIVER_NOW, one BLOCKED, active_t1=1"
