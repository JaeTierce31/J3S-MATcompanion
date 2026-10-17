#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-db/migrations/recovered_archive}"
OUT="${2:-.recovered-migrations}"
mkdir -p "$OUT"

reconstruct() {
  local name="$1" expected="$2"
  local direct="$ROOT/$name.sql"
  local dir="$ROOT/$name"
  local out="$OUT/$name.sql"

  if [[ -f "$direct" ]]; then
    cp "$direct" "$out"
  elif [[ -d "$dir" ]]; then
    shopt -s nullglob
    local parts=("$dir"/*.b64part)
    shopt -u nullglob
    (( ${#parts[@]} > 0 )) || { echo "missing archive parts: $dir" >&2; exit 2; }
    printf '%s\n' "${parts[@]}" | sort -V | xargs cat | base64 --decode > "$out"
  else
    echo "missing recovered artifact: $direct or $dir" >&2
    exit 2
  fi

  local actual
  actual=$(sha256sum "$out" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "HASH MISMATCH $name expected=$expected actual=$actual" >&2
    rm -f "$out"
    exit 3
  fi
  echo "HASH PASS $name $actual"
}

reconstruct 001B_base e9b5704af817a7e2c7c6841010655c97e86bec27f3bc627a15e4648f786a8126
reconstruct 001C_runtime_hardening 69d6b76a9723052a0e5fcecc8ed305738a553ad2bcbd00123151cb22d9f3ae7c
reconstruct 001D_longitudinal_intelligence 2cdadabf81970ac534643f32ba1441821794b7a790150d3f2c84475c900791e2
reconstruct 001E_personal_intelligence fda38fd5dfd57bed4d9bd7a0066acc582c0d8ab5cb4714966c7a50ab3e13bca9
reconstruct 001F_delivery_read_model 5feeef146069191b989d8738f272f7abb69bbd096527e5bae32e6c3e539b2a04

echo "Recovered PSI-CIM 001B-001F migrations reconstructed with exact signed hashes."
