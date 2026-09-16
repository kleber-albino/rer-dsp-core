#!/usr/bin/env bash
# Cron helpers for the migration schedule (5-field Unix cron).
# Sourced by common.sh. No side effects.

dsp_normalize_hhmm() {
  local raw="${1:-}"
  local hour minute
  if [[ "$raw" =~ ^([0-9]{1,2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="00"
  elif [[ "$raw" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  if [ "$hour" -gt 23 ] || [ "$minute" -gt 59 ]; then
    return 1
  fi
  printf '%02d:%02d\n' "$hour" "$minute"
}

dsp_hhmm_hour() {
  printf '%s\n' "${1%%:*}"
}

dsp_hhmm_minute() {
  printf '%s\n' "${1##*:}"
}

# Hour steps that close a 24h cycle in crontab.
dsp_valid_hour_step() {
  case "$1" in
    1|2|3|4|6|8|12|24) return 0 ;;
    *) return 1 ;;
  esac
}

dsp_build_daily_cron() {
  local hhmm="$1"
  local minute hour
  minute=$((10#$(dsp_hhmm_minute "$hhmm")))
  hour=$((10#$(dsp_hhmm_hour "$hhmm")))
  printf '%s %s * * *\n' "$minute" "$hour"
}

# Every N hours at minute 0, aligned to midnight (0 */N * * *).
dsp_build_hourly_cron() {
  local step="$1"
  if ! dsp_valid_hour_step "$step"; then
    return 1
  fi
  printf '0 */%s * * *\n' "$step"
}

dsp_valid_minute_step() {
  [[ "${1:-}" =~ ^[1-9][0-9]?$ ]] || return 1
  [ "$1" -ge 1 ] && [ "$1" -le 59 ]
}

# Every N minutes (*/N * * * *). N is 1–59.
dsp_build_minute_cron() {
  local step="$1"
  if ! dsp_valid_minute_step "$step"; then
    return 1
  fi
  printf '*/%s * * * *\n' "$step"
}

dsp_valid_cron_5() {
  local fields
  read -r -a fields <<< "${1:-}"
  [ "${#fields[@]}" -eq 5 ]
}

# Trim and validate a custom 5-field cron line; prints normalized cron on stdout.
dsp_normalize_cron_5() {
  local raw="${1:-}"
  local fields
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  read -r -a fields <<< "$raw"
  if [ "${#fields[@]}" -ne 5 ]; then
    return 1
  fi
  local field
  for field in "${fields[@]}"; do
    if [ -z "$field" ]; then
      return 1
    fi
  done
  printf '%s %s %s %s %s\n' "${fields[0]}" "${fields[1]}" "${fields[2]}" "${fields[3]}" "${fields[4]}"
}

dsp_valid_iso_date() {
  [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

dsp_quote_dotenv_value() {
  local value="$1"
  local escaped
  escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '"%s"\n' "$escaped"
}

# 0 if date+time in TZ is still in the future. GNU date.
dsp_datetime_is_future() {
  local date_ymd="$1"
  local hhmm="$2"
  local tz="${3:-$DSP_MIGRATION_TZ}"
  local target now
  target="$(TZ="$tz" date -d "${date_ymd} ${hhmm}:00" +%s)" || return 1
  now="$(TZ="$tz" date +%s)"
  [ "$target" -gt "$now" ]
}
