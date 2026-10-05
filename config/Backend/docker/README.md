# Backend Docker

The image is built from the sibling repository Dockerfile:

`../rer-dsp-backend/Dockerfile` (path configurable via `DSP_BACKEND_PATH`).

Compose injects `./config` at build time (`additional_contexts: dsp_config`). The image copies into `/config`:

- `config/installation/installation-config.json` → `/config/installation-config.json`
- `config/map/mapLayersConfig.json` → `/config/mapLayersConfig.json`
- `config/downloads/downloadThemesConfig.json` → `/config/downloadThemesConfig.json`
- `config/about/about-config.json` and only the Markdown files listed in its `tabs[].file` → `/config/about/` (other `.md` files in the host folder are not copied)

If the active file is not on the host yet, the build uses the versioned `.example`.

- Env `DSP_INSTALLATION_CONFIG_FILE=file:/config/installation-config.json`
- Env `DSP_MAP_LAYERS_FILE=file:/config/mapLayersConfig.json`
- Env `DSP_DOWNLOAD_THEMES_FILE=file:/config/downloadThemesConfig.json`
- Env `DSP_ABOUT_CONFIG_FILE=file:/config/about/about-config.json`
- Env `DSP_ABOUT_CONTENT_DIR=file:/config/about/`
- Env `DSP_GEOSERVER_WFS_BASE_URL` (WFS URL of GeoServer Download on the Docker network, e.g. `http://dsp-geoserver-download:8080/geoserver/dsp/wfs`)
- Datasource pointing at the `dsp-db` service

After `./config.sh`, run `./setup.sh` or `./start.sh` to rebuild the image with the generated config.
