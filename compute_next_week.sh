#!/bin/bash
# =============================================================================
# Weekly Exposure Pipeline - Complete Execution
# =============================================================================
# This script runs the complete weekly exposure computation pipeline:
#   1. Ensure suncalc_postgres is installed
#   2. Generate weekly timestamps (today + 7 days)
#   3. Compute sun positions for the week
#   4. Compute sun exposure for all benches
#   5. Display results
#
# Usage:
#   ./compute_next_week.sh
#
# Estimated time: 15-30 minutes

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/infrastructure/docker

echo "=============================================="
echo "Sonnenbankerl - Weekly Exposure Pipeline"
echo "=============================================="
echo ""
echo "This pipeline will:"
echo "  0. Ensure suncalc_postgres is installed"
echo "  1. Clean old computation data"
echo "  2. Generate timestamps for next 7 days"
echo "  3. Compute sun positions (azimuth, elevation)"
echo "  4. Load exposure functions/config"
echo "  5. Precompute DEM horizons (2° bins to 8 km)"
echo "  6. Compute exposure for all benches"
echo "  7. Display results"
echo ""
echo "Estimated time: 15-30 minutes"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo ""
echo "Step 0: Ensuring suncalc_postgres is installed..."
echo "----------------------------------------------"
# Check if suncalc is installed, install if missing
SUNFUNC_EXISTS=$(docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -tAc "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position');" 2>/dev/null || echo "f")
if [ "$SUNFUNC_EXISTS" = "f" ] || [ "$SUNFUNC_EXISTS" = "" ]; then
    echo "suncalc_postgres not found, installing..."
    docker-compose --env-file .env exec -T postgres bash -c "psql -U postgres -d sonnenbankerl -f /var/lib/suncalc_postgres/suncalc/suncalc.sql" || \
    docker-compose --env-file .env exec -T postgres bash -c "psql -U postgres -d sonnenbankerl -f /tmp/suncalc_postgres/suncalc/suncalc.sql"
    
    # Verify installation
    SUNFUNC_EXISTS=$(docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -tAc "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position');")
    if [ "$SUNFUNC_EXISTS" = "t" ]; then
        echo "✅ suncalc_postgres installed successfully!"
    else
        echo "❌ ERROR: suncalc_postgres installation failed"
        exit 1
    fi
else
    echo "✅ suncalc_postgres already installed"
fi

echo ""
echo "Step 1: Cleaning old computation data..."
echo "----------------------------------------------"
# Ensure bench_horizon table exists before truncating
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "CREATE TABLE IF NOT EXISTS bench_horizon (bench_id INTEGER NOT NULL, azimuth_deg INTEGER NOT NULL, max_angle_deg DOUBLE PRECISION NOT NULL, PRIMARY KEY (bench_id, azimuth_deg));"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "TRUNCATE exposure; TRUNCATE sun_positions; DELETE FROM timestamps WHERE ts >= CURRENT_DATE; TRUNCATE bench_horizon;"

echo ""
echo "Step 2: Generating weekly timestamps..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql

echo ""
echo "Step 3: Computing sun positions..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql

echo ""
echo "Step 4: Loading exposure functions..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -f /precomputation/06_compute_exposure.sql

echo ""
echo "Step 5: Precomputing DEM horizons (this may take a few minutes)..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_all_bench_horizons();"

echo ""
echo "Step 6: Computing exposure (this takes the most time)..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"

echo ""
echo "Step 7: Displaying results..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql


echo ""
echo "=============================================="
echo "Pipeline complete!"
echo "=============================================="
echo ""
echo "To query data manually:"
echo "  docker-compose exec postgres psql -U postgres -d sonnenbankerl"
echo ""
echo "Useful queries:"
echo "  SELECT * FROM exposure LIMIT 10;"
echo "  SELECT * FROM get_exposure_computation_stats();"
echo "  SELECT * FROM v_bench_stats;"
echo ""

