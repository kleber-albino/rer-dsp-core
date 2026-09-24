# rer-dsp-core

The **DSP (Data Sharing Platform)** is a web platform for sharing, exploring and publishing geospatial environmental data. **This repository** is the operational entry point: it prepares databases, GeoServer, the nginx gateway and adopter configuration, and orchestrates the other DSP modules via Docker Compose.

Full documentation: **[rer-dsp-docs](https://github.com/Rural-Environmental-Registry/rer-dsp-docs)**

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Git | Sibling repositories can be cloned automatically when missing |
| Docker 24+ with Compose v2 | |
| Python 3 | Required for `./config.sh` (real adopter only) |
| Bash | Native on Linux/macOS; on Windows use WSL2 |

On first run, `.env` is created automatically from `.env.example`.

## Clone

```bash
git clone https://github.com/Rural-Environmental-Registry/rer-dsp-core.git
cd rer-dsp-core
```

Missing sibling repos (`rer-dsp-backend`, `rer-dsp-frontend`, `rer-dsp-job-data-migration`, and for real installs `rer-dsp-job-geo-file-generation`) are offered for automatic clone by the scripts.

---

## Path 0 — One-command install (fastest demo)

For a quick demo using **published GHCR images** (no source build, no sibling repos):

```bash
curl -fsSL https://raw.githubusercontent.com/Rural-Environmental-Registry/dsp-core/main/install.sh | sh
# or, from a clone:
./install.sh
```

`install.sh` checks Docker/Compose/git/openssl, clones only `dsp-core` (~1 MB, for the
demo seed and config templates), generates `.env` with random passwords and a
`docker-compose.release.yml` that pulls the `dsp-*` images from GHCR, applies the
quickstart seed to both databases, and brings the full stack up in demo mode.

It auto-detects the container DNS resolver (Docker `127.0.0.11`, podman and others
differ) so the gateway resolves upstreams on any runtime.

When done: open `http://localhost:8026/dsp/`. Manage with
`docker compose -f docker-compose.release.yml {logs -f | down | down -v}`.

Environment overrides: `DSP_VERSION`, `DSP_DIR`, `DSP_PORT`, `DSP_REGISTRY`.

> Use `install.sh` for a demo from published images. Use `./config.sh` + `./setup.sh`
> (Path B) for a real adopter that migrates data from a source database.

---

## Path A — Quick demo (recommended first)

Built-in Brazil seed. No external database, no `./config.sh`.

**1. Prepare infrastructure and demo data**

```bash
./setup.sh
```

Choose **option 1 — Demonstration**. This starts the databases and GeoServers and loads the synthetic seed. It does **not** start the backend, frontend or gateway.

**2. Start the application**

```bash
./start.sh
```

Required after every `./setup.sh`. Brings up backend, frontend and gateway without re-running migration.

---

## Path B — Real adopter (your organization's data)

Requires a JDBC source database and the configuration wizard.

**1. Configure the adopter**

```bash
./config.sh
```

Wizard: source database, territorial hierarchy (L1/L2/L3), area of interest, optional layers, UI labels and KPIs. Does **not** set batch job schedules.

**2. Prepare infrastructure and run migration**

```bash
./setup.sh
```

Choose **option 2 — Real adopter**. Defines when and how the first migration runs and the download pre-generation schedule.

**3. Start the application**

```bash
./start.sh
```

Required after setup. Use `./start.sh` again on later runs when the stack is already configured.

Details: [Full installation](https://github.com/Rural-Environmental-Registry/rer-dsp-docs/blob/develop/docs/guides/full-installation.md) in rer-dsp-docs.

---

## Which script when

| Script | Use when |
|--------|----------|
| `./install.sh` | Fastest demo from published GHCR images. One command, no source build, no sibling repos. Generates `.env` + `docker-compose.release.yml`, seeds both databases, starts the full stack in demo mode. Env overrides: `DSP_VERSION`, `DSP_DIR`, `DSP_PORT`, `DSP_REGISTRY`. |
| `./config.sh` | Real adopter only — first-time setup or after editing `adopter-config.yaml`. Regenerates files under `config/` (data, mappings, layers, UI, SeaweedFS credentials in `.env`). Does **not** set batch job schedules. Rebuild with `./setup.sh` or `./start.sh` afterward. |
| `./setup.sh` | First install, switching demo ↔ real, or re-running migration / seed. Menu: **1** demo, **2** real adopter, **3** status/cleanup. For real adopter, defines **when** and **how** migration runs and the download pre-generation cron (`DSP_GEO_FILE_GENERATION_CRON` in `.env`). |
| `./start.sh` | After `./setup.sh`, or whenever you need backend + frontend + gateway with the current configuration. Starts **only** those three services — databases, GeoServers and jobs must already be running from `./setup.sh`. Does not ask for job schedules. If you ran `docker compose down` without `-v` and `./start.sh` fails, bring infrastructure back with the `docker compose` command it prints, then run `./start.sh` again. |

---

## Access (default port 8026)

All HTTP traffic goes through the gateway on a single port. After `./start.sh`, the frontend is available at **http://localhost:8026/dsp/** using the default `.env` configuration.

| Service | URL |
|---------|-----|
| Frontend | http://localhost:8026/dsp/ |
| Backend API (Swagger) | http://localhost:8026/dsp-backend/swagger-ui.html |
| GeoServer Exhibition | http://localhost:8026/geoserver-exhibition/web/ |
| GeoServer Download | http://localhost:8026/geoserver-download/web/ |

If port 8026 is in use, change `DSP_GATEWAY_HOST_PORT` and `DSP_PUBLIC_BASE_URL` in `.env`, run `./config.sh` to refresh WMS/WFS URLs (real adopter), then `./start.sh` again.

## License

[GNU General Public License v3.0](LICENSE)
