#!/usr/bin/env bash
# Usage: ./start.sh   (migrate data first with ./setup.sh)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

DSP_ORCHESTRATION_SCRIPT="start.sh"
TOTAL_STEPS=8

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

step_header 1 "Prerequisites (Docker)"
require_not_root
require_docker

step_header 2 "Environment (.env)"
ensure_dotenv
reject_legacy_migration_env

step_header 3 "Repository paths (backend / frontend)"

info "Resolving repository paths..."
ensure_dsp_repositories --backend --frontend

step_header 4 "Installation config (UI labels, screens, KPIs)"

INSTALLATION_CONFIG_EXAMPLE="$ROOT_DIR/config/installation/installation-config.json.example"
INSTALLATION_CONFIG="$ROOT_DIR/config/installation/installation-config.json"

ensure_adopter_json_config \
  "Installation config" \
  "$INSTALLATION_CONFIG_EXAMPLE" \
  "$INSTALLATION_CONFIG" \
  "hierarchy labels, screen titles, KPI cards, area unit, date formats"

print_installation_preview "$INSTALLATION_CONFIG"

step_header 5 "Map layers config (WMS / GeoServer)"

ensure_map_layers_config
ensure_download_themes_config

if is_quickstart_configured; then
  info "Quickstart configuration detected."
  use_quickstart_layer_srids
fi

step_header 6 "Summary"

if is_persistent_migration_mode; then
  info "Migration service will stay running (mode=$(get_migration_execution_mode))."
  if [ -n "${DSP_MIGRATION_CRON:-}" ]; then
    info "Cron: ${DSP_MIGRATION_CRON} (tz=${DSP_MIGRATION_TZ})"
  fi
  if [ -n "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
    info "First load at: ${DSP_MIGRATION_SCHEDULED_AT} (tz=${DSP_MIGRATION_TZ})"
    if is_geo_wait_for_first_load_mode && is_object_storage_stack_enabled; then
      info "Pre-generated download files will be built once after that migration job finishes."
    fi
  fi
else
  info "This script starts the application stack only (no data migration)."
  info "To migrate/populate data, run ./setup.sh first (uses Docker volumes)."
fi

step_header 7 "Databases"

start_databases_and_wait
ensure_migration_service_if_needed
ensure_geo_file_generation_service_if_needed
if is_persistent_migration_mode; then
  info "Migration service stack is active ($(get_migration_execution_mode))."
else
  info "Migration is not run by ./start.sh. Use ./setup.sh when you need to (re)migrate."
fi

step_header 8 "GeoServers + application containers + gateway"

MIGRATION_CONFIG="$ROOT_DIR/config/Job-Data-Migration/application/application.yaml"
start_geoserver_exhibition "up" "$MIGRATION_CONFIG"
start_geoserver_download "up"

info "Building and starting application containers..."
docker compose --env-file .env up -d --build dsp-backend dsp-frontend
ok "Backend and frontend are running"

start_gateway

print_stack_summary
print_stack_urls with-status
print_stack_usage_hints
print_geo_file_generation_hints
