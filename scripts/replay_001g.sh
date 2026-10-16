#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

required=(users personal_insights insight_confidence_components decisions interactions)
for rel in "${required[@]}"; do
  exists=$(psql "$DATABASE_URL" -Atv ON_ERROR_STOP=1 -c "SELECT to_regclass('public.$rel') IS NOT NULL")
  [[ "$exists" == "t" ]] || { echo "BLOCKED: verified 001D-001F runtime baseline relation missing: $rel" >&2; exit 2; }
done

apply_once() {
  for f in db/migrations/001G_*.sql; do
    echo "apply $f"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
  done
}

apply_once
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/sql/001g_migration_replay.sql
apply_once
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/sql/001g_migration_replay.sql

echo "REPLAY-001G PASS: clean 001G apply + second replay over verified 001D-001F runtime baseline"
echo "NOTE: this does not certify repository clean-from-zero migration because historical 001D-001F migration files are not present in this repository."
