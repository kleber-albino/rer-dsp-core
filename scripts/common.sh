BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DSP_ORCHESTRATION_SCRIPT="${DSP_ORCHESTRATION_SCRIPT:-script}"
TOTAL_STEPS="${TOTAL_STEPS:-0}"

declare -gA STACK_SERVICE_STATUSES=()
STACK_REQUIRED_SERVICES=(
  dsp-db
  dsp-geoserver-db
  dsp-geoserver-exhibition
  dsp-geoserver-download
  dsp-backend
  dsp-frontend
  dsp-gateway
)

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=migration_schedule.sh
source "$_COMMON_DIR/migration_schedule.sh"

# Base pública da stack (gateway). DSP_PUBLIC_BASE_URL tem precedência; sem ela,
# monta a URL a partir do host e da porta do gateway, omitindo a porta 80.
dsp_public_base_url() {
  if [ -n "${DSP_PUBLIC_BASE_URL:-}" ]; then
    echo "${DSP_PUBLIC_BASE_URL%/}"
    return
  fi

  local host="${DSP_HTTP_HOST:-localhost}"
  local port="${DSP_GATEWAY_HOST_PORT:-8026}"

  if [ "$port" = "80" ]; then
    echo "http://${host}"
  else
    echo "http://${host}:${port}"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local answer=""

  while true; do
    read -r -p "${prompt} [y/n] " answer || return 1
    case "$answer" in
      y|Y)
        return 0
        ;;
      n|N)
        return 1
        ;;
      *)
        warn "Invalid response. Please enter y or n."
        ;;
    esac
  done
}

step_header() {
  local step="$1"
  local title="$2"
  echo ""
  echo "============================================================================="
  echo "Step ${step}/${TOTAL_STEPS} — ${title}"
  echo "============================================================================="
}

resolve_path() {
  local path="$1"
  local resolved
  if [[ "$path" = /* ]]; then
    resolved="$path"
  else
    resolved="$ROOT_DIR/$path"
  fi
  realpath -m "$resolved"
}

validate_json_file() {
  local file="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$file" >/dev/null
    return $?
  fi
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null
    return $?
  fi
  warn "Neither python3 nor jq found — skipping JSON syntax validation for: $file"
  return 0
}

ensure_adopter_json_config() {
  local label="$1"
  local example="$2"
  local active="$3"
  local edit_hint="$4"

  if [ ! -f "$example" ]; then
    error "${label} template not found at: $example"
    exit 1
  fi

  if [ ! -f "$active" ]; then
    error "${label} file not found:"
    echo "        $active"
    error "Run ./config.sh to generate the active file (${edit_hint}) and try './${DSP_ORCHESTRATION_SCRIPT}' again."
    exit 1
  fi

  if ! validate_json_file "$active"; then
    error "${label} file contains invalid JSON:"
    echo "        $active"
    exit 1
  fi

  if cmp -s "$active" "$example"; then
    error "${label} file is still identical to the template."
    echo "        $active"
    error "Edit the file (${edit_hint}) before continuing."
    exit 1
  fi

  ok "${label} configured: $active"
}

print_installation_preview() {
  local cfg="$1"
  info "Installation configuration preview:"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  File: $cfg"
    return
  fi
  python3 - "$cfg" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

print("  Hierarchy:")
for level in data.get("hierarchy", []):
    print(f"    {level.get('key', '?')}: {level.get('label', '?')}")

screens = data.get("screens", {})
home = screens.get("home", {})
downloads = screens.get("downloads", {})
print(f"  Home screen: {home.get('title', '<missing>')}")
identifier = home.get("identifier") or {}
print(f"  Home identifier: {identifier.get('label', '<missing>')}")
print(f"  Downloads screen: {downloads.get('title', '<missing>')}")
theme = downloads.get("theme") or {}
print(f"  Downloads theme: {theme.get('label', '<missing>')}")

kpis = data.get("kpis", {})
cards = kpis.get("cards", [])
print(f"  KPI cards: {len(cards)} (primary: {kpis.get('primaryCode', '<missing>')})")

aoi = data.get("areaOfInterest", {})
print(f"  Area unit: {aoi.get('areaUnitLabel', '<missing>')}")
PY
}

print_map_layers_preview() {
  local cfg="$1"
  info "Map layers configuration preview:"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  File: $cfg"
    return
  fi
  python3 - "$cfg" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

for group in data.get("groups", []):
    print(f"  Group: {group.get('name', '?')} ({group.get('key', '?')})")
    for layer in group.get("layers", []):
        style = layer.get("style") or {}
        color = style.get("color", "<missing>")
        fill = style.get("fillColor", "<missing>")
        print(f"    - {layer.get('name', '?')} [{layer.get('layers', '<missing>')}]")
        print(f"      baseUrl: {layer.get('baseUrl', '<missing>')}")
        print(f"      color: {color} | fillColor: {fill}")
PY
}

print_download_themes_preview() {
  local cfg="$1"
  info "Download themes configuration preview:"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  File: $cfg"
    return
  fi
  python3 - "$cfg" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

print(f"  WFS base URL: {data.get('wfsBaseUrl', '<missing>')}")
for theme in data.get("themes", []):
    status = "enabled" if theme.get("enabled", True) else "disabled"
    print(f"    - {theme.get('name', '?')} [{theme.get('typeName', '<missing>')}] ({status})")
PY
}

validate_download_themes_config() {
  local cfg="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    error "python3 is required to validate downloadThemesConfig.json."
    exit 1
  fi
  if ! python3 - "$cfg" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data.get("wfsBaseUrl"), str) or not data["wfsBaseUrl"].strip():
    raise SystemExit("wfsBaseUrl is required")

themes = data.get("themes")
if not isinstance(themes, list) or not themes:
    raise SystemExit("themes must be a non-empty list")

for index, theme in enumerate(themes):
    prefix = f"themes[{index}]"
    for key in ("code", "name", "typeName"):
        value = theme.get(key)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"{prefix}.{key} is required")
    formats = theme.get("formats")
    if not isinstance(formats, list) or not formats:
        raise SystemExit(f"{prefix}.formats must be a non-empty list")
    territory_filter = theme.get("territoryFilter")
    if not isinstance(territory_filter, dict):
        raise SystemExit(f"{prefix}.territoryFilter is required")
    strategy = territory_filter.get("strategy")
    if strategy not in {"direct", "aoi_linked"}:
        raise SystemExit(f"{prefix}.territoryFilter.strategy must be direct or aoi_linked")
PY
  then
    error "downloadThemesConfig.json is invalid."
    exit 1
  fi
  ok "Download themes config is valid"
}

ensure_download_themes_config() {
  local example="$ROOT_DIR/config/downloads/downloadThemesConfig.json.example"
  local active="$ROOT_DIR/config/downloads/downloadThemesConfig.json"

  ensure_adopter_json_config \
    "Download themes config" \
    "$example" \
    "$active" \
    "download themes catalog for /downloads endpoints"

  print_download_themes_preview "$active"
  validate_download_themes_config "$active"
  warn_urls_outside_gateway "$active" "Download themes config"
}

# As URLs de WMS/WFS são consumidas pelo browser e precisam apontar para o gateway.
# Configs gerados antes do gateway ainda trazem as portas antigas e quebram o mapa em silêncio.
warn_urls_outside_gateway() {
  local cfg="$1"
  local label="$2"
  local base_url
  base_url="$(dsp_public_base_url)"

  [ -f "$cfg" ] || return 0

  if grep -oE 'https?://[^"]+/geoserver[^"]*' "$cfg" \
      | grep -qv "^${base_url}/geoserver"; then
    warn "${label}: there are GeoServer URLs outside the gateway (${base_url})."
    warn "Run ./config.sh to regenerate them, or fix baseUrl/wfsBaseUrl by hand."
  fi
}

validate_map_layers_wms_ids() {
  local cfg="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    error "python3 is required to validate mapLayersConfig WMS layer ids and colors."
    exit 1
  fi
  if ! python3 - "$cfg" <<'PY'
import json
import re
import sys

REQUIRED = {
    "dsp:territory-level-1",
    "dsp:territory-level-2",
    "dsp:territory-level-3",
    "dsp:area-of-interest",
}
HEX = re.compile(r"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")
EPSG = re.compile(r"^(EPSG:)?[0-9]+$", re.IGNORECASE)

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

by_id = {}
for group in data.get("groups", []):
    for layer in group.get("layers", []):
        lid = layer.get("layers")
        if isinstance(lid, str) and lid:
            by_id[lid] = layer

missing = sorted(REQUIRED - set(by_id))
errors = []
if missing:
    print("EXPECTED (required WMS layer ids):")
    for item in sorted(REQUIRED):
        print(f"  - {item}")
    print("FOUND in mapLayersConfig.json:")
    for item in sorted(by_id) or ["(none)"]:
        print(f"  - {item}")
    print("MISSING:")
    for item in missing:
        print(f"  - {item}")
    sys.exit(1)

def validate_style(lid, layer):
    style = (layer.get("style") or {})
    color = style.get("color")
    fill = style.get("fillColor")
    if not isinstance(color, str) or not color.strip():
        errors.append(f"{lid}: style.color is missing")
    elif not HEX.match(color):
        errors.append(f"{lid}: style.color must be #RGB or #RRGGBB (got {color!r})")
    if not isinstance(fill, str) or not fill.strip():
        errors.append(f"{lid}: style.fillColor is missing")
    elif fill != "transparent" and not HEX.match(fill):
        errors.append(
            f"{lid}: style.fillColor must be 'transparent' or #RGB/#RRGGBB (got {fill!r})"
        )

for lid in sorted(REQUIRED):
    validate_style(lid, by_id[lid])

for lid, layer in sorted(by_id.items()):
    if lid in REQUIRED:
        continue
    validate_style(lid, layer)
    native = layer.get("nativeName")
    if not isinstance(native, str) or not native.strip():
        errors.append(f"{lid}: nativeName is required for extra layers")
    srs = layer.get("srs")
    if not isinstance(srs, str) or not srs.strip() or not EPSG.match(srs.strip()):
        errors.append(
            f"{lid}: srs is required for extra layers (integer or EPSG:n, got {srs!r})"
        )

if errors:
    print("INVALID layer configuration:")
    for item in errors:
        print(f"  - {item}")
    sys.exit(1)
sys.exit(0)
PY
  then
    error "mapLayersConfig.json must keep the four WMS layer ids and valid style colors."
    error "Extra layers also need nativeName, srs, and valid style colors."
    error "Ids must match GeoServer Exhibition populate and job layer-name."
    error "style.color: #RGB or #RRGGBB; style.fillColor: transparent or #RGB/#RRGGBB."
    exit 1
  fi
  ok "WMS layer ids and style colors match Exhibition contract"
}

# Ensures mapLayersConfig.json is valid, differs from template, and has required WMS ids/colors. Used by setup.sh.
ensure_map_layers_config() {
  local example="$ROOT_DIR/config/map/mapLayersConfig.json.example"
  local active="$ROOT_DIR/config/map/mapLayersConfig.json"

  ensure_adopter_json_config \
    "Map layers config" \
    "$example" \
    "$active" \
    "baseUrl / display names / style colors (keep the four required WMS ids; extras need nativeName + srs)"

  print_map_layers_preview "$active"
  validate_map_layers_wms_ids "$active"
  warn_urls_outside_gateway "$active" "Map layers config"
}

# Checa a REST API por dentro do container: os GeoServers não publicam porta no host,
# o acesso externo passa pelo gateway (que sobe depois deles).
wait_for_geoserver() {
  local compose_service="${1:-dsp-geoserver-exhibition}"
  local user="$2"
  local password="$3"
  local i
  for i in $(seq 1 60); do
    if docker compose --env-file .env exec -T "$compose_service" \
        curl -sf -u "${user}:${password}" \
        "http://localhost:8080/geoserver/rest/about/version.json" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

yaml_scalar() {
  local file="$1"
  local section="$2"
  local key="$3"
  awk -v section="$section" -v key="$key" '
    function leading_spaces(s) {
      match(s, /^[ ]*/)
      return RLENGTH
    }
    BEGIN { in_section = 0; section_indent = -1 }
    {
      indent = leading_spaces($0)
      line = $0
      sub(/^[ ]+/, "", line)
    }
    line ~ ("^" section ":") {
      in_section = 1
      section_indent = indent
      next
    }
    in_section && line != "" && line !~ /^#/ && indent <= section_indent {
      in_section = 0
    }
    in_section && line ~ ("^" key ":") {
      sub(/^[^:]+:[ ]*/, "", line)
      gsub(/^["'\'']|["'\'']$/, "", line)
      print line
      exit
    }
  ' "$file"
}

