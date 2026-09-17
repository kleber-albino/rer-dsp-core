# Job data-migration — Docker

The image is built from the sibling repository Dockerfile:

`../rer-dsp-job-data-migration/Dockerfile` (path configurable via `DSP_JOB_MIGRATION_PATH`).

The `dsp-job-migration` service uses Compose profile `migration`. Batch metadata lives in `dsp-db` schema `data_migration` (exclusive to this job; the geo-file job uses `geo_file_generation`).

## Entrypoint

[`entrypoint.sh`](entrypoint.sh) is copied into the image as `/migration-entrypoint.sh`:

| `DSP_MIGRATION_EXECUTION_MODE` | Behaviour |
| --- | --- |
| `once` (default) | Runs `java -jar /app/app.jar` and exits — `./setup.sh` uses `compose up` on `dsp-job-migration` (same container name as scheduled modes; stays **Exited**; `docker logs dsp-job-migration`) |
| `continuous` | If `DSP_MIGRATION_SCHEDULED_AT` is set (Schedule for later), waits, runs one first load, publishes both GeoServers, then `supercronic` on `DSP_MIGRATION_CRON`. Run now + Continuous has no wait (first load and populate already ran in setup). |
| `scheduled-once` | Waits until `DSP_MIGRATION_SCHEDULED_AT`, runs once, publishes both GeoServers, exits (Schedule for later + One-time) |

| Variable | Notes |
| --- | --- |
| `DSP_MIGRATION_CRON` | 5-field cron (e.g. `0 22 * * *`) written by `./setup.sh` Job 1/2 (every day / N hours / N minutes). `continuous` only. |
| `DSP_MIGRATION_SCHEDULED_AT` | `YYYY-MM-DD HH:MM:SS`. Required for `scheduled-once`; optional first load for `continuous` (Schedule for later). |
| `DSP_MIGRATION_TZ` | IANA timezone for wall clock. Read from `.env` (see `.env.example`). |

The JAR stays one-shot. Overlap: `flock` in the supercronic wrapper. A failed JAR does not stop the continuous container.

Scheduled first load: [`publish_geoservers.sh`](publish_geoservers.sh) runs the same `populate_geoserver.sh` used by `./setup.sh`, against Exhibition and Download on the Docker network, after the first successful scheduled load.

## Commands

**One-time now** (`once`):

```bash
docker rm -f dsp-job-migration
DSP_MIGRATION_EXECUTION_MODE=once docker compose --env-file .env --profile migration up --build \
  --abort-on-container-exit --exit-code-from dsp-job-migration \
  dsp-job-migration
```

`./setup.sh` (Run now) runs the same `compose up` flow on container **`dsp-job-migration`** (inside the `rer-dsp-core` stack). Logs: `docker logs dsp-job-migration`.

**Scheduled service** (`continuous` or `scheduled-once`):

```bash
docker compose --env-file .env --profile migration up -d --build dsp-job-migration
```

Optional extra one-shot on top of the schedule:

```bash
docker rm -f dsp-job-migration
DSP_MIGRATION_EXECUTION_MODE=once docker compose --env-file .env --profile migration up --build \
  --abort-on-container-exit --exit-code-from dsp-job-migration \
  dsp-job-migration
```

The image copies `application.yaml`, `mapLayersConfig.json`, the entrypoint, `publish_geoservers.sh`,
`mark_first_data_load_ready.sh` and `populate_geoserver.sh` at build time (from `dsp_config` build context).

## Related batch job

Geo file pre-generation (`dsp-job-geo-file-generation`, profile `object-storage`) uses the same
schedule menu in `./setup.sh` (Job 2/2). See [`../Job-Geo-File-Generation/docker/README.md`](../../Job-Geo-File-Generation/docker/README.md).
