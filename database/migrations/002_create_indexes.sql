-- Performance indexes for spatial and time-series queries
-- Run after initial schema creation

-- ============================================================================
-- Spatial Index on Benches
-- ============================================================================
-- GIST index for fast spatial queries (benches within radius)
CREATE INDEX IF NOT EXISTS benches_geom_idx ON benches USING GIST(geom);

COMMENT ON INDEX benches_geom_idx IS 'Spatial index for finding benches near a location';

-- ============================================================================
-- Temporal Index on Timestamps
-- ============================================================================
-- B-tree index for fast timestamp lookups
CREATE INDEX IF NOT EXISTS timestamps_ts_idx ON timestamps(ts);

COMMENT ON INDEX timestamps_ts_idx IS 'Index for fast timestamp lookups';

-- ============================================================================
-- Composite Index on Exposure
-- ============================================================================
-- Optimized for queries: "get exposure timeline for a specific bench"
CREATE INDEX IF NOT EXISTS exposure_bench_ts_idx ON exposure (bench_id, ts_id DESC);

COMMENT ON INDEX exposure_bench_ts_idx IS 'Index for querying exposure timeline for a specific bench';

-- ============================================================================
-- Success Message
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Indexes created successfully';
    RAISE NOTICE 'Performance optimizations applied';
END $$;
