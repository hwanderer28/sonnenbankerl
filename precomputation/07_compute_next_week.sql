-- =============================================================================
-- Weekly Exposure Pipeline - Results & Verification
-- =============================================================================
-- This script displays the results of the weekly exposure computation.
-- Run this after compute_exposure_next_days(7) to see results.
--
-- For fresh computation, run in order:
--   1. docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql
--   2. docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql
--   3. docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days(7);"
--   4. docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql

DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    bench_count INTEGER;
    ts_count INTEGER;
    sp_count INTEGER;
    exp_count INTEGER;
BEGIN
    start_date := CURRENT_DATE;
    end_date := CURRENT_DATE + 6;

    RAISE NOTICE '============================================';
    RAISE NOTICE 'Weekly Exposure Computation - Results';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Timeframe: % to %', start_date, end_date;
    RAISE NOTICE '';

    -- Count data
    SELECT COUNT(*) INTO bench_count FROM benches;
    SELECT COUNT(*) INTO ts_count FROM timestamps
    WHERE ts::DATE BETWEEN start_date AND end_date;
    SELECT COUNT(*) INTO sp_count FROM sun_positions sp
    JOIN timestamps t ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN start_date AND end_date;
    SELECT COUNT(*) INTO exp_count FROM exposure e
    JOIN timestamps t ON e.ts_id = t.id
    WHERE t.ts::DATE BETWEEN start_date AND end_date;

    RAISE NOTICE 'Data Summary:';
    RAISE NOTICE '  Benches: %', bench_count;
    RAISE NOTICE '  Timestamps: %', ts_count;
    RAISE NOTICE '  Sun positions: %', sp_count;
    RAISE NOTICE '  Exposure records: %', exp_count;
    RAISE NOTICE '';

    IF exp_count = 0 THEN
        RAISE WARNING 'No exposure data found!';
        RAISE NOTICE 'Run: SELECT compute_exposure_next_days(7);';
        RETURN;
    END IF;

    -- Overall statistics
    RAISE NOTICE 'Overall Exposure Statistics:';
    SELECT
        COUNT(*) as total_records,
        COUNT(DISTINCT e.bench_id) as benches_processed,
        COUNT(CASE WHEN exposed THEN 1 END) as sunny_records,
        COUNT(CASE WHEN NOT exposed THEN 1 END) as shady_records
    INTO exp_count, bench_count, ts_count, sp_count
    FROM exposure e
    JOIN timestamps t ON e.ts_id = t.id
    WHERE t.ts::DATE BETWEEN start_date AND end_date;

    RAISE NOTICE '  Total records: %', exp_count;
    RAISE NOTICE '  Benches with data: %', bench_count;
    IF exp_count > 0 THEN
        RAISE NOTICE '  Sunny: % (% %%)', ts_count, ROUND(ts_count * 100.0 / exp_count, 1);
        RAISE NOTICE '  Shady: % (% %%)', sp_count, ROUND(sp_count * 100.0 / exp_count, 1);
    ELSE
        RAISE NOTICE '  Sunny: 0 (0.0%%)';
        RAISE NOTICE '  Shady: 0 (0.0%%)';
    END IF;
    RAISE NOTICE '';

    -- Per-day breakdown
    RAISE NOTICE 'Daily Breakdown:';
END $$;

-- Display daily statistics
SELECT
    t.ts::DATE as date,
    COUNT(*) as total,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny,
    COUNT(CASE WHEN NOT e.exposed THEN 1 END) as shady,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / COUNT(*), 1) as sunny_pct
FROM exposure e
JOIN timestamps t ON e.ts_id = t.id
WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6
GROUP BY t.ts::DATE
ORDER BY t.ts::DATE;

DO $$
DECLARE
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := CURRENT_DATE;
    end_date := CURRENT_DATE + 6;

    RAISE NOTICE '';

    -- Per-bench statistics
    RAISE NOTICE 'Per-Bench Statistics (Top 5 sunniest):';
END $$;

-- Display bench-level statistics
SELECT
    b.id as bench_id,
    COUNT(*) as total_hours,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny_hours,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / COUNT(*), 1) as sunny_pct,
    MIN(t.ts)::time as first_sun,
    MAX(t.ts)::time as last_sun
FROM exposure e
JOIN timestamps t ON e.ts_id = t.id
JOIN benches b ON e.bench_id = b.id
WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6
  AND e.exposed = true
GROUP BY b.id
ORDER BY sunny_hours DESC
LIMIT 10;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Pipeline complete! Data ready for API.';
    RAISE NOTICE '============================================';
END $$;