yaml_source_table() {
  local file="$1"
  local section="$2"
  local line
  line="$(awk -v section="$section" '
    function leading_spaces(s) {
      match(s, /^[ ]*/)
      return RLENGTH
    }
    BEGIN { in_section = 0; section_indent = -1 }
    {
      indent = leading_spaces($0)
      line = $0
      sub(/^[ ]+/, "", line)
    }
    line ~ ("^" section ":") {
      in_section = 1
      section_indent = indent
      next
    }
    in_section && line != "" && line !~ /^#/ && indent <= section_indent {
      in_section = 0
    }
    in_section && line ~ /^source-table:/ {
      sub(/^[^:]+:[ ]*/, "", line)
      print line
      exit
    }
  ' "$file")"
  if [ -z "$line" ] || [[ "$line" == ">-" ]] || [[ "$line" == "|"* ]] || [[ "$line" == "("* ]]; then
    echo "SQL query defined in YAML"
  else
    echo "$line" | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
  fi
}

yaml_target_table() {
  yaml_scalar "$1" "$2" "target-table"
}

# Print ETL lines for batch.layers (generic layers → geo-target dsp.<layer_name>).
# Prints nothing when the list is empty or missing (caller shows "(none)").
yaml_generic_layers_etl_lines() {
  local file="$1"
  awk '
    function leading_spaces(s) {
      match(s, /^[ ]*/)
      return RLENGTH
    }
    function flush_item() {
      if (src == "") return
      n = split(src, parts, ".")
      tbl = parts[n]
      phys = lname
      gsub(/-/, "_", phys)
      if (phys == "") phys = tbl
      tgt = "dsp." phys
      status = ""
      if (enabled == "false") status = " (disabled)"
      if (lname != "") {
        print "      - " src " -> " tgt " [" lname "]" status
      } else {
        print "      - " src " -> " tgt status
      }
      src = ""; lname = ""; enabled = ""
    }
    BEGIN {
      in_root_batch = 0
      in_layers = 0
      root_batch_indent = -1
      layers_indent = -1
      src = ""; lname = ""; enabled = ""
    }
    {
      indent = leading_spaces($0)
      line = $0
      sub(/^[ ]+/, "", line)
    }
    !in_root_batch && indent == 0 && line ~ /^batch:/ {
      in_root_batch = 1
      root_batch_indent = indent
      next
    }
    in_root_batch && !in_layers && line != "" && line !~ /^#/ && indent <= root_batch_indent {
      in_root_batch = 0
    }
    in_root_batch && !in_layers && line ~ /^layers:/ {
      rest = line
      sub(/^layers:[ ]*/, "", rest)
      if (rest ~ /^\[\]/) {
        exit
      }
      in_layers = 1
      layers_indent = indent
      next
    }
    in_layers && line != "" && line !~ /^#/ {
      # List items share the same indent as "layers:" (YAML: "layers:" then "- ...").
      leave = 0
      if (indent < layers_indent) leave = 1
      if (indent == layers_indent && line !~ /^- /) leave = 1
      if (leave) {
        flush_item()
        exit
      }
    }
    in_layers && line ~ /^- / {
      flush_item()
      item = line
      sub(/^- /, "", item)
      if (item ~ /^source-table:/) {
        sub(/^source-table:[ ]*/, "", item)
        gsub(/^["'\'']|["'\'']$/, "", item)
        src = item
      }
      next
    }
    in_layers && line ~ /^source-table:/ {
      sub(/^source-table:[ ]*/, "", line)
      gsub(/^["'\'']|["'\'']$/, "", line)
      src = line
      next
    }
    in_layers && line ~ /^layer-name:/ {
      sub(/^layer-name:[ ]*/, "", line)
      gsub(/^["'\'']|["'\'']$/, "", line)
      lname = line
      next
    }
    in_layers && line ~ /^enabled:/ {
      sub(/^enabled:[ ]*/, "", line)
      enabled = line
      next
    }
    END { flush_item() }
  ' "$file"
}

# Resolve ${VAR_NAME} using a variable already exported in the shell (.env).
resolve_env_placeholder() {
  local raw="$1"
  if [[ "$raw" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
    local var_name="${BASH_REMATCH[1]}"
    if [ -n "${!var_name:-}" ]; then
      printf '%s' "${!var_name}"
      return
    fi
    printf '%s (unset)' "$raw"
    return
  fi
  printf '%s' "$raw"
}

print_migration_preview() {
  local cfg="$1"
  local will_run="${2:-false}"
  local first_run_label=""
  local recurrence_label=""
  if [ "$will_run" = "true" ]; then
    first_run_label="during this setup"
  elif [ -n "${MIGRATION_SCHEDULED_AT:-}" ]; then
    first_run_label="scheduled at ${MIGRATION_SCHEDULED_AT} (${DSP_MIGRATION_TZ})"
  else
    first_run_label="not configured"
  fi
  case "${MIGRATION_EXECUTION_MODE:-once}" in
    once)
      recurrence_label="one-time"
      ;;
    scheduled-once)
      recurrence_label="one-time (scheduled)"
      ;;
    continuous)
      recurrence_label="continuous"
      ;;
    *)
      recurrence_label="${MIGRATION_EXECUTION_MODE:-unknown}"
      ;;
  esac

  local batch_url source_url target_url
  local batch_user source_user target_user
  batch_url="$(yaml_scalar "$cfg" "batch" "url")"
  batch_user="$(yaml_scalar "$cfg" "batch" "username")"
  source_url="$(yaml_scalar "$cfg" "source" "url")"
  source_user="$(yaml_scalar "$cfg" "source" "username")"
  source_url="$(resolve_env_placeholder "$source_url")"
  source_user="$(resolve_env_placeholder "$source_user")"
  target_url="$(yaml_scalar "$cfg" "target" "url")"
  target_user="$(yaml_scalar "$cfg" "target" "username")"

  local l1_src l1_tgt l2_src l2_tgt l3_src l3_tgt aoi_src aoi_tgt
  l1_src="$(yaml_source_table "$cfg" "level-1")"
  l1_tgt="$(yaml_target_table "$cfg" "level-1")"
  l2_src="$(yaml_source_table "$cfg" "level-2")"
  l2_tgt="$(yaml_target_table "$cfg" "level-2")"
  l3_src="$(yaml_source_table "$cfg" "level-3")"
  l3_tgt="$(yaml_target_table "$cfg" "level-3")"
  aoi_src="$(yaml_source_table "$cfg" "area-of-interest")"
  aoi_tgt="$(yaml_target_table "$cfg" "area-of-interest")"

  local generic_layers_lines
  generic_layers_lines="$(yaml_generic_layers_etl_lines "$cfg")"

  info "Migration configuration preview:"
  echo "  First run: ${first_run_label}"
  echo "  Recurrence: ${recurrence_label}"
  if [ -n "${MIGRATION_CRON:-}" ]; then
    echo "  Cron: ${MIGRATION_CRON} (tz=${DSP_MIGRATION_TZ})"
  fi
  if [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; then
    echo "  Pre-generated downloads: once, automatically after the migration job completes"
  elif [ "${GEO_FILE_GENERATION_RECURRING:-true}" = "true" ] && [ -n "${GEO_FILE_GENERATION_CRON:-}" ]; then
    echo "  Pre-generated downloads: recurring (cron=${GEO_FILE_GENERATION_CRON})"
  fi
  echo "  Datasources:"
  echo "    batch:  ${batch_url:-<missing>} (user: ${batch_user:-<missing>})"
  echo "    source: ${source_url:-<missing>} (user: ${source_user:-<missing>})"
  echo "    target: ${target_url:-<missing>} (user: ${target_user:-<missing>})"
  echo "  ETL mappings:"
  echo "    level 1:          ${l1_src:-<missing>} -> ${l1_tgt:-<missing>}"
  echo "    level 2:          ${l2_src:-<missing>} -> ${l2_tgt:-<missing>}"
  echo "    level 3:          ${l3_src:-<missing>} -> ${l3_tgt:-<missing>}"
  echo "    area of interest: ${aoi_src:-<missing>} -> ${aoi_tgt:-<missing>}"
  echo "    generic layers:"
  if [ -n "$generic_layers_lines" ]; then
    printf '%s\n' "$generic_layers_lines"
  else
    echo "      (none)"
  fi
}

wait_for_db() {
  local service="$1"
  local user="$2"
  local db="$3"
  local i
  for i in $(seq 1 60); do
    if docker compose --env-file .env exec -T "$service" \
        pg_isready -U "$user" -d "$db" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# pg_isready alone is not enough on a fresh volume: the entrypoint may still be PID 1
# while a temporary PostgreSQL serves /docker-entrypoint-initdb.d scripts.
_postgres_definitive_and_ready() {
  local service="$1"
  local user="$2"
  local db="$3"
  local comm=""

  comm="$(docker compose --env-file .env exec -T "$service" \
    sh -c 'tr -d "\0" < /proc/1/comm 2>/dev/null' 2>/dev/null | tr -d '[:space:]')"
  if [ "$comm" != "postgres" ]; then
    return 1
  fi

  docker compose --env-file .env exec -T "$service" \
    pg_isready -U "$user" -d "$db" >/dev/null 2>&1
}

wait_for_postgres_initialization() {
  local service="$1"
  local user="$2"
  local db="$3"
  local i

  for i in $(seq 1 90); do
    if _postgres_definitive_and_ready "$service" "$user" "$db"; then
      return 0
    fi
    sleep 1
  done

  error "${service} did not finish PostgreSQL initialization in time (PID 1 is not postgres or pg_isready failed)."
  docker compose --env-file .env logs --tail 40 "$service" || true
  return 1
}

# Confirms init SQL created the expected schema (call after wait_for_postgres_initialization).
wait_for_db_schema() {
  local service="$1"
  local user="$2"
  local db="$3"
  local schema="$4"
  local i
  for i in $(seq 1 90); do
    if docker compose --env-file .env exec -T "$service" \
        psql -U "$user" -d "$db" -tAc \
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}'" \
        2>/dev/null | grep -q '^1$'; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_data_migration_schema() {
  if ! wait_for_db_schema dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}" data_migration; then
    error "dsp-db init SQL did not create schema 'data_migration' in time."
    docker compose --env-file .env logs --tail 40 dsp-db || true
    return 1
  fi
  return 0
}

dsp_db_schema_exists() {
  local schema="$1"
  docker compose --env-file .env exec -T dsp-db \
      psql -U "${DSP_DB_USER:-dsp}" -d "${DSP_DB_NAME:-dsp-db}" -tAc \
      "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}'" \
      2>/dev/null | grep -q '^1$'
}

