# DSP — Runbook "Arrumar a Casa" (CI/CD + externalização de config)

> Objetivo: tornar as imagens DSP **portáveis** — mesma imagem roda em docker-compose (dev local)
> e K8s (dev/qa/prd) via **config injetada em runtime** (env + ConfigMap), sem baked nem workaround.
> Contexto: o deploy K8s de 23/set subiu com **workarounds em runtime** (command wrapper no gateway).
> Isto é dívida. Este runbook elimina a dívida. Atuação em **branch `develop`** (nossa/DTP).

## Mapa atual (auditoria 23/set)

### Arquitetura de build
- **CI centralizado no `dsp-core`** (`.github/workflows/docker-build.yaml`, "approach A"): o core faz
  checkout dos repos irmãos, `docker compose build` (config operacional em cada repo;
  GeoServer `network:host`), retag e push das 8 imagens ao GHCR. Irmãos **não têm CI próprio**.
- Imagens: dsp-db, dsp-geoserver-db, dsp-backend, dsp-frontend, dsp-gateway,
  dsp-geoserver-exhibition, dsp-geoserver-download, dsp-job-migration.
- Tags por branch: `release/dev`→`X-dev`, `release/prd`→`X-prd`, `main`→`X`+`latest`.

### Estado por componente (baked vs runtime)
| Componente | Config runtime OK? | Problema |
|-----------|--------------------|----------|
| dsp-backend | ✅ BOM | Spring lê `DSP_*`/`SPRING_*` de env. Configs JSON baked em /config via `select-runtime-config.sh` (aceitável — são catálogos, não ambiente). Probe TCP (sem actuator). |
| dsp-frontend | ✅ BOM | Dockerfile remove default.conf, roda USER nginx, cria cache dirs. VITE_* são build-arg (baked) MAS gera `env.json` runtime (`urlBackend`) — parametrizável. |
| dsp-db / geoserver-db | ✅ BOM | PostGIS, env POSTGRES_* padrão. |
| **dsp-gateway** | ❌ **RUIM** | **3 bugs** (ver abaixo). É a origem de todo o workaround. |
| geoservers | ⚠️ médio | PROXY_BASE_URL importante p/ links WMS/WFS — confirmar se vem de env no build ou runtime. |

## Problemas a corrigir (por prioridade)

### P0 — CI quebrado pela renomeação (URGENTE)
`dsp-core/.github/workflows/docker-build.yaml` faz checkout dos irmãos com nomes ANTIGOS:
- `repository: Rural-Environmental-Registry/rer-dsp-backend` → deve ser `dsp-backend`
- idem `rer-dsp-frontend`, `rer-dsp-job-data-migration`
- `path: rer-dsp-core` / `rer-dsp-backend` etc → padronizar (paths do compose já foram p/ `../backend` etc no deploy local, mas o CI usa `../rer-dsp-*`)
- `secrets.DSP_SIBLING_REPOS_TOKEN` — confirmar que existe e tem read nos repos renomeados.
**Ação**: atualizar nomes no workflow. Alinhar com os `context:` do docker-compose.yml (que hoje
apontam `../rer-dsp-*` no repo, mas foram ajustados p/ `../X` no clone local — divergência a unificar).

### P1 — dsp-gateway: 3 bugs de imagem (elimina o command wrapper do K8s)
Dockerfile atual: `FROM nginx:alpine` + `COPY nginx/ /etc/nginx/templates/`. Só isso.
1. **Não remove `/etc/nginx/conf.d/default.conf`** do nginx base → o entrypoint NÃO processa o
   template DSP (envsubst só roda se o conf destino não existir). **Fix**: `RUN rm -f /etc/nginx/conf.d/default.conf`
   (o dsp-frontend JÁ faz isso — copiar o padrão de lá).
2. **`resolver 127.0.0.11` hardcoded** (`default.conf.template:19`) = DNS do Docker. Em K8s é CoreDNS.
   **Fix**: `resolver ${DSP_RESOLVER} valid=10s ipv6=off;` + default `127.0.0.11` no compose e
   `10.247.3.10` (ou `kube-dns.kube-system.svc.cluster.local`) no K8s. Adicionar `DSP_RESOLVER` ao envsubst.
