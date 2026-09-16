#!/bin/sh
# Migration job entrypoint — DSP_MIGRATION_EXECUTION_MODE:
#   once            — java -jar and exit (compose run without --rm; logs via docker logs)
#   continuous      — optional wait until DSP_MIGRATION_SCHEDULED_AT (Schedule for later),
#                     one first load, then supercronic on DSP_MIGRATION_CRON
#   scheduled-once  — wait until DSP_MIGRATION_SCHEDULED_AT, run once, exit
set -e

MODE="${DSP_MIGRATION_EXECUTION_MODE:-once}"
JAVA_BIN="java ${JAVA_OPTS:--XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0} -jar /app/app.jar"
PUBLISH_GEOSERVERS="/publish-geoservers.sh"

if [ -n "${DSP_MIGRATION_TZ:-}" ]; then
  TZ="$DSP_MIGRATION_TZ"
fi
export TZ

valid_cron_5() {
  # shellcheck disable=SC2086
  set -- $1
  [ "$#" -eq 5 ]
}

run_jar() {
  echo "[entrypoint] Starting migration cycle (tz=${TZ})..."
  set +e
  # shellcheck disable=SC2086
  $JAVA_BIN
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "[entrypoint] Migration cycle finished successfully"
  else
    echo "[entrypoint] Migration cycle failed (exit ${status})" >&2
  fi
  return "$status"
}

publish_geoservers_after_first_load() {
  if [ ! -f "$PUBLISH_GEOSERVERS" ]; then
    echo "[entrypoint] ${PUBLISH_GEOSERVERS} not found — skip GeoServer populate" >&2
    return 0
  fi
  sh "$PUBLISH_GEOSERVERS"
}

# Empty DSP_MIGRATION_SCHEDULED_AT: no wait (Run now + Continuous).
wait_until_scheduled() {
  WHEN="${DSP_MIGRATION_SCHEDULED_AT:-}"
  if [ -z "$WHEN" ]; then
    return 0
  fi
  target=$(date -d "$WHEN" +%s) || {
    echo "[entrypoint] Invalid DSP_MIGRATION_SCHEDULED_AT: '${WHEN}'" >&2
    exit 1
  }
  now=$(date +%s)
  if [ "$target" -gt "$now" ]; then
    wait_s=$((target - now))
    echo "[entrypoint] waiting until ${WHEN} (${wait_s}s, tz=${TZ})"
    sleep "$wait_s"
  else
    echo "[entrypoint] ${WHEN} is in the past — continuing"
  fi
}

run_deferred_first_load() {
  marker="/tmp/dsp-migration-deferred-initial.done"
  if [ -z "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
    return 0
  fi
  if [ -f "$marker" ]; then
    echo "[entrypoint] deferred first load already done — skipping"
    return 0
  fi
  wait_until_scheduled
  if ! run_jar; then
    echo "[entrypoint] deferred first load failed — not publishing GeoServer layers" >&2
    return 1
  fi
  touch "$marker"
  publish_geoservers_after_first_load || true
}

case "$MODE" in
  once|"")
    # shellcheck disable=SC2086
    exec $JAVA_BIN
    ;;

  scheduled-once)
    if [ -z "${DSP_MIGRATION_SCHEDULED_AT:-}" ]; then
      echo "[entrypoint] DSP_MIGRATION_SCHEDULED_AT is required for scheduled-once" >&2
      exit 1
    fi
    wait_until_scheduled
    if ! run_jar; then
      exit 1
    fi
    publish_geoservers_after_first_load
    exit $?
    ;;

  continuous)
    CRON="${DSP_MIGRATION_CRON:-0 22 * * *}"
    if ! valid_cron_5 "$CRON"; then
      echo "[entrypoint] Invalid DSP_MIGRATION_CRON (need 5 fields): '${CRON}'" >&2
      exit 1
    fi
    if ! command -v supercronic >/dev/null 2>&1; then
      echo "[entrypoint] supercronic not found in the image — rebuild dsp-job-migration" >&2
      exit 1
    fi
    run_deferred_first_load || true
    WRAPPER="/tmp/dsp-migration-run.sh"
    cat >"$WRAPPER" <<'EOF'
#!/bin/sh
JAVA_BIN="java ${JAVA_OPTS:--XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0} -jar /app/app.jar"
lock="/tmp/dsp-migration-sync.lock"
exec 9>"$lock"
if ! flock -n 9; then
  echo "[entrypoint] Sync cycle skipped — another sync is still running" >&2
  exit 0
fi
echo "[entrypoint] Starting migration cycle..."
set +e
$JAVA_BIN
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "[entrypoint] Migration cycle finished successfully"
  if [ -n "${DSP_MIGRATION_SCHEDULED_AT:-}" ] && [ -f /publish-geoservers.sh ]; then
    sh /publish-geoservers.sh || true
  fi
  exit 0
fi
echo "[entrypoint] Migration cycle failed (exit ${status})" >&2
exit 0
EOF
    chmod +x "$WRAPPER"
    echo "[entrypoint] continuous: supercronic cron='${CRON}' tz=${TZ}"
    echo "${CRON} ${WRAPPER}" > /tmp/dsp-migration.crontab
    exec supercronic /tmp/dsp-migration.crontab
    ;;

  *)
    echo "[entrypoint] Invalid DSP_MIGRATION_EXECUTION_MODE: '${MODE}' (once|continuous|scheduled-once)" >&2
    exit 1
    ;;
esac