# Init SQL in the dsp-db image only runs on an empty volume. Existing installs
# get the geo-file Batch schema by applying the same file once (CREATE IF NOT EXISTS).
apply_geo_file_generation_schema_if_missing() {
  local sql="$ROOT_DIR/config/db/dsp-db/03_geo_file_generation_batch.sql"
  if dsp_db_schema_exists geo_file_generation; then
    return 0
  fi
  info "Applying geo_file_generation Spring Batch schema on dsp-db..."
  if [ ! -f "$sql" ]; then
    error "Missing ${sql}"
    exit 1
  fi
  if ! docker compose --env-file .env exec -T dsp-db \
      psql -U "${DSP_DB_USER:-dsp}" -d "${DSP_DB_NAME:-dsp-db}" -v ON_ERROR_STOP=1 \
      < "$sql"; then
    error "Failed to apply schema geo_file_generation on dsp-db."
    docker compose --env-file .env logs --tail 40 dsp-db || true
    exit 1
  fi
}

wait_for_geo_file_generation_schema() {
  apply_geo_file_generation_schema_if_missing
  info "Waiting for dsp-db schema geo_file_generation..."
  if ! wait_for_db_schema dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}" geo_file_generation; then
    error "dsp-db did not create schema 'geo_file_generation' in time."
    docker compose --env-file .env logs --tail 40 dsp-db || true
    exit 1
  fi
  ok "dsp-db schema geo_file_generation ready"
}

validate_positive_integer() {
  local label="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    error "${label}: srid must be a positive integer (got '${value:-<missing>}')"
    exit 1
  fi
}

export_layer_srids_from_migration_config() {
  local srid_l1 srid_l2 srid_l3 srid_aoi

  srid_l1="${LAYER_SRS_TERRITORY_LEVEL_1:-4326}"
  srid_l2="${LAYER_SRS_TERRITORY_LEVEL_2:-4326}"
  srid_l3="${LAYER_SRS_TERRITORY_LEVEL_3:-4326}"
  srid_aoi="${LAYER_SRS_AREA_OF_INTEREST:-4326}"

  srid_l1="${srid_l1#EPSG:}"
  srid_l2="${srid_l2#EPSG:}"
  srid_l3="${srid_l3#EPSG:}"
  srid_aoi="${srid_aoi#EPSG:}"

  validate_positive_integer "LAYER_SRS_TERRITORY_LEVEL_1" "$srid_l1"
  validate_positive_integer "LAYER_SRS_TERRITORY_LEVEL_2" "$srid_l2"
  validate_positive_integer "LAYER_SRS_TERRITORY_LEVEL_3" "$srid_l3"
  validate_positive_integer "LAYER_SRS_AREA_OF_INTEREST" "$srid_aoi"

  export LAYER_SRS_TERRITORY_LEVEL_1="EPSG:${srid_l1}"
  export LAYER_SRS_TERRITORY_LEVEL_2="EPSG:${srid_l2}"
  export LAYER_SRS_TERRITORY_LEVEL_3="EPSG:${srid_l3}"
  export LAYER_SRS_AREA_OF_INTEREST="EPSG:${srid_aoi}"

  ok "Layer SRS from .env: L1=${LAYER_SRS_TERRITORY_LEVEL_1} L2=${LAYER_SRS_TERRITORY_LEVEL_2} L3=${LAYER_SRS_TERRITORY_LEVEL_3} AOI=${LAYER_SRS_AREA_OF_INTEREST}"
}

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    error "Do not run as root/sudo. Use: ./${DSP_ORCHESTRATION_SCRIPT}"
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker is required."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose v2 is required (docker compose)."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running. Start Docker and run './${DSP_ORCHESTRATION_SCRIPT}' again."
    exit 1
  fi

  ok "Docker and Docker Compose OK"
}

DSP_REPO_BACKEND_URL="https://github.com/Rural-Environmental-Registry/rer-dsp-backend.git"
DSP_REPO_FRONTEND_URL="https://github.com/Rural-Environmental-Registry/rer-dsp-frontend.git"
DSP_REPO_JOB_URL="https://github.com/Rural-Environmental-Registry/rer-dsp-job-data-migration.git"
DSP_REPO_GEO_FILE_JOB_URL="https://github.com/Rural-Environmental-Registry/rer-dsp-job-geo-file-generation.git"

require_git() {
  if ! command -v git >/dev/null 2>&1; then
    error "Git is required to clone missing repositories."
    error "Install Git or clone the repositories manually."
    exit 1
  fi
}

classify_dsp_repository_path() {
  local abs="$1"

  if [ -f "$abs/Dockerfile" ]; then
    echo "ok"
  elif [ -e "$abs" ]; then
    echo "invalid"
  else
    echo "missing"
  fi
}

print_dsp_repository_preview() {
  local core_abs="$1"
  shift
  local -a preview_lines=()
  local line=""

  while [ "$#" -gt 0 ]; do
    preview_lines+=("$1")
    shift
  done

  echo ""
  info "Missing repositories detected."
  echo ""
  echo "Folder structure after clone:"
  echo ""

  local common_parent=""
  local uses_sibling_layout=true
  local core_parent
  core_parent="$(dirname "$core_abs")"

  for line in "${preview_lines[@]}"; do
    IFS='|' read -r _label abs _url status <<<"$line"
    if [ "$(dirname "$abs")" != "$core_parent" ]; then
      uses_sibling_layout=false
      break
    fi
  done

  if [ "$uses_sibling_layout" = true ]; then
    common_parent="$core_parent"
    echo "  ${common_parent}/"
    echo "  ├── rer-dsp-core/              (already exists — you are here)"

    for line in "${preview_lines[@]}"; do
      IFS='|' read -r label abs _url status <<<"$line"
      local folder
      folder="$(basename "$abs")"
      case "$status" in
        ok)
          echo "  ├── ${folder}/              (already exists)"
          ;;
        missing)
          echo "  ├── ${folder}/           <- will be cloned"
          ;;
      esac
    done
  else
    echo "  ${core_abs}/              (already exists — you are here)"
    for line in "${preview_lines[@]}"; do
      IFS='|' read -r label abs _url status <<<"$line"
      case "$status" in
        ok)
          echo "  ${abs}/              (already exists)"
          ;;
        missing)
          echo "  ${abs}/           <- will be cloned"
          ;;
      esac
    done
  fi

  echo ""
  echo "Details:"
  for line in "${preview_lines[@]}"; do
    IFS='|' read -r label abs url status <<<"$line"
    echo "  ${label}"
    echo "    destination: ${abs}"
    if [ "$status" = "missing" ]; then
      echo "    source:      ${url}"
    fi
  done
  echo ""
}

ensure_dsp_repositories() {
  local want_backend=false
  local want_frontend=false
  local want_job=false
  local want_geo_file_job=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --backend)
        want_backend=true
        ;;
      --frontend)
        want_frontend=true
        ;;
      --job)
        want_job=true
        ;;
      --geo-file-job)
        want_geo_file_job=true
        ;;
      *)
        error "Unknown ensure_dsp_repositories option: $1"
        exit 1
        ;;
    esac
    shift
  done

  if [ "$want_backend" = false ] && [ "$want_frontend" = false ] && [ "$want_job" = false ] \
    && [ "$want_geo_file_job" = false ]; then
    error "ensure_dsp_repositories: pass at least one of --backend, --frontend, --job, --geo-file-job"
    exit 1
  fi

  local core_abs
  core_abs="$(resolve_path ".")"
  local -a preview_lines=()
  local -a missing_labels=()
  local -a missing_abs=()
  local -a missing_urls=()

  _ensure_dsp_repo_check() {
    local label="$1"
    local path="$2"
    local url="$3"
    local found_label="$4"
    local abs
    local status

    abs="$(resolve_path "$path")"
    status="$(classify_dsp_repository_path "$abs")"

    case "$status" in
      ok)
        ok "${found_label} found: ${abs}"
        preview_lines+=("${label}|${abs}|${url}|ok")
        ;;
      invalid)
        error "${found_label} directory exists but Dockerfile is missing: ${abs}"
        error "Fix the path in .env or use a valid clone of ${label}."
        exit 1
        ;;
      missing)
        preview_lines+=("${label}|${abs}|${url}|missing")
        missing_labels+=("$label")
        missing_abs+=("$abs")
        missing_urls+=("$url")
        ;;
    esac
  }

  if [ "$want_backend" = true ]; then
    _ensure_dsp_repo_check \
      "rer-dsp-backend" \
      "${DSP_BACKEND_PATH:-../rer-dsp-backend}" \
      "$DSP_REPO_BACKEND_URL" \
      "Backend"
  fi

  if [ "$want_frontend" = true ]; then
    _ensure_dsp_repo_check \
      "rer-dsp-frontend" \
      "${DSP_FRONTEND_PATH:-../rer-dsp-frontend}" \
      "$DSP_REPO_FRONTEND_URL" \
      "Frontend"
  fi

  if [ "$want_job" = true ]; then
    _ensure_dsp_repo_check \
      "rer-dsp-job-data-migration" \
      "${DSP_JOB_MIGRATION_PATH:-../rer-dsp-job-data-migration}" \
      "$DSP_REPO_JOB_URL" \
      "Migration job"
  fi

  if [ "$want_geo_file_job" = true ]; then
    _ensure_dsp_repo_check \
      "rer-dsp-job-geo-file-generation" \
      "${DSP_JOB_GEO_FILE_GENERATION_PATH:-../rer-dsp-job-geo-file-generation}" \
      "$DSP_REPO_GEO_FILE_JOB_URL" \
      "Geo file generation job"
  fi

  if [ "${#missing_labels[@]}" -eq 0 ]; then
    return 0
  fi

  print_dsp_repository_preview "$core_abs" "${preview_lines[@]}"

  if ! prompt_yes_no "Proceed with clone?"; then
    error "Missing repositories are required to continue."
    error "Clone them manually or run this script again and confirm the clone."
    exit 1
  fi

  require_git

  local i
  for i in "${!missing_labels[@]}"; do
    local dest="${missing_abs[$i]}"
    local parent
    parent="$(dirname "$dest")"
    mkdir -p "$parent"
    info "Cloning ${missing_labels[$i]} into ${dest}..."
    if [ -n "${DSP_REPO_CLONE_BRANCH:-}" ]; then
      git clone -b "$DSP_REPO_CLONE_BRANCH" "${missing_urls[$i]}" "$dest"
    else
      git clone "${missing_urls[$i]}" "$dest"
    fi
    if [ ! -f "$dest/Dockerfile" ]; then
      error "Clone completed but Dockerfile not found at: ${dest}"
      exit 1
    fi
    ok "${missing_labels[$i]} cloned: ${dest}"
  done
}

# Reject legacy env vars that used to control migration on/off.
# Decision is interactive in ./setup.sh only (call after ensure_dotenv).
reject_legacy_migration_env() {
  if [ -n "${DSP_RUN_MIGRATION+x}" ]; then
    error "DSP_RUN_MIGRATION is no longer supported."
    error "Remove it from .env and run ./setup.sh (Real adopter)."
    exit 1
  fi
  if [ -n "${DSP_SKIP_MIGRATION+x}" ]; then
    error "DSP_SKIP_MIGRATION is no longer supported. Remove it from .env and run ./setup.sh again."
    exit 1
  fi
  if [ -n "${DSP_MIGRATION_SYNC_INTERVAL:-}" ]; then
    warn "DSP_MIGRATION_SYNC_INTERVAL is ignored. Schedule is DSP_MIGRATION_CRON (set by ./setup.sh)."
  fi
}

ensure_dotenv() {
  if [ ! -f .env ]; then
    info "Creating .env from .env.example"
    cp .env.example .env
    ok ".env created — review values if needed"
  else
    info "Using existing .env"
  fi

  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  migrate_dotenv_to_gateway
}

# .env anteriores ao gateway apontam o frontend para uma porta que não existe mais.
# Só reescreve valores que vieram do .env.example antigo, preservando o que o adotante ajustou.
migrate_dotenv_to_gateway() {
  local migrated=false

  if [ -z "${DSP_PUBLIC_BASE_URL:-}" ]; then
    set_env_var DSP_PUBLIC_BASE_URL "$(dsp_public_base_url)"
    migrated=true
  fi

  case "${VITE_DSP_API_URL:-}" in
    *:22666*)
      set_env_var VITE_DSP_API_URL "${DSP_BACKEND_CONTEXT_PATH:-/dsp-backend}"
      migrated=true
      ;;
  esac

  if [ "$migrated" = "true" ]; then
    warn ".env updated for the gateway (single entry point)."
    warn "Run ./config.sh to regenerate the WMS/WFS URLs in the map and download configs."
  fi
}

