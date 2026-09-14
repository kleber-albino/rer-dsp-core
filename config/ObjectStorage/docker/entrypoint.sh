#!/bin/sh
# Starts SeaweedFS (weed mini), waits for the S3 API and ensures the bucket exists.
set -eu

if [ "$(id -u)" = "0" ]; then
  SEAWEED_UID="$(id -u seaweed)"
  SEAWEED_GID="$(id -g seaweed)"
  if [ -n "$SEAWEED_UID" ] && [ -n "$SEAWEED_GID" ]; then
    DATA_UID="$(stat -c '%u' /data 2>/dev/null || echo "")"
    if [ "$DATA_UID" != "$SEAWEED_UID" ]; then
      chown -R seaweed:seaweed /data 2>/dev/null || true
    fi
  fi
  exec su-exec seaweed "$0" "$@"
fi

ACCESS_KEY="${DSP_OBJECT_STORAGE_ACCESS_KEY:-dsp}"
SECRET_KEY="${DSP_OBJECT_STORAGE_SECRET_KEY:-dsp-secret}"
BUCKET="${DSP_OBJECT_STORAGE_BUCKET:-dsp-geo-files}"
REGION="${DSP_OBJECT_STORAGE_REGION:-us-east-1}"

export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_DEFAULT_REGION="$REGION"

/usr/bin/weed -logtostderr=true mini \
  -dir=/data \
  -ip.bind=0.0.0.0 \
  -master.volumeSizeLimitMB=30000 \
  -s3.config=/etc/seaweedfs/s3.json &

weed_pid=$!

ready=false
for _ in $(seq 1 90); do
  if aws --endpoint-url http://127.0.0.1:8333 s3 ls --region "$REGION" >/dev/null 2>&1; then
    ready=true
    break
  fi
  if ! kill -0 "$weed_pid" 2>/dev/null; then
    echo "SeaweedFS exited before the S3 API became ready" >&2
    wait "$weed_pid" || true
    exit 1
  fi
  sleep 1
done

if [ "$ready" != true ]; then
  echo "SeaweedFS S3 API did not become ready in time" >&2
  kill "$weed_pid" 2>/dev/null || true
  exit 1
fi

if ! aws --endpoint-url http://127.0.0.1:8333 s3api head-bucket \
  --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1; then
  aws --endpoint-url http://127.0.0.1:8333 s3 mb "s3://${BUCKET}" --region "$REGION"
fi

wait "$weed_pid"
