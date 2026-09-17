# Gateway (DSP)

nginx reverse proxy — single entry point for the stack. Frontend, backend and both GeoServers
do not publish a host port; all external HTTP access goes through here.

## Image

- Base: `nginx:alpine`
- Build context: `rer-dsp-core/config/Gateway` (`dockerfile: docker/Dockerfile`)
- Compose service: `dsp-gateway`
- Templates are copied into the image at `/etc/nginx/templates/` (`nginx/default.conf.template`)

The template is processed by `envsubst` on container start. Only `DSP_*` variables are
substituted (`NGINX_ENVSUBST_FILTER=^DSP_`), to avoid conflicting with nginx's own variables
such as `$uri` and `$host`.

After changing a template, rebuild (`./start.sh` or `docker compose up -d --build dsp-gateway`).

## Defaults

| Item | Value |
| --- | --- |
| Host port | `8026` (`DSP_GATEWAY_HOST_PORT`) |
| Public base | `http://localhost:8026` (`DSP_PUBLIC_BASE_URL`) |
| Health | http://localhost:8026/gateway/health |

## Routes

| External route | Internal target | Cache |
| --- | --- | --- |
| `/` | redirects to `/dsp/` | — |
| `/dsp/` | `dsp-frontend:8080` | no |
| `/dsp-backend/` | `dsp-backend:8080` (same path, no rewrite) | no |
| `/geoserver-exhibition/<ws>/wms` and `/wfs` | `dsp-geoserver-exhibition:8080/geoserver/...` | yes |
| `/geoserver-exhibition/` (web UI, REST) | `dsp-geoserver-exhibition:8080/geoserver/` | no |
| `/geoserver-download/<ws>/wms` and `/wfs` | `dsp-geoserver-download:8080/geoserver/...` | yes |
| `/geoserver-download/` (web UI, REST) | `dsp-geoserver-download:8080/geoserver/` | no |
| `/gateway/health` | local nginx response | — |

The backend prefix follows `DSP_BACKEND_CONTEXT_PATH`. Because both GeoServers respond on
`/geoserver` internally, each gets its own external prefix and a `rewrite`. Each GeoServer's
`PROXY_BASE_URL` ensures GetCapabilities and web UI links use the correct public URL.

## Cache

The cache zone (`dsp_cache`, volume `dsp_gateway_cache`) is declared and applied on WMS/WFS
endpoints, but comes **disabled** by default: `DSP_GATEWAY_CACHE_BYPASS=1` in `.env`.

Cache covers only service endpoints, which have no session. GeoServer web UI and REST API are
excluded so admin login is not broken. Because GeoServer responds with
`Cache-Control: max-age=0, must-revalidate` on every request, the gateway ignores that header on
those routes — otherwise nothing would be stored.

To enable, leave the variable empty and recreate the container:

```bash
# .env
DSP_GATEWAY_CACHE_BYPASS=
DSP_GATEWAY_CACHE_TTL=10m

docker compose --env-file .env up -d --force-recreate dsp-gateway
```

The `X-Cache-Status` header (`HIT`, `MISS`, `BYPASS`) is sent on every GeoServer response and
helps verify behaviour:

```bash
curl -sI "http://localhost:8026/geoserver-exhibition/dsp/wms?service=WMS&request=GetCapabilities" | grep -i x-cache
```

To clear the cache: `docker compose --env-file .env down` and remove volume `dsp_gateway_cache`.

## Notes

- Upstreams are resolved at runtime via Docker DNS (`resolver 127.0.0.11` + variable name). This
  lets the gateway start even when a service is down, returning `502` instead of failing on boot —
  required for `./setup.sh` demo mode, which does not start backend or frontend.
- There is no TLS termination here. Exposing via HTTPS remains the adopter's responsibility; this
  is the natural place to do it.