set_env_var() {
  local key="$1"
  local value="$2"
  local env_file="${ROOT_DIR:-.}/.env"

  if [ ! -f "$env_file" ]; then
    error ".env not found — run ensure_dotenv first."
    exit 1
  fi

  local quoted
  quoted="$(dsp_quote_dotenv_value "$value")"

  if grep -q "^${key}=" "$env_file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$quoted" '
      $0 ~ "^" k "=" { print k "=" v; next }
      { print }
    ' "$env_file" >"$tmp"
    mv "$tmp" "$env_file"
  else
    printf '\n%s=%s\n' "$key" "$quoted" >>"$env_file"
  fi

  set -a
  # shellcheck disable=SC1091
  source "$env_file"
  set +a
}

get_migration_execution_mode() {
  echo "${DSP_MIGRATION_EXECUTION_MODE:-once}"
}

is_continuous_migration_mode() {
  [ "$(get_migration_execution_mode)" = "continuous" ]
}

is_scheduled_once_migration_mode() {
  [ "$(get_migration_execution_mode)" = "scheduled-once" ]
}

is_persistent_migration_mode() {
  is_continuous_migration_mode || is_scheduled_once_migration_mode
}

migration_scheduled_once_completed() {
  local state code
  state="$(docker inspect -f '{{.State.Status}}' dsp-job-migration 2>/dev/null)" || return 1
  code="$(docker inspect -f '{{.State.ExitCode}}' dsp-job-migration 2>/dev/null)" || return 1
  [ "$state" = "exited" ] && [ "$code" = "0" ]
}

# Persists batch job schedule and mode from ./setup.sh into .env.
persist_batch_jobs_env() {
  local geo_recurring="${GEO_FILE_GENERATION_RECURRING:-true}"
  local geo_mode="once"
  local geo_restart="no"

  set_env_var "DSP_MIGRATION_EXECUTION_MODE" "${MIGRATION_EXECUTION_MODE:-once}"
  set_env_var "DSP_MIGRATION_TZ" "${DSP_MIGRATION_TZ}"
  set_env_var "DSP_MIGRATION_CRON" "${MIGRATION_CRON:-}"
  set_env_var "DSP_MIGRATION_SCHEDULED_AT" "${MIGRATION_SCHEDULED_AT:-}"
  set_env_var "DSP_GEO_FILE_GENERATION_RECURRING" "$geo_recurring"

  if [ "$geo_recurring" = "true" ]; then
    geo_mode="continuous"
    geo_restart="unless-stopped"
    set_env_var "DSP_GEO_FILE_GENERATION_CRON" "${GEO_FILE_GENERATION_CRON:-}"
  else
    set_env_var "DSP_GEO_FILE_GENERATION_CRON" ""
    if [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; then
      geo_mode="wait-for-first-load"
      geo_restart="no"
    fi
  fi

  set_env_var "DSP_GEO_FILE_GENERATION_EXECUTION_MODE" "$geo_mode"
  set_env_var "DSP_GEO_FILE_GENERATION_RESTART_POLICY" "$geo_restart"
  set_env_var "DSP_FIRST_DATA_LOAD_MARKER" "/dsp-batch-markers/first_data_load.ready"
  set_env_var "DSP_SETUP_DATA_MODE" "real"
}

is_recurring_geo_file_generation_mode() {
  [ "${DSP_GEO_FILE_GENERATION_RECURRING:-true}" = "true" ]
}

is_geo_wait_for_first_load_mode() {
  [ "${DSP_GEO_FILE_GENERATION_EXECUTION_MODE:-continuous}" = "wait-for-first-load" ]
}

# Auxiliary marker volume runs use --rm (no need to keep containers for docker logs).
# One-shot migration (run_migration_job_once) uses compose up on dsp-job-migration (container kept Exited for logs).
mark_first_data_load_ready() {
  if ! is_object_storage_stack_enabled; then
    return 0
  fi
  local marker="${DSP_FIRST_DATA_LOAD_MARKER:-/dsp-batch-markers/first_data_load.ready}"
  if docker compose --env-file .env --profile migration run --rm --no-deps \
      --entrypoint sh dsp-job-migration -c "test -f '${marker}'" 2>/dev/null; then
    return 0
  fi
  docker compose --env-file .env --profile migration run --rm --no-deps \
    --entrypoint sh dsp-job-migration -c "mkdir -p \"\$(dirname '${marker}')\" && touch '${marker}'"
}

remove_stale_compose_run_container() {
  docker rm -f "$1" >/dev/null 2>&1 || true
}

run_migration_job_once() {
  if ! wait_for_postgres_initialization dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}"; then
    return 1
  fi
  if ! wait_for_data_migration_schema; then
    return 1
  fi
  remove_stale_compose_run_container "dsp-job-migration"
  DSP_MIGRATION_EXECUTION_MODE=once docker compose --env-file .env --profile migration up --build \
    --abort-on-container-exit --exit-code-from dsp-job-migration \
    dsp-job-migration
  docker update --restart no dsp-job-migration >/dev/null 2>&1 || true
}

run_geo_file_generation_job_once() {
  wait_for_geo_file_generation_schema
  remove_stale_compose_run_container "dsp-job-geo-file-generation"
  DSP_GEO_FILE_GENERATION_EXECUTION_MODE=once docker compose --env-file .env --profile object-storage up --build \
    --abort-on-container-exit --exit-code-from dsp-job-geo-file-generation \
    dsp-job-geo-file-generation
  docker update --restart no dsp-job-geo-file-generation >/dev/null 2>&1 || true
}

start_migration_service_stack() {
  info "Starting migration service stack (profile=migration)..."
  if ! wait_for_postgres_initialization dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}"; then
    exit 1
  fi
  if ! wait_for_data_migration_schema; then
    exit 1
  fi
  docker compose --env-file .env --profile migration up -d --build dsp-job-migration
  if is_continuous_migration_mode; then
    docker update --restart unless-stopped dsp-job-migration >/dev/null 2>&1 || true
  else
    docker update --restart no dsp-job-migration >/dev/null 2>&1 || true
  fi
  ok "Migration service stack ready"
}

ensure_migration_service_if_needed() {
  if is_scheduled_once_migration_mode && migration_scheduled_once_completed; then
    info "Scheduled one-shot migration already finished — not restarting the job container."
    return 0
  fi
  if ! is_persistent_migration_mode; then
    return 0
  fi
  start_migration_service_stack
}

# Brazil demo (quickstart) does not run SeaweedFS nor the geo-file job.
is_object_storage_stack_enabled() {
  ! is_quickstart_configured
}

is_geo_file_generation_enabled() {
  is_object_storage_stack_enabled
}

compose_profile_args() {
  COMPOSE_PROFILE_ARGS=(--profile migration)
  if is_object_storage_stack_enabled; then
    COMPOSE_PROFILE_ARGS+=(--profile object-storage)
  fi
}

clear_object_storage_env_for_demo() {
  set_env_var "DSP_SETUP_DATA_MODE" "demo"
  set_env_var "DSP_OBJECT_STORAGE_ENDPOINT" ""
  set_env_var "DSP_OBJECT_STORAGE_ACCESS_KEY" ""
  set_env_var "DSP_OBJECT_STORAGE_SECRET_KEY" ""
  set_env_var "DSP_MIGRATION_EXECUTION_MODE" "once"
  set_env_var "DSP_MIGRATION_CRON" ""
  set_env_var "DSP_MIGRATION_SCHEDULED_AT" ""
  set_env_var "DSP_GEO_FILE_GENERATION_RECURRING" "true"
  set_env_var "DSP_GEO_FILE_GENERATION_CRON" ""
  set_env_var "DSP_GEO_FILE_GENERATION_EXECUTION_MODE" "continuous"
}

# Demonstration setup (./setup.sh option 1): DBs + GeoServers only; no migration/object-storage jobs.
is_demo_stack_mode() {
  [ "${DSP_SETUP_DATA_MODE:-}" = "demo" ]
}

wait_for_object_storage_health() {
  info "Waiting for dsp-object-storage (SeaweedFS S3 API)..."
  local attempt=0
  local health=""

  while [ "$attempt" -lt 60 ]; do
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' dsp-object-storage 2>/dev/null || echo missing)"
    case "$health" in
      healthy)
        ok "dsp-object-storage ready"
        return 0
        ;;
      unhealthy)
        error "dsp-object-storage is unhealthy."
        docker compose --env-file .env --profile object-storage logs --tail 40 dsp-object-storage || true
        return 1
        ;;
    esac
    attempt=$((attempt + 1))
    sleep 2
  done

  error "dsp-object-storage did not become healthy in time."
  docker compose --env-file .env --profile object-storage logs --tail 40 dsp-object-storage || true
  return 1
}

start_object_storage_service() {
  info "Starting object storage (SeaweedFS, profile=object-storage)..."
  docker compose --env-file .env --profile object-storage up -d --build dsp-object-storage
  wait_for_object_storage_health
}

start_geo_file_generation_service() {
  info "Starting geo file generation service (profile=object-storage)..."
  wait_for_geo_file_generation_schema
  docker compose --env-file .env --profile object-storage up -d --build dsp-job-geo-file-generation
  ok "Geo file generation service ready (cron=${DSP_GEO_FILE_GENERATION_CRON:-0 2 * * *})"
}

ensure_object_storage_ready() {
  if ! is_object_storage_stack_enabled; then
    return 0
  fi
  ensure_dsp_repositories --geo-file-job
  start_object_storage_service
}

ensure_object_storage_stack() {
  if ! is_object_storage_stack_enabled; then
    return 0
  fi
  ensure_object_storage_ready
  if is_recurring_geo_file_generation_mode; then
    start_geo_file_generation_service
    return 0
  fi
  if is_geo_wait_for_first_load_mode && ! first_data_load_marker_exists; then
    start_geo_file_generation_wait_service
  fi
}

first_data_load_marker_exists() {
  local marker="${DSP_FIRST_DATA_LOAD_MARKER:-/dsp-batch-markers/first_data_load.ready}"
  docker compose --env-file .env --profile migration run --rm --no-deps \
    --entrypoint test dsp-job-migration -f "$marker" 2>/dev/null
}

start_geo_file_generation_wait_service() {
  info "Starting geo file generation (wait-for-first-load, profile=object-storage)..."
  wait_for_geo_file_generation_schema
  docker compose --env-file .env --profile object-storage up -d --build dsp-job-geo-file-generation
  ok "Geo file job is waiting — pre-generated downloads will be built once after the scheduled migration finishes."
}

