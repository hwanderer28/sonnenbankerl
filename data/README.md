# Data Directory

Storage location for raw and processed geospatial data.

**Note:** This directory is git-ignored. Large data files should not be committed to the repository.

## Structure

```
data/
├── raw/                    # Raw source data (git-ignored)
│   ├── dsm_graz_1m.tif    # Digital Surface Model (1m resolution)
│   ├── dem_graz.tif       # Digital Elevation Model
│   └── README.txt         # Data source information
├── processed/              # Processed/derived data (git-ignored)
│   └── [generated files]
└── osm/                    # OpenStreetMap exports
    └── graz_benches.geojson
```

## Data Sources

### Digital Surface Model (DSM) & Digital Elevation Model (DEM)

**Source:** Bundesamt für Eich- und Vermessungswesen (BEV)  
**URL:** https://www.bev.gv.at/

**Required files:**
- DSM: 1m resolution for Graz region (building heights, vegetation)
- DEM: Ground elevation for Graz region

**Download instructions:**
1. Visit BEV Open Data portal
2. Search for "Digitales Geländemodell" (DEM) and "Digitales Oberflächenmodell" (DSM)
3. Select Graz region (Steiermark)
4. Download as GeoTIFF format
5. Place in `data/raw/` directory

**Expected file sizes:**
- DSM: 500 MB - 2 GB
- DEM: 100 MB - 500 MB

### OpenStreetMap Bench Data

**Source:** OpenStreetMap via Overpass API  
**URL:** https://overpass-turbo.eu/

**Query for Graz benches:**
```overpass
[out:json];
area["name"="Graz"]["admin_level"="6"]->.searchArea;
(
  node["amenity"="bench"](area.searchArea);
  way["amenity"="bench"](area.searchArea);
);
out center;
```

**Manual download:**
1. Visit https://overpass-turbo.eu/
2. Paste query above
3. Click "Run"
4. Export as GeoJSON
5. Save to `data/osm/graz_benches.geojson`

**Automated import:**
```bash
cd precomputation
python import_osm.py --bbox 47.0,15.3,47.1,15.5 --output ../data/osm/graz_benches.geojson
```

## File Formats

### Raster Data (DSM/DEM)
- Format: GeoTIFF (.tif)
- Coordinate System: EPSG:4326 (WGS84) or EPSG:31256 (MGI Austria Lambert)
- Data Type: Float32
- NoData Value: -9999

### Vector Data (Benches)
- Format: GeoJSON (.geojson)
- Coordinate System: EPSG:4326 (WGS84)
- Geometry Type: Point

## Usage

### Import Rasters to Database

```bash
# From project root
cd precomputation

# Import DSM and DEM
python import_dsm.py \
  --dsm ../data/raw/dsm_graz_1m.tif \
  --dem ../data/raw/dem_graz.tif \
  --database sonnenbankerl
```

### Import Bench Data

```bash
python import_osm.py \
  --input ../data/osm/graz_benches.geojson \
  --database sonnenbankerl
```

## Data Management

### Storage Requirements

**Development:**
- Raw data: ~2-3 GB
- Processed data: ~500 MB
- Total: ~3 GB

**Production:**
- Database (with full exposure data): 5-10 GB
- Backup archives: 1-2 GB per backup

### Cleanup

```bash
# Remove processed files (regenerate as needed)
rm -rf data/processed/*

# Archive old exports
tar -czf data/archive/osm_$(date +%Y%m%d).tar.gz data/osm/
```

## Data Updates

### DSM/DEM Updates
- Frequency: Every 2-5 years (when BEV releases new versions)
- Process: Download new files, re-import, re-run precomputation

### Bench Data Updates
- Frequency: Monthly or as needed
- Process: Run `import_osm.py` to fetch latest OSM data
- Note: Only new benches require precomputation

## Troubleshooting

**Large file warnings in git:**
```bash
# Verify .gitignore includes data/raw and data/processed
git check-ignore data/raw/dsm_graz_1m.tif
# Should output: data/raw/dsm_graz_1m.tif
```

**Coordinate system mismatches:**
```bash
# Check raster CRS
gdalinfo data/raw/dsm_graz_1m.tif | grep EPSG

# Reproject if needed
gdalwarp -t_srs EPSG:4326 input.tif output.tif
```

**Missing data files:**
```bash
# Verify files exist
ls -lh data/raw/
ls -lh data/osm/

# Check file integrity
gdalinfo data/raw/dsm_graz_1m.tif
```

## Documentation

For more information on data processing, see:
- [Precomputation Scripts](../precomputation/README.md)
- [Sunshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
