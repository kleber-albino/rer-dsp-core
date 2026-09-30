# DSP CI — Docker image build & publish

Centralized CI for the whole DSP stack (**approach A**): `rer-dsp-core` is the build
orchestrator. `.github/workflows/docker-build.yaml` checks out the sibling repos,
builds every image with `docker compose build` (which resolves the
`additional_contexts: dsp_config` used by the backend/job Dockerfiles and the
`network:host` GeoServer builds), then retags the local `dsp-*:local` images and
pushes them to GHCR.

## Images published (ghcr.io/rural-environmental-registry/)
`dsp-db`, `dsp-geoserver-db`, `dsp-backend`, `dsp-frontend`, `dsp-gateway`,
`dsp-geoserver-exhibition`, `dsp-geoserver-download`, `dsp-job-migration`.

## Tags (by branch, from `VERSION`)
- `release/dev` → `<version>-dev`
- `release/prd` → `<version>-prd`
- `main` → `<version>` + `latest`
- PR → builds only (no push), for validation

(The DSP repos have no `release/qa` branch — only dev and prd.)

## REQUIRED SETUP — sibling-repo checkout token

The workflow checks out three **private** sibling repos (`dsp-backend`,
`dsp-frontend`, `dsp-job-data-migration`) into the short folders next to `core`
(`backend`, `frontend`, `job-data-migration`). The default `GITHUB_TOKEN` is
scoped to **this repo only** and cannot read them. You MUST provide a token with
`contents:read` on those repos as the secret **`DSP_SIBLING_REPOS_TOKEN`**:

- Recommended: a **GitHub App** (org-level, `contents:read` on the 4 DSP repos) —
  most secure and rotatable. Generate an ephemeral token at runtime.
- Acceptable: a **fine-grained PAT** with `contents:read` on the 3 sibling repos,
  stored as the org/repo secret `DSP_SIBLING_REPOS_TOKEN`.

Without this secret the sibling checkouts fail (no silent fallback — by design).

## Notes
- GeoServer builds need `network:host` → the buildx builder is created with
  `--allow-insecure-entitlement network.host`.
- `COMPOSE_BAKE=true` routes the compose build through buildx (better layering).
- `.env` is created from `.env.example` (build-time defaults only, no real secrets).
- Build is heavy (Java + 2 GeoServer images); expect long first runs.
