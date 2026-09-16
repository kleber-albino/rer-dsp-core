#!/bin/sh
# Idempotent marker written after the first successful data load and GeoServer publish.
set -e
MARKER="${DSP_FIRST_DATA_LOAD_MARKER:-/dsp-batch-markers/first_data_load.ready}"
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
echo "[mark-first-data-load] ready: ${MARKER}"