# One-shot geo generation during ./setup.sh after the first migration and GeoServer populate.
run_initial_geo_file_generation_if_needed() {
  if [ "${WILL_MIGRATE:-false}" != "true" ]; then
    return 0
  fi
  if ! is_geo_file_generation_enabled; then
    return 0
  fi
  if [ "${GEO_FILE_GENERATION_RECURRING:-true}" != "true" ] && \
     [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; then
    return 0
  fi
  info "Running initial geo file generation (one-shot; may take a while)..."
  if ! run_geo_file_generation_job_once; then
    error "Initial geo file generation failed. Data migration already completed."
    print_geo_file_generation_hints
    exit 1
  fi
  ok "Initial geo file generation finished"
  mark_first_data_load_ready
}

# Step 11 orchestration: object storage plus geo once, waiter, or recurring service.
ensure_geo_file_generation_after_setup() {
  if ! is_geo_file_generation_enabled; then
    return 0
  fi
  ensure_object_storage_ready
  if [ "${GEO_FILE_GENERATION_RECURRING:-true}" = "true" ]; then
    run_initial_geo_file_generation_if_needed
    start_geo_file_generation_service
    return 0
  fi
  if [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; then
    start_geo_file_generation_wait_service
    return 0
  fi
  run_initial_geo_file_generation_if_needed
}

ensure_geo_file_generation_service_if_needed() {
  ensure_object_storage_stack
}

print_geo_file_generation_hints() {
  if ! is_geo_file_generation_enabled; then
    echo ""
    echo "Pre-generated download files: disabled (Brazil demo — downloads served by the WFS)."
    return 0
  fi
  echo ""
  if is_recurring_geo_file_generation_mode; then
    echo "Pre-generated download files: bucket ${DSP_OBJECT_STORAGE_BUCKET:-dsp-geo-files}" \
      "at ${DSP_OBJECT_STORAGE_ENDPOINT:-http://dsp-object-storage:8333} (cron=${DSP_GEO_FILE_GENERATION_CRON:-0 2 * * *})"
    echo "Optional extra one-shot (in addition to the schedule):"
    echo "  docker rm -f dsp-job-geo-file-generation; DSP_GEO_FILE_GENERATION_EXECUTION_MODE=once docker compose --env-file .env --profile object-storage up --build --abort-on-container-exit --exit-code-from dsp-job-geo-file-generation dsp-job-geo-file-generation"
    echo "  Logs: docker logs dsp-job-geo-file-generation"
    return 0
  fi
  if is_geo_wait_for_first_load_mode || [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; then
    echo "Pre-generated download files: built once automatically after the migration job completes."
    if [ -n "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
      echo "  Waiting for scheduled migration at ${DSP_MIGRATION_SCHEDULED_AT} (${DSP_MIGRATION_TZ})."
    fi
    echo "  The geo file job is already running in wait-for-first-load mode."
    echo "  Optional manual one-shot:"
    echo "  docker rm -f dsp-job-geo-file-generation; DSP_GEO_FILE_GENERATION_EXECUTION_MODE=once docker compose --env-file .env --profile object-storage up --build --abort-on-container-exit --exit-code-from dsp-job-geo-file-generation dsp-job-geo-file-generation"
    echo "  Logs: docker logs dsp-job-geo-file-generation"
    return 0
  fi
  echo "Pre-generated download files: one-time generation (no recurring geo job)."
  echo "  docker rm -f dsp-job-geo-file-generation; DSP_GEO_FILE_GENERATION_EXECUTION_MODE=once docker compose --env-file .env --profile object-storage up --build --abort-on-container-exit --exit-code-from dsp-job-geo-file-generation dsp-job-geo-file-generation"
  echo "  Logs: docker logs dsp-job-geo-file-generation"
}

print_migration_resync_hints() {
  if ! is_persistent_migration_mode; then
    return 0
  fi
  local mode cron tz
  mode="$(get_migration_execution_mode)"
  cron="${DSP_MIGRATION_CRON:-}"
  tz="${DSP_MIGRATION_TZ}"
  echo ""
  echo "Migration execution mode: ${mode} (tz=${tz}${cron:+ cron=${cron}})"
  if [ -n "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
    echo "GeoServer layers are published automatically after the first scheduled migration."
    if { is_geo_wait_for_first_load_mode || [ "${GEO_FILE_GENERATION_WAIT:-false}" = "true" ]; } \
        && is_object_storage_stack_enabled; then
      echo "Pre-generated download files are built once right after that migration (geo file job)."
    fi
  fi
  echo "Optional one-shot re-sync (in addition to the schedule):"
  echo "  docker rm -f dsp-job-migration; DSP_MIGRATION_EXECUTION_MODE=once docker compose --env-file .env --profile migration up --build --abort-on-container-exit --exit-code-from dsp-job-migration dsp-job-migration"
  echo "  Logs: docker logs dsp-job-migration"
}

ensure_adopter_config() {
  local example="$ROOT_DIR/config/adopter/adopter-config.yaml.example"
  local active="$ROOT_DIR/config/adopter/adopter-config.yaml"
  local apply_script="$ROOT_DIR/scripts/apply_adopter_config.py"

  if [ ! -f "$example" ]; then
    error "Adopter configuration template not found: $example"
    exit 1
  fi
  if [ ! -f "$active" ]; then
    error "Adopter configuration not found: $active"
    error "Run ./config.sh to fill in the allowed fields and try again."
    exit 1
  fi
  if cmp -s "$active" "$example"; then
    error "The adopter configuration is still identical to the template."
    error "Run ./config.sh to fill in the allowed fields."
    exit 1
  fi
  if ! python3 "$apply_script" --root "$ROOT_DIR" --config "$active" --quiet; then
    error "Could not generate the DSP configuration files."
    error "Fix $active or run ./config.sh again."
    exit 1
  fi
  # Applying the configuration may update .env; reload it before continuing.
  ensure_dotenv
  ok "Adopter configuration applied safely"
}

start_databases_and_wait() {
  info "Starting databases (dsp-db, dsp-geoserver-db)..."
  docker compose --env-file .env up -d --build dsp-db dsp-geoserver-db
  ok "Database containers started"

  info "Waiting for dsp-db PostgreSQL initialization..."
  if ! wait_for_postgres_initialization dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}"; then
    exit 1
  fi
  if ! wait_for_db_schema dsp-db "${DSP_DB_USER:-dsp}" "${DSP_DB_NAME:-dsp-db}" dsp; then
    error "dsp-db init SQL did not create schema 'dsp' in time."
    docker compose --env-file .env logs --tail 40 dsp-db || true
    exit 1
  fi
  if ! wait_for_data_migration_schema; then
    exit 1
  fi
  ok "dsp-db ready"

  info "Waiting for dsp-geoserver-db PostgreSQL initialization..."
  if ! wait_for_postgres_initialization dsp-geoserver-db "${DSP_GEOSERVER_DB_USER:-dsp_geo}" "${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}"; then
    exit 1
  fi
  if ! wait_for_db_schema dsp-geoserver-db "${DSP_GEOSERVER_DB_USER:-dsp_geo}" "${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}" dsp; then
    error "dsp-geoserver-db init SQL did not create schema 'dsp' in time."
    docker compose --env-file .env logs --tail 40 dsp-geoserver-db || true
    exit 1
  fi
  ok "dsp-geoserver-db ready"

  ok "Databases are ready"
}

# Checks config file exists and JSON is valid (no template comparison).
ensure_runtime_json_file() {
  local label="$1"
  local active="$2"

  if [ ! -f "$active" ]; then
    error "${label} not found:"
    echo "        $active"
    error "Run ./config.sh and ./setup.sh first."
    exit 1
  fi
  if ! validate_json_file "$active"; then
    error "${label} contains invalid JSON:"
    echo "        $active"
    exit 1
  fi
  ok "${label} present: $active"
}

# Light validation for ./start.sh (exists + valid JSON; no template comparison).
ensure_runtime_config_files_exist() {
  ensure_runtime_json_file "Installation config" \
    "$ROOT_DIR/config/installation/installation-config.json"
  ensure_runtime_json_file "Map layers config" \
    "$ROOT_DIR/config/map/mapLayersConfig.json"
  ensure_runtime_json_file "Download themes config" \
    "$ROOT_DIR/config/downloads/downloadThemesConfig.json"
}

# Infrastructure container is ready (HEALTHY, RUNNING, or STARTING in compose ps).
is_setup_infra_service_ready() {
  local svc="$1"
  local status

  status="$(stack_service_status "$svc")"
  case "$status" in
    HEALTHY|RUNNING|STARTING)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Core DB + GeoServer services required for both demo and real adopter.
setup_infra_core_services() {
  printf '%s\n' \
    dsp-db \
    dsp-geoserver-db \
    dsp-geoserver-exhibition \
    dsp-geoserver-download
}

# Services ./setup.sh must leave running before ./start.sh.
setup_infra_required_services() {
  if is_demo_stack_mode || is_quickstart_configured; then
    setup_infra_core_services
    return 0
  fi

  setup_infra_core_services

  if is_persistent_migration_mode; then
    if is_scheduled_once_migration_mode && migration_scheduled_once_completed; then
      :
    else
      printf '%s\n' dsp-job-migration
    fi
  fi

  if ! is_object_storage_stack_enabled; then
    return 0
  fi

  printf '%s\n' dsp-object-storage
  if is_recurring_geo_file_generation_mode || is_geo_wait_for_first_load_mode; then
    printf '%s\n' dsp-job-geo-file-generation
  fi
}

# Hint after require_setup_infra_ready fails (copy-paste compose command).
print_infra_recovery_hint() {
  local profiles=""
  local services="dsp-db dsp-geoserver-db dsp-geoserver-exhibition dsp-geoserver-download"

  if is_demo_stack_mode || is_quickstart_configured; then
    echo ""
    echo "Infrastructure is not ready. ./start.sh only starts backend, frontend and gateway."
    echo "First time: run ./setup.sh (Demonstration or Real adopter)."
    echo "After 'docker compose down' (without -v), start demonstration infrastructure again:"
    echo ""
    echo "  docker compose --env-file .env up -d --build ${services}"
    echo ""
    echo "Then run ./start.sh again."
    echo ""
    return 0
  fi

  profiles="--profile migration"
  if is_object_storage_stack_enabled; then
    profiles="${profiles} --profile object-storage"
  fi
  if is_persistent_migration_mode; then
    if ! { is_scheduled_once_migration_mode && migration_scheduled_once_completed; }; then
      services="${services} dsp-job-migration"
    fi
  fi
  if is_object_storage_stack_enabled; then
    services="${services} dsp-object-storage"
    if is_recurring_geo_file_generation_mode || is_geo_wait_for_first_load_mode; then
      services="${services} dsp-job-geo-file-generation"
    fi
  fi

  echo ""
  echo "Infrastructure is not ready. ./start.sh only starts backend, frontend and gateway."
  echo "First time: run ./setup.sh"
  echo "After 'docker compose down' (without -v), start infrastructure again (no migration, no layer republish):"
  echo ""
  echo "  docker compose --env-file .env ${profiles} up -d --build ${services}"
  echo ""
  echo "Then run ./start.sh again."
  echo ""
}

# Exits if any setup_infra_required_services container is not running.
require_setup_infra_ready() {
  local svc
  local missing=false
  local attempt=0
  local max_attempts=30

  if is_demo_stack_mode || is_quickstart_configured; then
    info "Demonstration stack: checking DBs and GeoServers only."
  fi

  while [ "$attempt" -lt "$max_attempts" ]; do
    missing=false
    load_stack_service_statuses true
    while IFS= read -r svc; do
      [ -z "$svc" ] && continue
      if ! is_setup_infra_service_ready "$svc"; then
        missing=true
        break
      fi
    done < <(setup_infra_required_services)

    if [ "$missing" = false ]; then
      ok "Infrastructure is running"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -lt "$max_attempts" ]; then
      sleep 2
    fi
  done

  load_stack_service_statuses true
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    if ! is_setup_infra_service_ready "$svc"; then
      error "Infrastructure service not ready: ${svc} ($(stack_service_status "$svc"))"
    fi
  done < <(setup_infra_required_services)

  print_infra_recovery_hint
  exit 1
}

# Starts backend, frontend and gateway without compose depends_on (DBs/GeoServers).
start_application_stack() {
  info "Building and starting application containers..."
  # --no-deps: do not start DBs/GeoServers via depends_on; infra was validated earlier.
  docker compose --env-file .env up -d --build --no-deps dsp-backend dsp-frontend
  ok "Backend and frontend are running"
  start_gateway
}

# Runtime stack status helpers (container state / Docker healthcheck — no HTTP probes).

is_stack_optional_service() {
  false
}

get_stack_runtime_services() {
  local svc
  compose_profile_args
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    [ "$svc" = "dsp-job-migration" ] && continue
    printf '%s\n' "$svc"
  done < <(docker compose --env-file .env "${COMPOSE_PROFILE_ARGS[@]}" config --services 2>/dev/null || true)
}

compose_status_label() {
  local state="$1"
  local health="$2"

  if [ "$state" != "running" ]; then
    echo "STOPPED"
    return
  fi
  case "$health" in
    healthy) echo "HEALTHY" ;;
    unhealthy) echo "UNHEALTHY" ;;
    starting) echo "STARTING" ;;
    *) echo "RUNNING" ;;
  esac
}

