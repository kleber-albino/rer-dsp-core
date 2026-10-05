#!/usr/bin/env bash
# CFG-01, CFG-04, CFG-05, CFG-06: Compose sem binds; job/SQL na imagem; aviso do config.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="$ROOT/docker-compose.yml"
CONFIG_SH="$ROOT/config.sh"
JOB_DOCKERFILE="$ROOT/../dsp-job-data-migration/Dockerfile"
PASS=0
FAIL=0

assert_absent() {
  local file="$1"
  local pattern="$2"
  local label="${3:-$pattern}"
  if grep -F "$pattern" "$file" >/dev/null; then
    echo "FAIL: $label still present in $file"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label absent"
    PASS=$((PASS + 1))
  fi
}

assert_present() {
  local file="$1"
  local pattern="$2"
  local label="${3:-$pattern}"
  if grep -F "$pattern" "$file" >/dev/null; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing $label in $file"
    FAIL=$((FAIL + 1))
  fi
}

# CFG-01
assert_absent "$COMPOSE" "./config/installation/installation-config.json"
assert_absent "$COMPOSE" "./config/map/mapLayersConfig.json"
assert_absent "$COMPOSE" "./config/downloads/downloadThemesConfig.json"
assert_absent "$COMPOSE" "./config/about:/config/about"
assert_absent "$COMPOSE" "./config/Job-Data-Migration/application/application.yaml"
assert_absent "$COMPOSE" "./config/Job-Data-Migration/docker/entrypoint.sh"
assert_absent "$COMPOSE" "./config/db/dsp-db:/docker-entrypoint-initdb.d"
assert_absent "$COMPOSE" "./config/db/dsp-geoserver-db:/docker-entrypoint-initdb.d"
assert_present "$COMPOSE" "backend_config:" "GeoServer/backend map context"
assert_present "$COMPOSE" "dsp_core_infra: ./config" "migration job infra context"
assert_absent "$COMPOSE" "dsp_config: ./config" "legacy dsp_config on app images"
assert_present "$COMPOSE" "dsp_db_data:/var/lib/postgresql/data"
assert_present "$COMPOSE" "context: ./config/ObjectStorage" "object storage build context"
assert_present "$COMPOSE" "dsp_object_storage_data:/data" "object storage data volume"
assert_present "$COMPOSE" "profiles:" "compose profiles block"
grep -F "object-storage" "$COMPOSE" >/dev/null && echo "PASS: object-storage compose profile" && PASS=$((PASS + 1)) || { echo "FAIL: missing object-storage profile in $COMPOSE"; FAIL=$((FAIL + 1)); }

if command -v docker >/dev/null 2>&1; then
  rendered="$(cd "$ROOT" && docker compose --profile migration --profile object-storage config 2>/dev/null || true)"
  if [ -n "$rendered" ]; then
    if printf '%s\n' "$rendered" | grep -F 'type: bind' >/dev/null; then
      echo "FAIL: rendered compose still has type: bind"
      FAIL=$((FAIL + 1))
    else
      echo "PASS: rendered compose has no type: bind"
      PASS=$((PASS + 1))
    fi
  fi
fi

# CFG-04
assert_present "$JOB_DOCKERFILE" "/config/application.yaml" "job copies application.yaml to /config"
assert_present "$JOB_DOCKERFILE" 'ENTRYPOINT ["/migration-entrypoint.sh"]' "job ENTRYPOINT is /migration-entrypoint.sh"

# CFG-05
for db in dsp-db dsp-geoserver-db; do
  df="$ROOT/config/db/$db/Dockerfile"
  assert_present "$df" "COPY *.sql /docker-entrypoint-initdb.d/" "$db COPY SQL to initdb.d"
  assert_present "$COMPOSE" "context: ./config/db/$db" "$db build context"
done

# CFG-06
assert_present "$CONFIG_SH" "Run ./setup.sh or ./start.sh so containers pick up this configuration." "config.sh rebuild hint"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
