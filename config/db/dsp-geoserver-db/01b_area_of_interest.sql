-- Fixed skeleton for dsp.area_of_interest on GeoServers (full geometry).
-- Extra adopter-specific columns come from the migration job. No area column (dsp-db only).

CREATE TABLE IF NOT EXISTS dsp.area_of_interest (
    id                   VARCHAR(255) PRIMARY KEY,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ,
    territory_level_3_id VARCHAR(64) REFERENCES dsp.territory_level_3 (id),
    geom                 geometry(MultiPolygon)
);

CREATE INDEX IF NOT EXISTS idx_area_of_interest_territory_level_3_id
    ON dsp.area_of_interest (territory_level_3_id);
CREATE INDEX IF NOT EXISTS idx_area_of_interest_geom
    ON dsp.area_of_interest USING GIST (geom);

COMMENT ON TABLE dsp.area_of_interest IS 'Area of interest with full geometry for map / WFS';