load_stack_service_statuses() {
  local refresh="${1:-false}"
  local line svc state health label runtime_svc

  if [ "$refresh" != "true" ] && [ "${#STACK_SERVICE_STATUSES[@]}" -gt 0 ]; then
    return
  fi

  STACK_SERVICE_STATUSES=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    svc="${line%%|*}"
    line="${line#*|}"
    state="${line%%|*}"
    health="${line#*|}"
    label="$(compose_status_label "$state" "$health")"
    STACK_SERVICE_STATUSES["$svc"]="$label"
  done < <(docker compose --env-file .env ps -a --format '{{.Service}}|{{.State}}|{{.Health}}' 2>/dev/null || true)

  while IFS= read -r runtime_svc; do
    [ -z "$runtime_svc" ] && continue
    if [ -z "${STACK_SERVICE_STATUSES[$runtime_svc]+x}" ]; then
      STACK_SERVICE_STATUSES["$runtime_svc"]="STOPPED"
    fi
  done < <(get_stack_runtime_services)
}

stack_service_status() {
  echo "${STACK_SERVICE_STATUSES[$1]:-STOPPED}"
}

is_stack_service_up() {
  [ "$(stack_service_status "$1")" != "STOPPED" ]
}

print_stack_service_status() {
  local svc status note

  load_stack_service_statuses true
  echo ""
  info "Checking this project's Docker containers..."
  echo ""
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    status="$(stack_service_status "$svc")"
    note=""
    if is_stack_optional_service "$svc"; then
      note="  (optional — setup/migration)"
    fi
    printf '  [%s] %s%s\n' "$status" "$svc" "$note"
  done < <(get_stack_runtime_services)
  echo ""
}

stack_required_services() {
  local -a services=("${STACK_REQUIRED_SERVICES[@]}")
  if is_object_storage_stack_enabled; then
    services+=(dsp-object-storage dsp-job-geo-file-generation)
  fi
  printf '%s\n' "${services[@]}"
}

print_stack_summary() {
  local svc status
  local required_total=0
  local required_up=0
  local has_caveat=false
  local any_up=false

  load_stack_service_statuses

  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    required_total=$((required_total + 1))
    status="$(stack_service_status "$svc")"
    if is_stack_service_up "$svc"; then
      required_up=$((required_up + 1))
      any_up=true
      case "$status" in
        UNHEALTHY|STARTING) has_caveat=true ;;
      esac
    fi
  done < <(stack_required_services)

  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    if is_stack_service_up "$svc"; then
      any_up=true
    fi
  done < <(get_stack_runtime_services)

  if [ "$any_up" = false ]; then
    warn "Stack is off — no project containers are running."
  elif [ "$required_up" -lt "$required_total" ]; then
    warn "Partial stack — ${required_up} of ${required_total} required services running."
  elif [ "$has_caveat" = true ]; then
    warn "Stack is running with health caveats (UNHEALTHY or STARTING containers)."
  else
    ok "Stack ready — all required services are running."
  fi
  info "Container state only — HTTP endpoints are not probed."
}

print_stack_url_line() {
  local label="$1"
  local status="$2"
  local url="$3"

  if [ -n "$status" ]; then
    printf '%-22s [%s] %s\n' "${label}:" "$status" "$url"
  else
    printf '%-22s %s\n' "${label}:" "$url"
  fi
}

# compose down does not remove one-off containers from compose run (without --rm they stay Exited);
# resolve project name so explicit teardown can remove them.
compose_project_name() {
  if [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
    echo "$COMPOSE_PROJECT_NAME"
    return 0
  fi

  local from_label=""
  local cname
  for cname in dsp-db dsp-gateway dsp-geoserver-db dsp-job-migration; do
    from_label="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project"}}' "$cname" 2>/dev/null || true)"
    if [ -n "$from_label" ]; then
      echo "$from_label"
      return 0
    fi
  done

  local root="${ROOT_DIR:-}"
  if [ -z "$root" ]; then
    root="$(pwd)"
  fi
  basename "$root"
}

compose_remove_project_containers() {
  local project cid
  project="$(compose_project_name)"
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    docker rm -f "$cid" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)
}

# Tear down compose services (migration + object-storage profiles), including Exited compose run containers.
compose_down_project() {
  local project remaining
  compose_remove_project_containers
  docker compose --env-file .env \
    --profile migration \
    --profile object-storage \
    down "$@" --remove-orphans
  project="$(compose_project_name)"
  remaining="$(docker ps -aq --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)"
  if [ -n "$remaining" ]; then
    warn "Some project containers could not be removed:"
    docker ps -a --filter "label=com.docker.compose.project=${project}" \
      --format '  {{.Names}} ({{.ID}})' 2>/dev/null || true
  fi
}

# Status of this project's compose services + URLs; optional project cleanup; then exit.
show_stack_status_menu() {
  print_stack_service_status
  print_stack_summary
  print_stack_urls with-status
  print_stack_usage_hints

  echo ""
  echo "What do you want to do?"
  echo "  1) Remove this project's containers, volumes and images"
  echo "  2) Exit"
  local action=""
  read -r -p "Choice [1/2]: " action || true
  case "$action" in
    1)
      echo ""
      warn "This deletes ONLY this project's Docker resources (compose down -v --rmi all, migration profile included)."
      warn "Database data in project volumes will be lost."
      local confirm=""
      read -r -p "Type YES to confirm cleanup: " confirm || true
      if [ "$confirm" != "YES" ]; then
        info "Cleanup cancelled."
        exit 0
      fi
      info "Removing project containers, volumes and images..."
      compose_down_project -v --rmi all
      ok "Project Docker resources removed."
      exit 0
      ;;
    2|"")
      info "Exiting."
      exit 0
      ;;
    *)
      error "Invalid choice: '${action}' — use 1 (cleanup) or 2 (exit)."
      exit 1
      ;;
  esac
}

# Interactive data-prep menu for ./setup.sh.
# Sets globals: SETUP_MODE (demo|real), WILL_MIGRATE, KEEP_MIGRATION_SERVICE,
# MIGRATION_EXECUTION_MODE, MIGRATION_CRON, MIGRATION_SCHEDULED_AT,
# GEO_FILE_GENERATION_CRON, GEO_FILE_GENERATION_RECURRING, GEO_FILE_GENERATION_WAIT.
# Not a command substitution on purpose: error output must reach the terminal.
prompt_setup_data_mode() {
  echo ""
  echo "This step prepares geographic data in the local DSP databases and publishes GeoServer layers (Exhibition + Download)."
  echo "Pick the option that matches your goal:"
  echo ""
  echo "  1) Demonstration (built-in Brazil seed, no JDBC)"
  echo "     Loads demo map data from built-in SQL — no source database or migration job."
  echo "     Use when exploring the UI, evaluating the stack, or when you do not have adopter data yet."
  echo ""
  echo "  2) Real adopter — migrate from JDBC source (ETL)"
  echo "     Requires ./config.sh first, then runs ETL from your JDBC source into dsp-db and the GeoServer DB."
  echo "     Use for a production-like setup when your source database is ready to import."
  echo ""
  echo "  3) Stack status / cleanup / exit"
  echo "     Shows container status and service URLs; optionally removes this project's Docker resources, then exits."
  echo "     Use to inspect the stack or reset containers/volumes without loading or migrating data."
  echo ""
  echo "How do you want to prepare data?"
  local choice=""
  read -r -p "Choice [1/2/3]: " choice || true
  case "$choice" in
    1)
      SETUP_MODE="demo"
      WILL_MIGRATE=false
      KEEP_MIGRATION_SERVICE=false
      ;;
    2)
      SETUP_MODE="real"
      prompt_real_adopter_migration_plan
      ;;
    3)
      show_stack_status_menu
      ;;
    *)
      error "Invalid choice: '${choice}' — use 1 (demonstration), 2 (real adopter) or 3 (status)."
      error "Run './${DSP_ORCHESTRATION_SCRIPT}' again."
      exit 1
      ;;
  esac
}

prompt_schedule_hhmm() {
  local prompt_label="${1:-Time}"
  local default_hhmm="${2:-22:00}"
  local -n out_hhmm=$3
  local raw normalized
  while true; do
    read -r -p "${prompt_label} [${default_hhmm}]: " raw || true
    if [ -z "$raw" ]; then
      raw="$default_hhmm"
    fi
    if normalized="$(dsp_normalize_hhmm "$raw")"; then
      out_hhmm="$normalized"
      return 0
    fi
    error "Invalid time: '${raw}' — use HH:MM (e.g. 22:00)."
  done
}

prompt_migration_hhmm() {
  local prompt_label="${1:-Time}"
  local default_hhmm="${2:-22:00}"
  prompt_schedule_hhmm "$prompt_label" "$default_hhmm" MIGRATION_HHMM
}

# Writes a 5-field cron into the variable named by $2 (nameref).
# $1 intro question, $2 output var name, $3 optional HH:MM for daily reuse, $4 default daily HH:MM.
prompt_recurring_schedule_cron() {
  local question="$1"
  local cron_var_name="$2"
  local hhmm="${3:-}"
  local default_daily_hhmm="${4:-22:00}"
  local -n cron_out=$cron_var_name
  local freq_choice step picked_hhmm built

  echo ""
  echo "$question"
  echo ""
  if [ -n "$hhmm" ]; then
    echo "  1) Every day at this time (${hhmm})"
  else
    echo "  1) Every day at a given time"
  fi
  echo "  2) Every N hours"
  echo "  3) Every N minutes"
  echo "  4) Custom cron expression (5 fields)"
  echo ""
  while true; do
    read -r -p "Choice [1]: " freq_choice || true
    case "${freq_choice:-1}" in
      1|2|3|4)
        break
        ;;
      *)
        error "Invalid choice: '${freq_choice}' — use 1 (every day), 2 (every N hours), 3 (every N minutes) or 4 (custom cron)."
        ;;
    esac
  done
  case "${freq_choice:-1}" in
    1)
      if [ -z "$hhmm" ]; then
        prompt_schedule_hhmm "Time" "$default_daily_hhmm" picked_hhmm
        hhmm="$picked_hhmm"
      fi
      cron_out="$(dsp_build_daily_cron "$hhmm")"
      ;;
    2)
      while true; do
        read -r -p "Every how many hours? [6]: " step || true
        if [ -z "$step" ]; then
          step="6"
        fi
        if built="$(dsp_build_hourly_cron "$step")"; then
          cron_out="$built"
          case "$step" in
            6) echo "  Runs at 00:00, 06:00, 12:00, and 18:00." ;;
            24) echo "  Runs once per day at 00:00." ;;
            *) echo "  Runs at minute 0 every ${step} hours (aligned to midnight)." ;;
          esac
          break
        fi
        error "Invalid interval: '${step}' — use 1, 2, 3, 4, 6, 8, 12 or 24."
      done
      ;;
    3)
      while true; do
        read -r -p "Every how many minutes? [5]: " step || true
        if [ -z "$step" ]; then
          step="5"
        fi
        if built="$(dsp_build_minute_cron "$step")"; then
          cron_out="$built"
          break
        fi
        error "Invalid interval: '${step}' — use an integer from 1 to 59."
      done
      ;;
    4)
      while true; do
        local raw_cron
        read -r -p "Cron (minute hour day month weekday) [0 22 * * *]: " raw_cron || true
        if [ -z "$raw_cron" ]; then
          raw_cron="0 22 * * *"
        fi
        if built="$(dsp_normalize_cron_5 "$raw_cron")"; then
          cron_out="$built"
          break
        fi
        error "Invalid cron: '${raw_cron}' — enter exactly 5 fields (e.g. 0 22 * * * or */15 * * * *)."
      done
      ;;
  esac
  ok "Schedule cron: ${cron_out}"
}