3. **Upstreams com nome curto hardcoded** (`set $dsp_frontend dsp-frontend:8080`). Com resolver custom,
   nginx não usa search domain → "Host not found" em K8s. **Fix**: parametrizar via env
   `${DSP_FRONTEND_UPSTREAM}` (compose=`dsp-frontend:8080`, K8s=`dsp-frontend.dsp-dev.svc.cluster.local:8080`)
   OU usar FQDN que resolve nos dois (compose resolve short, K8s precisa FQDN). Idem backend, 2 geoservers.
   Adicionar essas vars ao bloco envsubst e ao `.env.example`.

> Nota envsubst: o compose já usa `NGINX_ENVSUBST_FILTER: "^DSP_"` (só substitui `${DSP_*}`, preserva
> `$uri/$host`). Então basta nomear as novas vars como `DSP_RESOLVER`, `DSP_FRONTEND_UPSTREAM`,
> `DSP_BACKEND_UPSTREAM`, `DSP_GEOSERVER_EXHIBITION_UPSTREAM`, `DSP_GEOSERVER_DOWNLOAD_UPSTREAM` que o
> filtro `^DSP_` já as pega. Trocar no template `127.0.0.11`→`${DSP_RESOLVER}` e
> `set $x dsp-frontend:8080`→`set $x ${DSP_FRONTEND_UPSTREAM}` etc.

Resultado: gateway roda igual em compose e K8s **sem command wrapper**. Workaround atual (deploy K8s):
`command: rm default.conf + sed resolver + sed FQDNs + docker-entrypoint.sh` — remover após corrigir imagem.

### P2 — GeoServer PROXY_BASE_URL  [CONFIRMADO: já é runtime]
`PROXY_BASE_URL` JÁ é env runtime no compose (`${DSP_PUBLIC_BASE_URL}/geoserver-exhibition|download`,
default `http://localhost:8026`). NÃO é baked. **Problema no deploy K8s de 23/set**: não setamos essa
env → GeoServers usam default `localhost:8026` → **links WMS/WFS quebrados**. **Fix (só overlay K8s)**:
adicionar env nos deployments geoserver-exhibition/download:
`PROXY_BASE_URL=https://dspdev.dataprev.gov.br/geoserver-exhibition` (e `/geoserver-download`).
Também `DSP_GEOSERVER_WFS_BASE_URL` no backend já tem default de cluster ok.
Não precisa mexer na imagem — só no K8s. Rápido.

### P3 — Segredos
`.env.example` tem senhas em texto (dsp/dsp, geoserver). K8s `secrets.yaml` tem `CHANGE_ME`.
**Ação**: para dev interno, ok placeholders; antes de qa/prd → sealed-secrets ou SOPS. Nunca versionar real.

### P4 — Config JSON (installation/map/downloads/about)
Baked na imagem via `select-runtime-config.sh` (backend). Para permitir troca por ambiente sem rebuild,
avaliar montar como ConfigMap em K8s (`/config/*.json`). Hoje é baked — aceitável no MVP, revisar.

## Padrão-alvo (mesma imagem, config por ambiente)
```
imagem (build uma vez, sem valores de ambiente)
  ├── compose:  .env  → docker compose environment/args
  └── K8s:      ConfigMap (não-secreto: hosts, resolver, PROXY_BASE_URL, URLs)
                Secret    (senhas, credenciais)
                → montados como env/arquivo nos deployments
```
Regra: **nada de host/URL/credencial cozido no build**. Só binário + template. Valores entram em runtime.

## Ordem de execução (branch develop de cada repo)
1. **P0** — fix CI do core (nomes renomeados) → destrava rebuild das imagens. Testar workflow_dispatch.
2. **P1** — corrigir Dockerfile + template do gateway (3 fixes) → rebuild → validar em K8s SEM wrapper.
3. **P2** — GeoServer PROXY_BASE_URL runtime.
4. Atualizar `docker-compose.yml` + `.env.example` com as novas vars (DSP_RESOLVER, *_UPSTREAM).
5. Atualizar overlay K8s (rer-infra/dsp/k8s): ConfigMap com as vars, remover command wrapper do gateway.
6. **P3/P4** — segredos e configs JSON (antes de qa/prd).
7. PR em develop de cada repo + validar imagem nova roda em compose E K8s.

## Governança
- Atuar em `develop` (DTP manda). `dsp-develop` é da Youx.
- Bugs do gateway: podemos corrigir em develop e a Youx sincroniza. Alinhar com Leonardo/Youx.
