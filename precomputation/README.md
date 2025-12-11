# Precomputation Scripts

Python scripts for batch processing sun exposure data.

## Structure

```
precomputation/
├── compute_exposure.py       # Main precomputation script
├── los_algorithm.py          # Line-of-sight calculations
├── import_osm.py             # OSM data import
├── import_dsm.py             # DSM/DEM raster import
└── requirements.txt          # Python dependencies
```

## Prerequisites

- Python 3.10+
- PostgreSQL with PostGIS and TimescaleDB
- DSM/DEM raster files (GeoTIFF format)
- Access to OpenStreetMap data

## Installation

```bash
cd precomputation

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Usage

### 1. Import DSM/DEM Rasters

```bash
# Import Digital Surface Model (1m resolution)
python import_dsm.py --dsm ../data/raw/dsm_graz_1m.tif --dem ../data/raw/dem_graz.tif
```

### 2. Import Bench Data from OSM

```bash
# Download and import benches from OpenStreetMap
python import_osm.py --bbox 47.0,15.3,47.1,15.5 --output ../data/osm/graz_benches.geojson
```

### 3. Run Precomputation

```bash
# Full computation for a year (takes hours/days)
python compute_exposure.py --year 2026 --parallel 8

# Incremental update (for new benches or future dates)
python compute_exposure.py --year 2027 --incremental

# Process specific bench IDs only
python compute_exposure.py --year 2026 --bench-ids 1,2,3,4,5
```

### Parameters

**compute_exposure.py options:**
```
--year YEAR            Target year for computation
--parallel N           Number of parallel workers (default: CPU count)
--incremental          Only compute missing data
--bench-ids IDS        Comma-separated bench IDs to process
--interval MINUTES     Time interval in minutes (default: 10)
--max-distance METERS  Maximum ray distance for LOS (default: 1000)
```

## Algorithm Overview

### Line-of-Sight (LOS) Calculation

For each bench and timestamp:
1. Calculate sun position (azimuth, elevation) using suncalc
2. Compute 3D ray from bench to sun direction
3. Sample DSM along ray at regular intervals
4. Check if any obstacle blocks the sun
5. Store binary result (exposed/not exposed)

### Performance

**Processing time estimates:**
- 200 benches × 52,560 timestamps: ~1-3 days (8 cores)
- 1000 benches × 52,560 timestamps: ~5-7 days (8 cores)

**Optimization strategies:**
- Parallel processing across benches
- Spatial indexing for DSM queries
- Batch database inserts (1000 rows at a time)
- Skip nighttime hours (sun elevation < 0°)

## Scheduled Updates

For automated updates, set up a cron job:

```bash
# Edit crontab
crontab -e

# Run incremental update every 6 months (Jan 1 and Jul 1 at 2 AM)
0 2 1 1,7 * cd /opt/sonnenbankerl/precomputation && ./venv/bin/python compute_exposure.py --year $(date +\%Y) --incremental >> /var/log/sonnenbankerl/precompute.log 2>&1
```

## Monitoring

```bash
# Check progress during computation
tail -f /var/log/sonnenbankerl/precompute.log

# Monitor database growth
psql -d sonnenbankerl -c "SELECT pg_size_pretty(pg_total_relation_size('exposure'));"

# Check completion status
psql -d sonnenbankerl -c "SELECT COUNT(*) FROM exposure WHERE EXTRACT(YEAR FROM timestamps.ts) = 2026;"
```

## Data Sources

### DSM/DEM Data
- Source: Bundesamt für Eich- und Vermessungswesen (BEV)
- Resolution: 1m (DSM), 10m (DEM)
- Format: GeoTIFF
- Download: https://www.bev.gv.at/

### OpenStreetMap Data
- Source: OpenStreetMap
- Query: Overpass API
- Tags: amenity=bench, tourism=viewpoint
- Export: GeoJSON format

## Troubleshooting

**Out of memory errors:**
- Reduce parallel workers: `--parallel 2`
- Process in smaller batches: use `--bench-ids`

**Slow DSM queries:**
- Ensure spatial indexes exist on raster tables
- Consider pre-tiling DSM for faster access

**Database connection issues:**
- Check `DATABASE_URL` in `.env`
- Ensure PostgreSQL allows enough connections
- Use connection pooling for large batches

## Documentation

For detailed pipeline information, see:
- [Sunshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Backend Architecture](../docs/architecture.md)
