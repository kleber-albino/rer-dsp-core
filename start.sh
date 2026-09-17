#!/usr/bin/env bash
# Usage: ./setup.sh first, then ./start.sh (application: backend, frontend, gateway)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

DSP_ORCHESTRATION_SCRIPT="start.sh"
TOTAL_STEPS=6

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

step_header 4 "Runtime configuration files"

ensure_runtime_config_files_exist

step_header 5 "Infrastructure (must be running)"

require_setup_infra_ready

step_header 6 "Application containers + gateway"

MIGRATION_CONFIG="$ROOT_DIR/config/Job-Data-Migration/application/application.yaml"
start_geoserver_exhibition "up" "$MIGRATION_CONFIG"
start_geoserver_download "up"

info "Building and starting application containers..."
docker compose --env-file .env up -d --build --force-recreate dsp-backend dsp-frontend
ok "Backend and frontend are running"

start_gateway
start_application_stack

print_stack_summary
print_stack_urls with-status
print_stack_usage_hints
print_geo_file_generation_hints
