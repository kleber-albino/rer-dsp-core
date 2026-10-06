# GeoServer Exhibition (DSP)

Docker image for map WMS/WFS navigation used by the DSP UI (`mapLayersConfig.json`).

Downloads (CSV/WFS export) use a separate GeoServer — see `config/GeoserverDownload/docker`.

## Image

- Base: `docker.osgeo.org/geoserver:3.0.0`
- Build context: `rer-dsp-core/config` (`dockerfile: GeoserverExhibition/docker/Dockerfile`)
- Compose service: `dsp-geoserver-exhibition`
- `mapLayersConfig.json` lives in `config/GeoserverExhibition/map/` (updated by dsp-core `./config.sh`) and is baked into the image at `/config/mapLayersConfig.json` via `select-runtime-config.sh`

## Defaults

Does not publish a host port: external access goes through the gateway (`config/Gateway/docker`).

| Item | Value |
| --- | --- |
| Gateway prefix | `/geoserver-exhibition` |
| UI | http://localhost:8026/geoserver-exhibition/web/ |
| WMS | http://localhost:8026/geoserver-exhibition/dsp/wms |
| Admin | `admin` / `geoserver` |

The external prefix differs from the internal one (`/geoserver`), so `PROXY_BASE_URL` — derived from
`DSP_PUBLIC_BASE_URL` — is required: without it, GetCapabilities and web UI links would point at
the wrong path.

## Published layers (fixed)

| PostGIS table | WMS layer | Job `layer-name` |
| --- | --- | --- |
| `dsp.territory_level_1` | `dsp:territory-level-1` | `territory-level-1` |
| `dsp.territory_level_2` | `dsp:territory-level-2` | `territory-level-2` |
| `dsp.territory_level_3` | `dsp:territory-level-3` | `territory-level-3` |
| `dsp.area_of_interest` | `dsp:area-of-interest` | `area-of-interest` |

`populate_geoserver.sh` does **not** create tables. It only publishes FeatureTypes for tables created by `config/db/dsp-db` init SQL (data from the migration job).

`mapLayersConfig.json` must keep these four `layers` ids — `./start.sh` validates them.

Layer colors come from `mapLayersConfig.json` in the image (`style.color` / `style.fillColor`). Populate creates/updates one SLD per layer (`dsp_territory_level_*`, `dsp_area_of_interest`).

## Manual populate

```bash
docker compose up -d --build dsp-geoserver-exhibition
docker compose exec dsp-geoserver-exhibition /opt/populate_geoserver.sh
```
