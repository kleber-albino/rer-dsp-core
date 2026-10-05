#!/usr/bin/env bash
# Testes do select-runtime-config.sh (CFG-02, CFG-03, CFG-07, CFG-08, CFG-09).
set -euo pipefail

CORE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_ROOT="$(cd "$CORE_ROOT/../dsp-backend" && pwd)"
SCRIPT="$BACKEND_ROOT/config/docker/select-runtime-config.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_eq() {
  local label="$1"
  local expected="$2"
  local file="$3"
  if [ ! -f "$file" ]; then
    echo "FAIL: $label — missing $file"
    FAIL=$((FAIL + 1))
    return
  fi
  assert_eq "$label" "$expected" "$(cat "$file")"
}

assert_exit() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — exit $actual (expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# CFG-03: arquivo ativo é copiado (não o example)
mkdir -p "$TMP/src1"
printf 'ACTIVE\n' >"$TMP/src1/mapLayersConfig.json"
printf 'EXAMPLE\n' >"$TMP/src1/mapLayersConfig.json.example"
"$SCRIPT" pick "$TMP/src1" mapLayersConfig.json "$TMP/out1/mapLayersConfig.json"
assert_file_eq "pick prefers active file" "ACTIVE" "$TMP/out1/mapLayersConfig.json"

# CFG-02: só example → destino com nome ativo e conteúdo do example
mkdir -p "$TMP/src2"
printf 'EXAMPLE_ONLY\n' >"$TMP/src2/installation-config.json.example"
"$SCRIPT" pick "$TMP/src2" installation-config.json "$TMP/out2/installation-config.json"
assert_file_eq "pick falls back to .example" "EXAMPLE_ONLY" "$TMP/out2/installation-config.json"

# CFG-09: ativo e example ausentes → exit != 0
set +e
"$SCRIPT" pick "$TMP/src2" missing.yaml "$TMP/out-missing.yaml"
status=$?
set -e
assert_exit "pick fails when both files missing" 1 "$status"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for about tests (CFG-07, CFG-08)"
  exit 1
fi

# CFG-07: about gera .md a partir de .md.example; ignora quickstart; só tabs do JSON
mkdir -p "$TMP/about-src"
cat >"$TMP/about-src/about-config.json.example" <<'JSON'
{"enabled":true,"tabs":[{"id":"tab-1","label":"Overview","file":"overview.md"}]}
JSON
printf 'OVERVIEW_EXAMPLE\n' >"$TMP/about-src/overview.md.example"
printf 'QUICKSTART\n' >"$TMP/about-src/overview.quickstart.md.example"
printf 'ORPHAN\n' >"$TMP/about-src/extra.md"
"$SCRIPT" about "$TMP/about-src" "$TMP/about-dst"
assert_file_eq "about uses about-config.json.example" '{"enabled":true,"tabs":[{"id":"tab-1","label":"Overview","file":"overview.md"}]}' "$TMP/about-dst/about-config.json"
assert_file_eq "about generates overview.md from .md.example" "OVERVIEW_EXAMPLE" "$TMP/about-dst/overview.md"
if [ -f "$TMP/about-dst/extra.md" ]; then
  echo "FAIL: about copied orphan markdown not listed in about-config.json"
  FAIL=$((FAIL + 1))
else
  echo "PASS: about skips orphan markdown files"
  PASS=$((PASS + 1))
fi
if [ -f "$TMP/about-dst/overview.quickstart.md" ] || [ -f "$TMP/about-dst/overview.quickstart.md.example" ]; then
  echo "FAIL: about copied quickstart artifact into dest"
  FAIL=$((FAIL + 1))
else
  echo "PASS: about ignores *.quickstart.md.example"
  PASS=$((PASS + 1))
fi

# CFG-08: .md ativo é preservado
mkdir -p "$TMP/about-src2"
cat >"$TMP/about-src2/about-config.json" <<'JSON'
{"enabled":false,"tabs":[{"id":"tab-1","label":"Overview","file":"overview.md"}]}
JSON
cat >"$TMP/about-src2/about-config.json.example" <<'JSON'
{"enabled":true,"tabs":[{"id":"tab-1","label":"Overview","file":"overview.md"}]}
JSON
printf 'ACTIVE_MD\n' >"$TMP/about-src2/overview.md"
printf 'EXAMPLE_MD\n' >"$TMP/about-src2/overview.md.example"
"$SCRIPT" about "$TMP/about-src2" "$TMP/about-dst2"
assert_file_eq "about prefers active about-config.json" '{"enabled":false,"tabs":[{"id":"tab-1","label":"Overview","file":"overview.md"}]}' "$TMP/about-dst2/about-config.json"
assert_file_eq "about prefers active overview.md" "ACTIVE_MD" "$TMP/about-dst2/overview.md"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
