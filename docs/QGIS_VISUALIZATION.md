# QGIS Visualization Guide

This guide explains how to visualize bench sun exposure in QGIS using PostgreSQL/PostGIS tables.

## Connection Setup

### 1. Add PostgreSQL Connection

1. Open QGIS
2. Go to **Browser** panel
3. Right-click **PostgreSQL** → **New Connection**
4. Fill in:
   - **Name**: Sonnenbankerl (or your preference)
   - **Host**: localhost (or VPS IP)
   - **Port**: 5435 (check docker-compose.yml)
   - **Database**: sonnenbankerl
   - **SSL mode**: Prefer
5. Click **Test Connection** → Enter credentials:
   - **Username**: postgres
   - **Password**: (from .env file)
6. Click **OK**

### 2. Available Tables for QGIS

#### qgis_bench_exposure (Full Dataset)
```
Records: 18,250 (all exposure data)
SRID: 4326
Geometry: POINT
```

**Fields:**
- `bench_id`: Bench identifier
- `osm_id`: OpenStreetMap ID
- `geometry`: Bench location (POINT, 4326)
- `elevation`: Bench elevation (meters)
- `timestamp`: Time of exposure check
- `is_sunny`: TRUE/FALSE
- `exposure_status`: 'Sunny' or 'Shady'
- `azimuth_deg`: Sun azimuth (degrees)
- `sun_elevation`: Sun elevation (degrees)

#### qgis_today_exposure (Today's Data)
```
Records: ~2,600 (today only, refreshable)
SRID: 4326
Geometry: POINT
```

**Fields:** Same as above, but filtered to current date.

**Refresh today's data:**
```sql
SELECT refresh_qgis_today();
```

## Quick Styling Guide

### Categorized by Exposure Status

1. Add `qgis_today_exposure` to QGIS
2. Right-click layer → **Properties** → **Symbology**
3. **Symbology type**: Categorized
4. **Column**: `exposure_status`
5. Click **Classify**
6. Style:
   - **Sunny**: Yellow (#FFD700) marker, size 10
   - **Shady**: Blue (#4169E1) marker, size 10

### Filter by Time

Use QGIS filter or expression:
```sql
timestamp = '2026-01-10 12:00:00+01'
```

Or for a time range:
```sql
timestamp >= '2026-01-10 12:00:00+01' 
AND timestamp < '2026-01-10 12:10:00+01'
```

### Labels

Show bench_id for identification:
- **Label field**: `bench_id`
- **Placement**: Above point

## Useful Queries

Run these in QGIS **DB Manager** → **PostgreSQL** → Execute SQL:

### Today's Summary
```sql
SELECT exposure_status, COUNT(DISTINCT bench_id) as benches
FROM qgis_today_exposure
GROUP BY exposure_status;
```

### Sunny Benches at Noon
```sql
SELECT bench_id, ST_AsText(geometry) as location
FROM qgis_today_exposure
WHERE exposure_status = 'Sunny'
  AND timestamp::time BETWEEN '12:00' AND '12:10';
```

### Top 10 Sunniest Benches Today
```sql
SELECT bench_id, COUNT(*) as sunny_hours
FROM qgis_today_exposure
WHERE exposure_status = 'Sunny'
GROUP BY bench_id
ORDER BY sunny_hours DESC
LIMIT 10;
```

### Benches with Most Shady Hours
```sql
SELECT bench_id, COUNT(*) as shady_hours
FROM qgis_today_exposure
WHERE exposure_status = 'Shady'
GROUP BY bench_id
ORDER BY shady_hours DESC
LIMIT 10;
```

### Exposure Distribution by Hour
```sql
SELECT 
    EXTRACT(HOUR FROM timestamp) as hour,
    COUNT(CASE WHEN exposure_status = 'Sunny' THEN 1 END) as sunny,
    COUNT(CASE WHEN exposure_status = 'Shady' THEN 1 END) as shady
FROM qgis_today_exposure
GROUP BY EXTRACT(HOUR FROM timestamp)
ORDER BY hour;
```

## Troubleshooting

### No geometry detected?
Ensure you're using the `qgis_*` tables, not views. The views have SRID=0 issues in some QGIS versions.

### Can't connect?
- Check PostgreSQL is running: `docker-compose ps`
- Verify port 5435 (not default 5432)
- Check credentials in .env file

### Wrong timestamps?
PostgreSQL stores timestamps in UTC. Filter using:
```sql
timestamp::date = CURRENT_DATE
```

### Data not updating?
Refresh the materialized view:
```sql
SELECT refresh_qgis_today();
```

## Performance Tips

- Use `qgis_today_exposure` for faster access (2,600 vs 18,250 records)
- Filter by timestamp before loading large datasets
- Create spatial indexes (already done)
- Limit display to visible map area

## Data Refresh

To refresh today's data after recomputation:

```sql
-- Quick refresh
SELECT refresh_qgis_today();

-- Or manual refresh
TRUNCATE qgis_today_exposure;
INSERT INTO qgis_today_exposure 
SELECT * FROM qgis_bench_exposure 
WHERE timestamp::date = CURRENT_DATE;
```

## See Also

- [Precomputation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Database Schema](../database/README.md)
- [Backend API](../backend/README.md)
