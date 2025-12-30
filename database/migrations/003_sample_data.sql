-- Sample data for testing and development
-- Three benches in Graz Stadtpark area with 7 days of exposure data

-- ============================================================================
-- Sample Benches in Graz Stadtpark
-- ============================================================================
INSERT INTO benches (osm_id, geom, elevation, name) VALUES
(1001, ST_SetSRID(ST_MakePoint(15.4395, 47.0707), 4326), 353.2, 'Stadtpark Bench 1'),
(1002, ST_SetSRID(ST_MakePoint(15.4405, 47.0715), 4326), 354.5, 'Stadtpark Bench 2'),
(1003, ST_SetSRID(ST_MakePoint(15.4385, 47.0695), 4326), 352.8, 'Stadtpark Bench 3')
ON CONFLICT (osm_id) DO NOTHING;

-- ============================================================================
-- Generate Timestamps (Next 7 Days, 10-minute Intervals)
-- ============================================================================
-- ~1,008 timestamps (7 days × 24 hours × 6 intervals/hour)
INSERT INTO timestamps (ts)
SELECT generate_series(
    date_trunc('hour', NOW()),
    date_trunc('hour', NOW()) + INTERVAL '7 days',
    INTERVAL '10 minutes'
)
ON CONFLICT (ts) DO NOTHING;

-- ============================================================================
-- Generate Sample Sun Positions
-- ============================================================================
-- Simplified sun position calculation for testing
-- In production, this would be calculated using proper solar algorithms
INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
SELECT 
    id,
    -- Simplified azimuth: 90° (east) at 6am, 180° (south) at 12pm, 270° (west) at 6pm
    90 + (EXTRACT(HOUR FROM ts) - 6) * 15 as azimuth_deg,
    -- Simplified elevation: peak at noon, negative at night
    CASE 
        WHEN EXTRACT(HOUR FROM ts) BETWEEN 6 AND 18 THEN
            45 - ABS(EXTRACT(HOUR FROM ts) - 12) * 3.5
        ELSE
            -10
    END as elevation_deg
FROM timestamps
ON CONFLICT (ts_id) DO NOTHING;

-- ============================================================================
-- Generate Sample Exposure Data
-- ============================================================================
-- Simplified exposure: benches are sunny during daylight hours (8 AM - 6 PM)
-- In production, this would be calculated using line-of-sight algorithms with DSM data
INSERT INTO exposure (ts_id, bench_id, exposed)
SELECT 
    t.id as ts_id,
    b.id as bench_id,
    CASE 
        -- Sunny hours: 8 AM to 6 PM
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 8 AND 17 THEN TRUE
        -- Night/early morning/late evening: shady
        ELSE FALSE
    END as exposed
FROM timestamps t
CROSS JOIN benches b
ON CONFLICT (ts_id, bench_id) DO NOTHING;

-- ============================================================================
-- Verify Data Insertion
-- ============================================================================
DO $$
DECLARE
    bench_count INT;
    timestamp_count INT;
    exposure_count INT;
BEGIN
    SELECT COUNT(*) INTO bench_count FROM benches;
    SELECT COUNT(*) INTO timestamp_count FROM timestamps;
    SELECT COUNT(*) INTO exposure_count FROM exposure;
    
    RAISE NOTICE 'Sample data inserted successfully';
    RAISE NOTICE 'Benches: %', bench_count;
    RAISE NOTICE 'Timestamps: %', timestamp_count;
    RAISE NOTICE 'Exposure records: %', exposure_count;
END $$;
