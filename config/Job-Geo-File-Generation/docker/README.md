# Job geo-file-generation — Docker

The image is built from the sibling repository Dockerfile:

`../rer-dsp-job-geo-file-generation/Dockerfile` (path configurable via `DSP_JOB_GEO_FILE_GENERATION_PATH`).

The `dsp-job-geo-file-generation` service uses Compose profile `object-storage` (adopter real installs only). It publishes the
territorial download files (levels 2 and 3) to the bundled SeaweedFS (`dsp-object-storage`) so that `/downloads/file`
does not have to query the WFS. Batch metadata lives in `dsp-db` schema `geo_file_generation`
(tables `BATCH_*` exclusive to this job). The migration job keeps its own schema
`data_migration`.

The bucket `dsp-geo-files` is created by `dsp-object-storage` on startup if missing. Without a healthy object storage the job logs the error,
publishes nothing and the JVM exits with success (so the stack keeps running and the
territorial flags stay on for the next cycle). The Spring Batch metadata in schema
`geo_file_generation` records `exit_code = OBJECT_STORAGE_NOT_READY` on
`batch_job_execution` — query that column to see cycles where generation was skipped due
to storage, distinct from `COMPLETED` (all files published) or `PUBLISH_*` (partial failures).

Brazil demo (`./setup.sh` option 1) does **not** start this service nor `dsp-object-storage`.

## Entrypoint

[`entrypoint.sh`](entrypoint.sh) is copied into the image as `/geo-file-entrypoint.sh`:

| `DSP_GEO_FILE_GENERATION_EXECUTION_MODE` | Behaviour |
| --- | --- |
| `continuous` (default) | `supercronic` on `DSP_GEO_FILE_GENERATION_CRON` |
| `once` | Runs `java -jar /app/app.jar` and exits — used by `compose run` (container stays **Exited**; `docker logs <name>`) |
| `wait-for-first-load` | Polls `DSP_FIRST_DATA_LOAD_MARKER`, then runs once and exits (deferred static load) |

| Variable | Notes |
| --- | --- |
| `DSP_GEO_FILE_GENERATION_CRON` | 5-field cron written to `.env` by `./setup.sh` (Job 2/2 — same every day / N hours / N minutes menu as data migration). Pick a window **after** migration (`DSP_MIGRATION_CRON` when continuous), because migration raises the flags. |
| `DSP_GEO_FILE_GENERATION_TZ` | IANA timezone for wall clock. Defaults to `DSP_MIGRATION_TZ`. |

The JAR stays one-shot. Overlap: `flock` in the supercronic wrapper — the first full
generation can outlive its window, and two cycles would publish the same keys and race on
the flags. A failed JAR does not stop the continuous container.

## Configuration

`./config.sh` writes the SeaweedFS endpoint, bucket, region, credentials and path-style to
`application/application.yaml` and `DSP_OBJECT_STORAGE_*` in `.env`.

`DSP_GEO_FILE_GENERATION_CRON` is set in `./setup.sh` (living source or deferred + re-sync), not in `./config.sh`.
`DSP_GEO_FILE_GENERATION_RECURRING=false` skips the continuous geo container (one-time or wait-for-first-load).
Reapplying `./config.sh` does not change migration or pre-generation crons in `.env`.

With **Run now** during setup, after GeoServer populate, `./setup.sh` runs one `once` generation
(`compose run`, container retained) before starting the continuous service.

The backend reads the same bucket (`DSP_OBJECT_STORAGE_*` in `.env`) to serve the file and
to report `lastFileGenerated` from the object metadata `generated-at`.

## Commands

**Scheduled service** (`continuous`):

```bash
docker compose --env-file .env --profile object-storage up -d --build dsp-job-geo-file-generation
```

**One-time now** (`once`):

```bash
docker compose --env-file .env --profile object-storage run --build \
  -e DSP_GEO_FILE_GENERATION_EXECUTION_MODE=once dsp-job-geo-file-generation
```

One-off containers are not removed automatically; inspect logs with `docker logs` on the `…_run_<id>` name from `docker ps -a`. Scheduled/wait modes use fixed names `dsp-job-geo-file-generation`.

The image copies `application.yaml`, `downloadThemesConfig.json` and the entrypoint at build time.
