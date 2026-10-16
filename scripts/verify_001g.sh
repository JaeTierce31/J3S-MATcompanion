#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

run_sql() {
  local file="$1"
  echo "==> $file"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
}

run_sql tests/sql/001g_policy_config.sql
run_sql tests/sql/001g_materiality.sql
run_sql tests/sql/001g_redundancy.sql
run_sql tests/sql/001g_eligibility.sql
run_sql tests/sql/001g_ranking.sql
run_sql tests/sql/001g_delivery_budget.sql
run_sql tests/sql/001g_learning.sql
run_sql tests/sql/001g_next_action.sql
run_sql tests/sql/001g_action_closure.sql
run_sql tests/sql/001g_delivery_resolution.sql
run_sql tests/sql/001g_auditability.sql
run_sql tests/sql/001g_degraded_mode.sql
run_sql tests/sql/001g_invariants.sql
run_sql tests/sql/001g_e2e.sql
run_sql tests/sql/001g_auth_regression.sql

bash tests/concurrency/001g_delivery_budget_atomic.sh

echo "PSI-CIM-001G verification PASS"
