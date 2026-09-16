#!/bin/sh
# Geo file pre-generation job entrypoint — DSP_GEO_FILE_GENERATION_EXECUTION_MODE:
#   once                 — java -jar and exit (compose run without --rm; logs via docker logs)
#   continuous           — supercronic on DSP_GEO_FILE_GENERATION_CRON
#   wait-for-first-load  — poll DSP_FIRST_DATA_LOAD_MARKER, then run once and exit
set -e

MODE="${DSP_GEO_FILE_GENERATION_EXECUTION_MODE:-continuous}"
JAVA_BIN="java ${JAVA_OPTS:--XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0} -jar /app/app.jar"

if [ -n "${DSP_GEO_FILE_GENERATION_TZ:-}" ]; then
  TZ="$DSP_GEO_FILE_GENERATION_TZ"
fi
export TZ

valid_cron_5() {
  # shellcheck disable=SC2086
  set -- $1
  [ "$#" -eq 5 ]
}

case "$MODE" in
  once|"")
    # shellcheck disable=SC2086
    exec $JAVA_BIN
    ;;

  continuous)
    CRON="${DSP_GEO_FILE_GENERATION_CRON:-0 2 * * *}"
    if ! valid_cron_5 "$CRON"; then
      echo "[entrypoint] Invalid DSP_GEO_FILE_GENERATION_CRON (need 5 fields): '${CRON}'" >&2
      exit 1
    fi
    if ! command -v supercronic >/dev/null 2>&1; then
      echo "[entrypoint] supercronic not found in the image — rebuild dsp-job-geo-file-generation" >&2
      exit 1
    fi
    WRAPPER="/tmp/dsp-geo-file-run.sh"
    cat >"$WRAPPER" <<'EOF'
#!/bin/sh
JAVA_BIN="java ${JAVA_OPTS:--XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0} -jar /app/app.jar"
# A cycle can outlive its window on the first full generation; overlapping runs would
# publish the same keys twice and race on the territorial flags.
lock="/tmp/dsp-geo-file.lock"
exec 9>"$lock"
if ! flock -n 9; then
  echo "[entrypoint] Generation cycle skipped — another cycle is still running" >&2
  exit 0
fi
echo "[entrypoint] Starting geo file generation cycle..."
set +e
$JAVA_BIN
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "[entrypoint] Generation cycle finished successfully"
  exit 0
fi
# Exiting non-zero would make supercronic noisy for something the flags already retry.
echo "[entrypoint] Generation cycle failed (exit ${status})" >&2
exit 0
EOF
    chmod +x "$WRAPPER"
    echo "[entrypoint] continuous: supercronic cron='${CRON}' tz=${TZ}"
    echo "${CRON} ${WRAPPER}" > /tmp/dsp-geo-file.crontab
    exec supercronic /tmp/dsp-geo-file.crontab
    ;;

  wait-for-first-load)
    MARKER="${DSP_FIRST_DATA_LOAD_MARKER:-/dsp-batch-markers/first_data_load.ready}"
    echo "[entrypoint] wait-for-first-load: download pre-generation is paused until the migration job finishes."
    echo "[entrypoint] after migration, this container will build pre-generated files once, then exit."
    echo "[entrypoint] polling every 30s for marker: ${MARKER}"
    polls=0
    while [ ! -f "$MARKER" ]; do
      polls=$((polls + 1))
      if [ "$polls" -ge 10 ]; then
        echo "[entrypoint] still waiting — migration has not completed yet (no marker at ${MARKER})"
        polls=0
      fi
      sleep 30
    done
    echo "[entrypoint] migration complete (marker present) — starting one pre-generation cycle"
    # shellcheck disable=SC2086
    exec $JAVA_BIN
    ;;

  *)
    echo "[entrypoint] Invalid DSP_GEO_FILE_GENERATION_EXECUTION_MODE: '${MODE}' (once|continuous|wait-for-first-load)" >&2
    exit 1
    ;;
esac
