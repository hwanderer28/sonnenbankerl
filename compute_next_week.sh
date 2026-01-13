#!/bin/bash
# =============================================================================
# Weekly Exposure Pipeline - Complete Execution
# =============================================================================
# This script runs the complete weekly exposure computation pipeline:
#   1. Generate weekly timestamps (today + 7 days)
#   2. Compute sun positions for the week
#   3. Compute sun exposure for all benches
#   4. Display results
#
# Usage:
#   ./compute_next_week.sh
#
# Estimated time: 15-30 minutes

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/infrastructure/docker"

echo "=============================================="
echo "Sonnenbankerl - Weekly Exposure Pipeline"
echo "=============================================="
echo ""
echo "This pipeline will:"
echo "  1. Clean old computation data"
echo "  2. Generate timestamps for next 7 days"
echo "  3. Compute sun positions (azimuth, elevation)"
echo "  4. Load exposure functions/config"
echo "  5. Compute exposure for all 50 benches"
echo "  6. Display results"
echo ""
echo "Estimated time: 15-30 minutes"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo ""
echo "Step 1: Cleaning old computation data..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "TRUNCATE exposure; TRUNCATE sun_positions; DELETE FROM timestamps WHERE ts >= CURRENT_DATE;"

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
echo "Step 5: Computing exposure (this takes the most time)..."
echo "----------------------------------------------"
docker-compose --env-file .env exec -T postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"

echo ""
echo "Step 6: Displaying results..."
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
