#!/bin/bash
# =============================================================================
# Data Import Pipeline (Rasters + Benches)
# =============================================================================
# This script helps initialize a fresh database with required spatial data.
# It can import:
#   1) Raster data (DSM/DEM) via raster2pgsql
#   2) Bench vector data (OSM benches)
#   3) Both, in sequence
#
# Requirements:
#   - Docker services running (docker-compose up -d in infrastructure/docker)
#   - Raster files present on host: data/raw/dsm_graz_1m.tif, data/raw/dem_graz.tif
#   - Bench data already in SQL script (03_import_benches.sql)
#
# Usage:
#   ./import_data.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/infrastructure/docker"

PSQL_CMD="docker-compose --env-file ../../.env exec -T postgres psql -U postgres -d sonnenbankerl"
RAW_CHECK_DIR="../../data/raw"

print_header() {
  echo "=============================================="
  echo "Sonnenbankerl - Data Import"
  echo "=============================================="
  echo ""
  echo "This helper will:";
  echo "  - Ensure required extensions are enabled"
  echo "  - Import DSM/DEM rasters (optional)"
  echo "  - Import OSM bench data (optional)"
  echo ""
  echo "Select what to import:"
  echo "  1) Rasters only (DSM/DEM)"
  echo "  2) Benches only"
  echo "  3) Both rasters and benches"
  echo ""
}

check_raster_files() {
  local missing=0
  for f in "$RAW_CHECK_DIR/dsm_graz_1m.tif" "$RAW_CHECK_DIR/dem_graz.tif"; do
    if [[ ! -f "$f" ]]; then
      echo "Missing raster file: $f"
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    echo "Checked host path (from infrastructure/docker): $RAW_CHECK_DIR"
  fi
  if [[ "$missing" -eq 1 ]]; then
    echo "Please place required rasters in data/raw before importing."
    exit 1
  fi
}

run_extensions() {
  echo "Step 0: Ensuring extensions..."
  echo "----------------------------------------------"
  set +e
  $PSQL_CMD -f /precomputation/01_setup_extensions.sql
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    echo "WARNING: Extension setup reported errors (e.g., suncalc_postgres missing)."
    echo "         You can install the extension later; pipeline will fall back to sample sun data."
  fi
  echo ""
}

import_rasters() {
  echo "Step 1: Importing rasters (DSM/DEM)..."
  echo "----------------------------------------------"
  check_raster_files
  docker-compose --env-file ../../.env exec -T postgres bash -c "raster2pgsql -s 4326 -I -C -M /data/raw/dsm_graz_1m.tif dsm_raster | psql -U postgres -d sonnenbankerl"
  docker-compose --env-file ../../.env exec -T postgres bash -c "raster2pgsql -s 4326 -I -C -M /data/raw/dem_graz.tif dem_raster | psql -U postgres -d sonnenbankerl"
  $PSQL_CMD -f /precomputation/02_import_rasters.sql
  echo ""
}

import_benches() {
  echo "Step 2: Importing benches (OSM)..."
  echo "----------------------------------------------"
  $PSQL_CMD -f /precomputation/03_import_benches.sql
  echo ""
}

print_header
read -p "Enter choice [1/2/3]: " choice

do_rasters=false
do_benches=false
case "$choice" in
  1) do_rasters=true ;;
  2) do_benches=true ;;
  3) do_rasters=true; do_benches=true ;;
  *) echo "Invalid choice"; exit 1 ;;
esac

echo ""
echo "Estimated time: rasters (5-15 min), benches (<1 min)"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo ""
run_extensions

if $do_rasters; then
  import_rasters
fi

if $do_benches; then
  import_benches
fi

echo "=============================================="
echo "Data import complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  - Run ./compute_next_week.sh to generate exposure"
echo "  - Validate with: $PSQL_CMD -c \"SELECT * FROM v_bench_stats;\""
echo ""
