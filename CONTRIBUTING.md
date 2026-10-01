# Contributing to rer-dsp-core

Thank you for your interest in contributing to dsp-core.

This repository is the operational entry point of the **DSP (Data Sharing
Platform)**, part of the Rural Environmental Registry (RER). It prepares
databases, GeoServer, the nginx gateway, object storage, and adopter
configuration, and orchestrates the other modules with Docker Compose.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

Full project documentation lives in
[dsp-docs](https://github.com/Rural-Environmental-Registry/dsp-docs).
The guide below covers this module only.

---

## What belongs here

Changes to stack orchestration belong in this repository:

- `./config.sh`, `./setup.sh`, and `./start.sh`
- Infrastructure under `config/` (databases, GeoServers, gateway, object storage, job images)


`./config.sh` writes the adopter file and regenerates operational files. Do not
edit these by hand:

- `config/installation/installation-config.json`
- `config/map/mapLayersConfig.json`
- `config/downloads/downloadThemesConfig.json`
- `config/Job-Data-Migration/application/application.yaml`
- `config/Job-Geo-File-Generation/application/application.yaml`

Change `config/adopter/adopter-config.yaml` (wizard or editor) and reapply
`./config.sh`. The wizard does not set batch job schedules. Cron values in
`.env` are defined by `./setup.sh`.

Application code belongs in its own repository:

| Change | Repository |
|--------|------------|
| Architecture, installation, and platform guides | [dsp-docs](https://github.com/Rural-Environmental-Registry/dsp-docs) |
| REST API | [dsp-backend](https://github.com/Rural-Environmental-Registry/dsp-backend) |
| Web interface | [dsp-frontend](https://github.com/Rural-Environmental-Registry/dsp-frontend) |
| Source-database migration | [dsp-job-data-migration](https://github.com/Rural-Environmental-Registry/dsp-job-data-migration) |
| Pre-generated download files | [dsp-job-geo-file-generation](https://github.com/Rural-Environmental-Registry/dsp-job-geo-file-generation) |

Issues for every DSP module are opened in this repository.

---

## How to contribute

### 1. Bugs and features

1. Open an issue describing the problem or the change:
   https://github.com/Rural-Environmental-Registry/dsp-core/issues
2. Fork the repository
3. Create a branch from `develop`: `git checkout -b feat/short-description`
4. Make the change
5. Run the shell checks that cover the files you touched (see below)
6. Commit with a clear message
7. Open a pull request against `develop`

### 2. Script and Compose changes

| Area | Where |
|------|--------|
| Adopter wizard and generated files | `./config.sh`, `scripts/apply_adopter_config.py` |
| First install, demo seed, migration schedule | `./setup.sh` |
| Backend, frontend, and gateway startup | `./start.sh` |
| Services, profiles, and ports | `docker-compose.yml` |


### 3. Documentation of this module

Keep `README.md` limited to this module: purpose, prerequisites, and which
script to run. Platform-wide guides (architecture, quick start, full
installation) go to
[dsp-docs](https://github.com/Rural-Environmental-Registry/dsp-docs), in both
`docs/pt-br/` and `docs/en/`.

---

## Local setup

| Requirement | Use |
|-------------|-----|
| Git | Clone this repository and missing sibling modules |
| Docker 24+ with Compose v2 | Start databases, GeoServers, gateway, and the other modules |
| Python 3 | `./config.sh` for a real adopter |
| Bash | The operational scripts. On Windows, use WSL2 |

Demo from published images:

Real adopter:

```bash
./config.sh
./setup.sh
./start.sh
```

The frontend is at http://localhost:8026/dsp/ with the default `.env`.

## Code standards

- Operational scripts are Bash. Keep them runnable on Linux and macOS
- The adopter wizard is Python 3
- Do not put adopter-specific table names, labels, or credentials in Compose or in the scripts. They come from `adopter-config.yaml` and `.env`
- Generated files under `config/` are copied into images at build. After `./config.sh`, containers pick them up through `./setup.sh` or `./start.sh`
- `./start.sh` starts only backend, frontend, and gateway. Databases, GeoServers, and jobs come from `./setup.sh`
- The object-storage profile (SeaweedFS and the geo-file job) is for a real adopter. The Brazil demo does not start it
- Do not commit `.env` or generated passwords

---

## Review process

1. **Checks** — the shell scripts in `tests/` that cover your change must pass
2. **Peer review** — at least one maintainer reviews the pull request
3. **Merge** — approved pull requests are merged into `develop`

---

## Commit message format

Use conventional commits:

```
feat: ask for the geo-file cron only in setup.sh
fix: keep generated JSON out of Compose volume binds
docs: describe install.sh in the module README
```

**Types:**

- `feat:` — new behavior
- `fix:` — bug fix
- `docs:` — documentation only
- `refactor:` — internal change with the same behavior

---

## Getting help

- **Questions or bugs:** open an issue in this repository:
  https://github.com/Rural-Environmental-Registry/dsp-core/issues
- **Stuck on a pull request:** ask in the pull request
- **Platform behavior:** see
  [dsp-docs](https://github.com/Rural-Environmental-Registry/dsp-docs)

---

## License

By contributing, you agree that your contributions will be licensed under the
[GNU General Public License v3.0](LICENSE).

---

**Thank you for helping improve dsp-core.**
