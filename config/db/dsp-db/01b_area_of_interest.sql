-- Fixed skeleton for dsp.area_of_interest (API / KPIs / migration).
-- Extra adopter-specific columns come from the migration job (additional_columns / mappings).

CREATE TABLE IF NOT EXISTS dsp.area_of_interest (
    id                   VARCHAR(255) PRIMARY KEY,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ,
    territory_level_3_id VARCHAR(64) REFERENCES dsp.territory_level_3 (id),
    area                 NUMERIC,
    boundary_box         geometry(Polygon),
    centroid_coordinates geometry(Point)
);

CREATE INDEX IF NOT EXISTS idx_area_of_interest_territory_level_3_id
    ON dsp.area_of_interest (territory_level_3_id);
CREATE INDEX IF NOT EXISTS idx_area_of_interest_boundary_box
    ON dsp.area_of_interest USING GIST (boundary_box);
CREATE INDEX IF NOT EXISTS idx_area_of_interest_centroid_coordinates
    ON dsp.area_of_interest USING GIST (centroid_coordinates);

COMMENT ON TABLE dsp.area_of_interest IS 'Area of interest (light geo on dsp-db; full geom on geoserver-db)';