# Sets MIGRATION_CRON. $1 optional HH:MM from a scheduled first run — reused for daily cron.
prompt_migration_how_often() {
  local hhmm="${1:-}"
  prompt_recurring_schedule_cron \
    "How often should the data be synchronized after the initial migration?" \
    MIGRATION_CRON \
    "$hhmm" \
    "22:00"
}

# Sets GEO_FILE_GENERATION_CRON (same schedule menu as data migration).
prompt_geo_file_generation_schedule() {
  echo ""
  echo "Pre-generated download files (object storage)"
  if [ -n "${MIGRATION_CRON:-}" ]; then
    echo "  Migration re-sync cron: ${MIGRATION_CRON}"
  fi
  echo "  Schedule pre-generation in a window after migration (migration raises the flags)."
  prompt_recurring_schedule_cron \
    "How often should pre-generated download files be built?" \
    GEO_FILE_GENERATION_CRON \
    "" \
    "02:00"
}

# Scheduled first run. Sets MIGRATION_SCHEDULED_AT and MIGRATION_HHMM.
# Timezone: DSP_MIGRATION_TZ (already loaded from .env by ensure_dotenv).
prompt_migration_when() {
  local date_ymd today
  echo ""
  echo "Enter the date and time for the first migration:"
  today="$(TZ="${DSP_MIGRATION_TZ}" date +%F)"
  while true; do
    read -r -p "Date (YYYY-MM-DD) [${today}]: " date_ymd || true
    if [ -z "$date_ymd" ]; then
      date_ymd="$today"
    fi
    if ! dsp_valid_iso_date "$date_ymd"; then
      error "Invalid date: '${date_ymd}' — use YYYY-MM-DD."
      continue
    fi
    prompt_migration_hhmm "Time" "22:00"
    if dsp_datetime_is_future "$date_ymd" "$MIGRATION_HHMM" "$DSP_MIGRATION_TZ"; then
      MIGRATION_SCHEDULED_AT="${date_ymd} ${MIGRATION_HHMM}:00"
      ok "Scheduled for ${MIGRATION_SCHEDULED_AT} (${DSP_MIGRATION_TZ})"
      return 0
    fi
    error "That date/time is in the past. Choose a future time."
  done
}

# Real adopter: preset data-update model, then migration/geo crons when applicable.
prompt_real_adopter_migration_plan() {
  local preset after_choice

  WILL_MIGRATE=false
  KEEP_MIGRATION_SERVICE=false
  MIGRATION_CRON=""
  MIGRATION_SCHEDULED_AT=""
  GEO_FILE_GENERATION_CRON=""
  GEO_FILE_GENERATION_RECURRING=true
  GEO_FILE_GENERATION_WAIT=false

  echo ""
  echo "How will your source data be updated over time?"
  echo ""
  echo "  1) One-time load — import once, source does not change"
  echo "  2) Living source — periodic re-sync from JDBC"
  echo "  3) Deferred first load — first migration at a chosen date and time"
  echo ""
  read -r -p "Choice [1/2/3]: " preset || true
  case "$preset" in
    1|"")
      WILL_MIGRATE=true
      MIGRATION_EXECUTION_MODE="once"
      KEEP_MIGRATION_SERVICE=false
      GEO_FILE_GENERATION_RECURRING=false
      GEO_FILE_GENERATION_WAIT=false
      ;;
    2)
      WILL_MIGRATE=true
      MIGRATION_EXECUTION_MODE="continuous"
      KEEP_MIGRATION_SERVICE=true
      GEO_FILE_GENERATION_RECURRING=true
      prompt_migration_how_often
      prompt_geo_file_generation_schedule
      ;;
    3)
      prompt_migration_when
      echo ""
      echo "After the first load, will the source be re-synchronized?"
      echo ""
      echo "  1) No — static data (one-time load only)"
      echo "  2) Yes — periodic re-sync"
      echo ""
      read -r -p "Choice [1/2]: " after_choice || true
      case "${after_choice:-1}" in
        1|"")
          WILL_MIGRATE=false
          MIGRATION_EXECUTION_MODE="scheduled-once"
          KEEP_MIGRATION_SERVICE=true
          GEO_FILE_GENERATION_RECURRING=false
          GEO_FILE_GENERATION_WAIT=true
          info "The migration job will run at the scheduled time, load data, and publish GeoServer layers."
          info "Pre-generated download files will then be built once automatically (no separate geo schedule)."
          ;;
        2)
          WILL_MIGRATE=false
          MIGRATION_EXECUTION_MODE="continuous"
          KEEP_MIGRATION_SERVICE=true
          GEO_FILE_GENERATION_RECURRING=true
          prompt_migration_how_often "$MIGRATION_HHMM"
          prompt_geo_file_generation_schedule
          ;;
        *)
          error "Invalid choice: '${after_choice}' — use 1 (static) or 2 (re-sync)."
          error "Run './${DSP_ORCHESTRATION_SCRIPT}' again."
          exit 1
          ;;
      esac
      ;;
    *)
      error "Invalid choice: '${preset}' — use 1 (one-time), 2 (living source) or 3 (deferred)."
      error "Run './${DSP_ORCHESTRATION_SCRIPT}' again."
      exit 1
      ;;
  esac
}

# Ensures quickstart UI/map configs (overwrites configs from another installation).
ensure_quickstart_adopter_configs() {
  local install_example="$ROOT_DIR/config/installation/installation-config.quickstart.json.example"
  local install_active="$ROOT_DIR/config/installation/installation-config.json"
  local map_example="$ROOT_DIR/config/map/mapLayersConfig.quickstart.json.example"
  local map_active="$ROOT_DIR/config/map/mapLayersConfig.json"
  local download_example="$ROOT_DIR/config/downloads/downloadThemesConfig.quickstart.json.example"
  local download_active="$ROOT_DIR/config/downloads/downloadThemesConfig.json"
  local about_example="$ROOT_DIR/config/about/about-config.quickstart.json.example"
  local about_active="$ROOT_DIR/config/about/about-config.json"
  local about_dir="$ROOT_DIR/config/about"

  if [ ! -f "$install_example" ]; then
    error "Quickstart installation template not found at: $install_example"
    exit 1
  fi
  if [ ! -f "$map_example" ]; then
    error "Quickstart map layers template not found at: $map_example"
    exit 1
  fi
  if [ ! -f "$download_example" ]; then
    error "Quickstart download themes template not found at: $download_example"
    exit 1
  fi
  if [ ! -f "$about_example" ]; then
    error "Quickstart about config template not found at: $about_example"
    exit 1
  fi

  cp "$install_example" "$install_active"
  info "Installation config set from quickstart template:"
  echo "       $install_active"

  cp "$map_example" "$map_active"
  info "Map layers config set from quickstart template:"
  echo "       $map_active"

  cp "$download_example" "$download_active"
  info "Download themes config set from quickstart template:"
  echo "       $download_active"

  cp "$about_example" "$about_active"
  info "About config set from quickstart template:"
  echo "       $about_active"

  for about_md in overview features configuration license; do
    local about_md_example="$about_dir/${about_md}.quickstart.md.example"
    local about_md_active="$about_dir/${about_md}.md"
    if [ ! -f "$about_md_example" ]; then
      error "Quickstart about markdown template not found at: $about_md_example"
      exit 1
    fi
    cp "$about_md_example" "$about_md_active"
  done
  info "About markdown tabs set from quickstart templates in:"
  echo "       $about_dir"

  if ! validate_json_file "$install_active"; then
    error "Installation config contains invalid JSON: $install_active"
    exit 1
  fi
  if ! validate_json_file "$map_active"; then
    error "Map layers config contains invalid JSON: $map_active"
    exit 1
  fi
  validate_map_layers_wms_ids "$map_active"

  if ! validate_json_file "$download_active"; then
    error "Download themes config contains invalid JSON: $download_active"
    exit 1
  fi
  validate_download_themes_config "$download_active"

  if ! validate_json_file "$about_active"; then
    error "About config contains invalid JSON: $about_active"
    exit 1
  fi
}

is_quickstart_configured() {
  local install_example="$ROOT_DIR/config/installation/installation-config.quickstart.json.example"
  local install_active="$ROOT_DIR/config/installation/installation-config.json"
  local map_example="$ROOT_DIR/config/map/mapLayersConfig.quickstart.json.example"
  local map_active="$ROOT_DIR/config/map/mapLayersConfig.json"
  local download_example="$ROOT_DIR/config/downloads/downloadThemesConfig.quickstart.json.example"
  local download_active="$ROOT_DIR/config/downloads/downloadThemesConfig.json"
  local about_example="$ROOT_DIR/config/about/about-config.quickstart.json.example"
  local about_active="$ROOT_DIR/config/about/about-config.json"
  [ -f "$install_example" ] &&
    [ -f "$install_active" ] &&
    [ -f "$map_example" ] &&
    [ -f "$map_active" ] &&
    [ -f "$download_example" ] &&
    [ -f "$download_active" ] &&
    [ -f "$about_example" ] &&
    [ -f "$about_active" ] &&
    [ -f "$ROOT_DIR/config/about/overview.md" ] &&
    [ -f "$ROOT_DIR/config/about/features.md" ] &&
    [ -f "$ROOT_DIR/config/about/configuration.md" ] &&
    [ -f "$ROOT_DIR/config/about/license.md" ] &&
    cmp -s "$install_active" "$install_example" &&
    cmp -s "$map_active" "$map_example" &&
    cmp -s "$download_active" "$download_example" &&
    cmp -s "$about_active" "$about_example"
}

use_quickstart_layer_srids() {
  local mismatch=false
  local value

  for value in \
    "${LAYER_SRS_TERRITORY_LEVEL_1:-4674}" \
    "${LAYER_SRS_TERRITORY_LEVEL_2:-4674}" \
    "${LAYER_SRS_TERRITORY_LEVEL_3:-4674}" \
    "${LAYER_SRS_AREA_OF_INTEREST:-4674}"
  do
    value="${value#EPSG:}"
    if [ "$value" != "4674" ]; then
      mismatch=true
      break
    fi
  done

  if [ "$mismatch" = "true" ]; then
    warn "Quickstart uses SRID 4674; .env LAYER_SRS_* values apply only in the real adopter flow."
  fi

  export LAYER_SRS_TERRITORY_LEVEL_1="EPSG:4674"
  export LAYER_SRS_TERRITORY_LEVEL_2="EPSG:4674"
  export LAYER_SRS_TERRITORY_LEVEL_3="EPSG:4674"
  export LAYER_SRS_AREA_OF_INTEREST="EPSG:4674"
  ok "Quickstart layer SRS: L1=EPSG:4674 L2=EPSG:4674 L3=EPSG:4674 AOI=EPSG:4674"
}

