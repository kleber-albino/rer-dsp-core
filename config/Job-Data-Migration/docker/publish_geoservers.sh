#!/bin/sh
# After the first successful scheduled migration: publish layers on both GeoServers.
# No-op when DSP_MIGRATION_SCHEDULED_AT is empty (Run now already populated GeoServer during setup).
set -e

MARKER="${DSP_GEOSERVER_POPULATE_MARKER:-/tmp/dsp-geoserver-populated.done}"
POPULATE_SCRIPT="${DSP_GEOSERVER_POPULATE_SCRIPT:-/opt/populate_geoserver.sh}"

if [ -z "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
  exit 0
fi

if [ -f "$MARKER" ]; then
  echo "[publish-geoservers] layers already published — skipping"
  exit 0
fi

if [ ! -f "$POPULATE_SCRIPT" ]; then
  echo "[publish-geoservers] populate script not found: ${POPULATE_SCRIPT}" >&2
  exit 1
fi

GS_USER="${DSP_GEOSERVER_ADMIN_USER:-admin}"
GS_PASSWORD="${DSP_GEOSERVER_ADMIN_PASSWORD:-geoserver}"
EXHIBITION_URL="${DSP_GEOSERVER_EXHIBITION_INTERNAL_URL:-http://dsp-geoserver-exhibition:8080/geoserver}"
DOWNLOAD_URL="${DSP_GEOSERVER_DOWNLOAD_INTERNAL_URL:-http://dsp-geoserver-download:8080/geoserver}"

wait_for_geoserver_rest() {
  name="$1"
  url="$2"
  i=0
  echo "[publish-geoservers] waiting for ${name} REST at ${url} ..."
  while [ "$i" -lt 90 ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "${GS_USER}:${GS_PASSWORD}" \
      "${url}/rest/about/version.json" || true)
    if [ "$code" = "200" ]; then
      echo "[publish-geoservers] ${name} is ready"
      return 0
    fi
    i=$((i + 1))
    sleep 5
  done
  echo "[publish-geoservers] ${name} REST did not become ready" >&2
  return 1
}

run_populate() {
  name="$1"
  url="$2"
  datastore="$3"
  echo "[publish-geoservers] publishing layers on ${name} (${url})"
  GEOSERVER_URL="$url" \
    GEOSERVER_ADMIN_USER="$GS_USER" \
    GEOSERVER_ADMIN_PASSWORD="$GS_PASSWORD" \
    DATASTORE_NAME="$datastore" \
    WORKSPACE_NAME="${WORKSPACE_NAME:-dsp}" \
    DB_HOST="${DSP_GEOSERVER_DB_HOST:-dsp-geoserver-db}" \
    DB_PORT="${DSP_GEOSERVER_DB_PORT:-5432}" \
    DB_NAME="${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}" \
    DB_SCHEMA="${DSP_GEOSERVER_DB_SCHEMA:-dsp}" \
    DB_USER="${DSP_GEOSERVER_DB_USER:-dsp_geo}" \
    DB_PASSWORD="${DSP_GEOSERVER_DB_PASSWORD:-dsp_geo}" \
    MAP_LAYERS_CONFIG="${MAP_LAYERS_CONFIG:-/config/mapLayersConfig.json}" \
    LAYER_SRS_TERRITORY_LEVEL_1="${LAYER_SRS_TERRITORY_LEVEL_1:-4326}" \
    LAYER_SRS_TERRITORY_LEVEL_2="${LAYER_SRS_TERRITORY_LEVEL_2:-4326}" \
    LAYER_SRS_TERRITORY_LEVEL_3="${LAYER_SRS_TERRITORY_LEVEL_3:-4326}" \
    LAYER_SRS_AREA_OF_INTEREST="${LAYER_SRS_AREA_OF_INTEREST:-4326}" \
    bash "$POPULATE_SCRIPT"
}

wait_for_geoserver_rest "GeoServer Exhibition" "$EXHIBITION_URL"
wait_for_geoserver_rest "GeoServer Download" "$DOWNLOAD_URL"

run_populate "GeoServer Exhibition" "$EXHIBITION_URL" \
  "${DSP_GEOSERVER_EXHIBITION_DATASTORE:-dsp-geoserver-db}"
run_populate "GeoServer Download" "$DOWNLOAD_URL" \
  "${DSP_GEOSERVER_DOWNLOAD_DATASTORE:-dsp-geoserver-download-db}"

touch "$MARKER"
echo "[publish-geoservers] Exhibition and Download layers published"

if [ -f /mark_first_data_load_ready.sh ]; then
  sh /mark_first_data_load_ready.sh
else
  first_marker="${DSP_FIRST_DATA_LOAD_MARKER:-/dsp-batch-markers/first_data_load.ready}"
  mkdir -p "$(dirname "$first_marker")"
  touch "$first_marker"
  echo "[mark-first-data-load] ready: ${first_marker}"
fi
