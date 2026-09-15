# Object storage (SeaweedFS) — Docker

`dsp-object-storage` provides an S3-compatible API via [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
(`weed mini`) for pre-generated territorial download files.

## When it starts

| Installation | Profile `object-storage` |
|--------------|--------------------------|
| Brazil demo (`./setup.sh` option 1) | **No** — downloads use WFS only |
| Real adopter | **Yes** — required together with `dsp-job-geo-file-generation` |

## Internal endpoint

- Docker network URL: `http://dsp-object-storage:8333`
- Bucket: `dsp-geo-files` (created on startup if missing)
- Default credentials: `dsp` / `dsp-secret` (in `s3.json` baked into the image and in `.env`)

## Capacity

- `weed mini` auto-configures the per-volume size limit and volume count from free disk space (no extra flags in the DSP image).
- Total capacity depends on free space on the Docker volume `dsp_object_storage_data`.

## Host port

Optional for diagnostics (`aws s3 --endpoint-url http://localhost:8333`):

```bash
DSP_OBJECT_STORAGE_HOST_PORT=8333   # default in .env.example
```

## Backup

Back up the `dsp_object_storage_data` volume (or the equivalent host directory). The DSP does not keep object versions in the bucket — each regeneration overwrites the object.

## Commands

```bash
# Start storage only (real adopter)
docker compose --env-file .env --profile object-storage up -d --build dsp-object-storage

# List bucket
AWS_ACCESS_KEY_ID=dsp AWS_SECRET_ACCESS_KEY=dsp-secret \
  aws --endpoint-url http://localhost:8333 s3 ls s3://dsp-geo-files/
```