apply_quickstart_seed() {
  local seed_dir="$ROOT_DIR/config/db/seed/quickstart"
  local dsp_user="${DSP_DB_USER:-dsp}"
  local dsp_db="${DSP_DB_NAME:-dsp-db}"
  local geo_user="${DSP_GEOSERVER_DB_USER:-dsp_geo}"
  local geo_db="${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}"

  for f in \
    "$seed_dir/01_territory_dsp.sql" \
    "$seed_dir/02_aoi_dsp.sql" \
    "$seed_dir/01_territory_exhibition.sql" \
    "$seed_dir/02_aoi_exhibition.sql"
  do
    if [ ! -f "$f" ]; then
      error "Quickstart seed file missing: $f"
      exit 1
    fi
  done

  info "Applying quickstart seed to dsp-db (demo data)..."
  docker compose --env-file .env exec -T dsp-db \
    psql -q -v ON_ERROR_STOP=1 -U "$dsp_user" -d "$dsp_db" \
    <"$seed_dir/01_territory_dsp.sql"
  docker compose --env-file .env exec -T dsp-db \
    psql -q -v ON_ERROR_STOP=1 -U "$dsp_user" -d "$dsp_db" \
    <"$seed_dir/02_aoi_dsp.sql"
  ok "dsp-db seeded"

  info "Applying quickstart seed to dsp-geoserver-db..."
  docker compose --env-file .env exec -T dsp-geoserver-db \
    psql -q -v ON_ERROR_STOP=1 -U "$geo_user" -d "$geo_db" \
    <"$seed_dir/01_territory_exhibition.sql"
  docker compose --env-file .env exec -T dsp-geoserver-db \
    psql -q -v ON_ERROR_STOP=1 -U "$geo_user" -d "$geo_db" \
    <"$seed_dir/02_aoi_exhibition.sql"
  ok "geoserver-db seeded"

  warn "Demonstration data only — heavily simplified Brazil geometries, not production."
}

start_geoserver_exhibition() {
  local mode="${1:-up}"
  local migration_config="${2:-}"

  # LAYER_SRS_* come from .env (defaults 4326); migration YAML path is unused for SRS today.
  info "Resolving layer SRS from .env (LAYER_SRS_*)..."
  export_layer_srids_from_migration_config "$migration_config"
  if [ -z "$migration_config" ] || [ ! -f "$migration_config" ]; then
    info "No migration YAML — using LAYER_SRS_* defaults (demonstration / no migration)."
  fi

  if [ "$mode" = "up" ]; then
    # mode=up: start without republishing layers (populate runs in setup).
    info "Building and starting GeoServer Exhibition..."
    docker compose --env-file .env up -d --build dsp-geoserver-exhibition
  else
    # mode=populate|start: setup builds the image; populate also publishes layers.
    info "Building and starting GeoServer Exhibition..."
    docker compose --env-file .env up -d --build dsp-geoserver-exhibition
  fi
  ok "GeoServer Exhibition container started"

  GEOSERVER_PUBLIC_URL="$(dsp_public_base_url)/geoserver-exhibition"
  GEOSERVER_ADMIN_USER="${DSP_GEOSERVER_ADMIN_USER:-admin}"
  GEOSERVER_ADMIN_PASSWORD="${DSP_GEOSERVER_ADMIN_PASSWORD:-geoserver}"

  info "Waiting for GeoServer Exhibition REST API (dsp-geoserver-exhibition) ..."
  if ! wait_for_geoserver "dsp-geoserver-exhibition" \
      "$GEOSERVER_ADMIN_USER" "$GEOSERVER_ADMIN_PASSWORD"; then
    error "GeoServer Exhibition did not become ready in time."
    docker compose --env-file .env logs --tail 80 dsp-geoserver-exhibition || true
    exit 1
  fi
  ok "GeoServer Exhibition is ready"

  if [ "$mode" = "populate" ]; then
    info "Publishing map layers on GeoServer Exhibition (workspace dsp)..."
    docker compose --env-file .env exec -T dsp-geoserver-exhibition /opt/populate_geoserver.sh
    ok "GeoServer Exhibition layers published"
  fi
}

start_geoserver_download() {
  local mode="${1:-up}"

  if [ "$mode" = "up" ]; then
    # mode=up: start without republishing layers (populate runs in setup).
    info "Building and starting GeoServer Download..."
    docker compose --env-file .env up -d --build dsp-geoserver-download
  else
    # mode=populate|start: setup builds the image; populate also publishes layers.
    info "Building and starting GeoServer Download..."
    docker compose --env-file .env up -d --build dsp-geoserver-download
  fi
  ok "GeoServer Download container started"

  GEOSERVER_DOWNLOAD_PUBLIC_URL="$(dsp_public_base_url)/geoserver-download"
  GEOSERVER_ADMIN_USER="${DSP_GEOSERVER_ADMIN_USER:-admin}"
  GEOSERVER_ADMIN_PASSWORD="${DSP_GEOSERVER_ADMIN_PASSWORD:-geoserver}"

  info "Waiting for GeoServer Download REST API (dsp-geoserver-download) ..."
  if ! wait_for_geoserver "dsp-geoserver-download" \
      "$GEOSERVER_ADMIN_USER" "$GEOSERVER_ADMIN_PASSWORD"; then
    error "GeoServer Download did not become ready in time."
    docker compose --env-file .env logs --tail 80 dsp-geoserver-download || true
    exit 1
  fi
  ok "GeoServer Download is ready"

  if [ "$mode" = "populate" ]; then
    info "Publishing download layers on GeoServer Download (workspace dsp)..."
    docker compose --env-file .env exec -T dsp-geoserver-download /opt/populate_geoserver.sh
    ok "GeoServer Download layers published"
  fi
}

start_gateway() {
  local base_url
  base_url="$(dsp_public_base_url)"
  local i

  # --no-deps: do not restart GeoServers/backend only because of gateway depends_on.
  info "Building and starting gateway (nginx)..."
  docker compose --env-file .env up -d --build --no-deps dsp-gateway
  ok "Gateway container started"

  info "Waiting for the gateway at ${base_url}/gateway/health ..."
  for i in $(seq 1 20); do
    if docker compose --env-file .env exec -T dsp-gateway \
        wget -q -O /dev/null http://localhost:8080/gateway/health >/dev/null 2>&1; then
      ok "Gateway is ready"
      if [ -n "${DSP_GATEWAY_CACHE_BYPASS-1}" ]; then
        info "nginx cache is off (DSP_GATEWAY_CACHE_BYPASS=${DSP_GATEWAY_CACHE_BYPASS-1}). Leave it empty in .env to enable."
      else
        info "nginx cache is on (TTL ${DSP_GATEWAY_CACHE_TTL:-10m}) for the GeoServer routes."
      fi
      return 0
    fi
    sleep 2
  done

  error "Gateway did not become ready in time."
  docker compose --env-file .env logs --tail 80 dsp-gateway || true
  exit 1
}

print_stack_urls() {
  local show_status="${1:-}"
  local base_url
  base_url="$(dsp_public_base_url)"
  local geoserver_url="${base_url}/geoserver-exhibition"
  local geoserver_download_url="${base_url}/geoserver-download"
  local http_host="${DSP_HTTP_HOST:-localhost}"
  local frontend_url="${base_url}${VITE_BASE_URL:-/dsp/}"
  local backend_url="${base_url}${DSP_BACKEND_CONTEXT_PATH:-/dsp-backend}"
  local svc_status=""

  load_stack_service_statuses

  if [ "$show_status" = "with-status" ]; then
    echo ""
    svc_status="$(stack_service_status dsp-gateway)"
    print_stack_url_line "Gateway" "$svc_status" "${base_url}/gateway/health"
    svc_status="$(stack_service_status dsp-frontend)"
    print_stack_url_line "Frontend" "$svc_status" "$frontend_url"
    svc_status="$(stack_service_status dsp-backend)"
    print_stack_url_line "Backend" "$svc_status" "$backend_url"
    print_stack_url_line "Installation config" "$svc_status" "${backend_url}/config/installation"
    print_stack_url_line "Map layers" "$svc_status" "${backend_url}/map/getLayers"
    svc_status="$(stack_service_status dsp-geoserver-exhibition)"
    print_stack_url_line "GeoServer Exhibition" "$svc_status" "${geoserver_url}/web/"
    print_stack_url_line "GeoServer WMS" "$svc_status" "${geoserver_url}/dsp/wms"
    svc_status="$(stack_service_status dsp-geoserver-download)"
    print_stack_url_line "GeoServer Download" "$svc_status" "${geoserver_download_url}/web/"
    print_stack_url_line "GeoServer Download WFS" "$svc_status" "${geoserver_download_url}/dsp/wfs"
    svc_status="$(stack_service_status dsp-db)"
    print_stack_url_line "DSP DB" "$svc_status" "${http_host}:${DSP_DB_HOST_PORT:-20654}  db=${DSP_DB_NAME:-dsp-db}  user=${DSP_DB_USER:-dsp}"
    svc_status="$(stack_service_status dsp-geoserver-db)"
    print_stack_url_line "GeoServer DB" "$svc_status" "${http_host}:${DSP_GEOSERVER_DB_HOST_PORT:-20656}  db=${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}  user=${DSP_GEOSERVER_DB_USER:-dsp_geo}"
    if is_persistent_migration_mode && is_stack_service_up dsp-job-migration; then
      svc_status="$(stack_service_status dsp-job-migration)"
      print_stack_url_line "Migration job (service)" "$svc_status" "mode=$(get_migration_execution_mode)${DSP_MIGRATION_CRON:+ cron=${DSP_MIGRATION_CRON}}${DSP_MIGRATION_SCHEDULED_AT:+ at=${DSP_MIGRATION_SCHEDULED_AT}}"
    fi
    return
  fi

  echo ""
  echo "Gateway:               ${base_url}/gateway/health"
  echo "Frontend:              ${frontend_url}"
  echo "Backend:               ${backend_url}"
  echo "Installation config:   ${backend_url}/config/installation"
  echo "Map layers:            ${backend_url}/map/getLayers"
  echo "GeoServer Exhibition:  ${geoserver_url}/web/"
  echo "GeoServer WMS:         ${geoserver_url}/dsp/wms"
  echo "GeoServer Download:    ${geoserver_download_url}/web/"
  echo "GeoServer Download WFS: ${geoserver_download_url}/dsp/wfs"
  echo "DSP DB:                ${http_host}:${DSP_DB_HOST_PORT:-20654}  db=${DSP_DB_NAME:-dsp-db}  user=${DSP_DB_USER:-dsp}"
  echo "GeoServer DB: ${http_host}:${DSP_GEOSERVER_DB_HOST_PORT:-20656}  db=${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db}  user=${DSP_GEOSERVER_DB_USER:-dsp_geo}"
  if is_persistent_migration_mode && is_stack_service_up dsp-job-migration; then
    echo "Migration job:         $(get_migration_execution_mode)${DSP_MIGRATION_CRON:+ cron=${DSP_MIGRATION_CRON}}${DSP_MIGRATION_SCHEDULED_AT:+ at=${DSP_MIGRATION_SCHEDULED_AT}}"
  fi
}

print_stack_usage_hints() {
  echo ""
  echo "Verify tables:"
  echo "  docker compose exec dsp-db psql -U ${DSP_DB_USER:-dsp} -d ${DSP_DB_NAME:-dsp-db} -c '\\dt dsp.*'"
  echo "  docker compose exec dsp-db psql -U ${DSP_DB_USER:-dsp} -d ${DSP_DB_NAME:-dsp-db} -c '\\dt data_migration.*'"
  echo "  docker compose exec dsp-db psql -U ${DSP_DB_USER:-dsp} -d ${DSP_DB_NAME:-dsp-db} -c '\\dt geo_file_generation.*'"
  echo "  docker compose exec dsp-geoserver-db psql -U ${DSP_GEOSERVER_DB_USER:-dsp_geo} -d ${DSP_GEOSERVER_DB_NAME:-dsp-geoserver-db} -c '\\dt dsp.*'"
  echo ""
  echo "Migrate / (re)populate data:"
  echo "  ./setup.sh"
  print_migration_resync_hints
  echo ""
  echo "Application only (backend, frontend, gateway): ./start.sh"
  echo "  Requires infrastructure running; if you ran compose down, use the compose command printed when ./start.sh fails."
  echo ""
  echo "Rebuild frontend only: docker compose up -d --build dsp-frontend"
  echo "Logs:       docker compose logs -f"
  echo "Stop:       docker compose --env-file .env --profile migration down"
  echo "Reset DBs:  docker compose --env-file .env --profile migration down -v && ./setup.sh"
  echo ""
}
