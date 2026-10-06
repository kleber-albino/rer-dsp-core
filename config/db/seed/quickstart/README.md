# Quickstart seed (demonstration only)

Static SQL that populates `dsp-db` and `dsp-geoserver-db` without a JDBC source or migration job.

## Contents

| File | Target |
| --- | --- |
| `01_territory_dsp.sql` | `dsp.territory_level_*` on dsp-db (bbox + centroid) |
| `01_territory_exhibition.sql` | same tables on exhibition-db (`geom`) |
| `02_aoi_dsp.sql` | Loads `dsp.area_of_interest` on dsp-db (+ `kpi_measure` demo) |
| `02_aoi_exhibition.sql` | Loads AOI rows on geoserver-db (`geom`) |

## Hierarchy

- L1: Brazil (`BR`)
- L2: 5 regions (union of states; source region table has no geometry)
- L3: 27 states
- AOI: 54 synthetic `DEMO-*` squares (2 per state)

## Geometry notes

- SRID: **4674** (SIRGAS 2000)
- Territory polygons: heavily simplified — not cartographic quality
- Boundaries are **shared**: neighbouring states touch with no gaps and no overlapping area, and each region is the dissolved union of its states (so region borders match the state borders on them)
- Simplification was done over the whole coverage at once (topology-aware), not polygon by polygon — that is what keeps the borders coincident
- The source data is not an exact partition: a few thin strips are left between neighbouring states. They are invisible on the state layer, but dissolving them into regions/country turns each strip into a near-zero-width notch that renders as a stray line. The strips were closed and handed to the neighbouring state, so the dissolved layers have no notches and no holes
- AOI squares: `ST_Expand(centroid, 0.12°)` → side ≈ 0.24° (~26 km); **not** real property boundaries
- **12 overlapping AOI pairs** (partial intersection); remaining pairs are separated
- Squares may cross state borders or coastlines — acceptable for demo

## Usage

Applied by `./setup.sh` when you choose option **1** (demonstration).

Core init SQL (`01b_area_of_interest.sql` in the DB images) creates the minimal `dsp.area_of_interest` skeleton on both Postgres; `./start.sh` also applies it on older volumes if the table is missing. These seed files only insert demo rows (and `kpi_measure` on dsp-db). Adopter installs add variable columns and data via the migration job (`additional_columns`). The last-update column is `updated_at`.

The quickstart `installation-config.json` uses **`map.initialView.mode: manual`** (center Brazil, zoom 4) so the home map always opens framed on the demo territory without depending on `GET /territory/boundary-box` at first load.

Do **not** use these files for production or as a real adopter mapping.
