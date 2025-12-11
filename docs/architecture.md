# Backend Architecture

This document outlines the comprehensive backend infrastructure for the Sonnenbankerl application, designed to be hosted on a VPS.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App                     │
│                    (iOS/Android Clients)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS/REST API
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                     YOUR VPS SERVER                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │            API Gateway / Load Balancer                │  │
│  │                    (Traefik)                          │  │
│  │              - SSL/TLS termination                    │  │
│  │              - Rate limiting                          │  │
│  │              - Request routing                        │  │
│  └─────────────┬──────────────────────┬──────────────────┘  │
│                │                      │                     │
│  ┌─────────────▼──────────┐  ┌────────▼──────────────────┐  │
│  │   REST API Service     │  │  Static File Service      │  │
│  │   (Node.js/Python)     │  │  (Optional: API docs)     │  │
│  │                        │  │                           │  │
│  │ - Bench queries        │  └───────────────────────────┘  │
│  │ - Weather integration  │                                 │
│  │ - Exposure calculations│                                 │
│  └─────────────┬──────────┘                                 │
│                │                                            │
│  ┌─────────────▼──────────────────────────────────────────┐ │
│  │         PostgreSQL Database                            │ │
│  │         + PostGIS + TimescaleDB                        │ │
│  │                                                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │   benches    │  │  timestamps  │  │ sun_positions│  │ │
│  │  │  (PostGIS)   │  └──────────────┘  └──────────────┘  │ │
│  │  └──────────────┘                                      │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  exposure (TimescaleDB hypertable)               │  │ │
│  │  │  - Precomputed sun/shade data                    │  │ │
│  │  │  - 10-min intervals for 2026                     │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Precomputation Service (Python)                  │  │
│  │      - Runs periodically (cron)                       │  │
│  │      - Batch processes sun exposure                   │  │
│  │      - Updates exposure table                         │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Monitoring & Logging                             │  │
│  │      - Application logs                               │  │
│  │      - Database performance monitoring                │  │
│  │      - Error tracking                                 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                       │
                       │ External API calls
                       │
         ┌─────────────▼────────────┐
         │  GeoSphere Austria API   │
         │  (Weather data)          │
         └──────────────────────────┘
```

## Component Breakdown

### 1. Database Layer

**Technology Stack:**
- PostgreSQL 14+
- PostGIS (spatial data extension)
- TimescaleDB (time-series optimization)
- suncalc_postgres (sun position calculations)

**Database Schema:**

```sql
-- Bench locations with spatial data
CREATE TABLE benches (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    geom GEOGRAPHY(POINT, 4326),
    elevation FLOAT,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX benches_geom_idx ON benches USING GIST(geom);

-- Timestamp intervals (10-minute resolution)
CREATE TABLE timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);
CREATE INDEX timestamps_ts_idx ON timestamps(ts);

-- Precomputed sun positions for Graz
CREATE TABLE sun_positions (
    ts_id INT REFERENCES timestamps(id),
    azimuth_deg FLOAT,
    elevation_deg FLOAT,
    PRIMARY KEY (ts_id)
);

-- Sun exposure data (TimescaleDB hypertable)
CREATE TABLE exposure (
    ts_id INT REFERENCES timestamps(id),
    bench_id INT REFERENCES benches(id),
    exposed BOOLEAN NOT NULL,
    location GEOGRAPHY(POINT, 4326),
    PRIMARY KEY (ts_id, bench_id)
);
SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => INTERVAL '1 month');
CREATE INDEX exposure_bench_ts_idx ON exposure (bench_id, ts_id DESC);
CREATE INDEX exposure_location_idx ON exposure USING GIST (location);

-- Digital Surface Model and Digital Elevation Model
-- (Loaded via raster2pgsql)
-- dsm_raster: 1m resolution surface model
-- dem_raster: ground elevation model
```

**Storage Estimates:**
- Initial dataset (200 benches, 1 year): 50-500 MB (compressed)
- Full dataset (1000 benches, 1 year): 1-2 GB
- DSM/DEM rasters for Graz: 500 MB - 2 GB

**Performance Optimizations:**
- TimescaleDB compression for exposure table
- Spatial indexes on geography columns
- Partitioning by time (automatic with TimescaleDB)
- Connection pooling (pgBouncer)

### 2. REST API Service

**Technology Options:**

#### Option A: Python (FastAPI) - Recommended
```python
# Advantages:
# - Excellent PostgreSQL support (psycopg2/asyncpg)
# - Fast async performance
# - Built-in OpenAPI documentation
# - Same language as precomputation scripts
# - Type hints and validation (Pydantic)

from fastapi import FastAPI, Query
from typing import List, Optional
import asyncpg

app = FastAPI()

@app.get("/api/benches")
async def get_benches(
    lat: float,
    lon: float,
    radius: float = Query(1000, description="Radius in meters")
):
    # Returns benches within radius with current sun/shade status
    pass
```

#### Option B: Node.js (Express)
```javascript
// Advantages:
// - Lightweight and fast
// - Large ecosystem
// - Good real-time capabilities (if needed)

const express = require('express');
const { Pool } = require('pg');
const app = express();
```

**API Endpoints:**

```
GET  /api/benches
     Query params:
       - lat: float (required)
       - lon: float (required)
       - radius: float (optional, default: 1000m)
     Returns: List of benches with current sun/shade status
     
     Response example:
     {
       "benches": [
         {
           "id": 1,
           "osm_id": 123456789,
           "location": {"lat": 47.07, "lon": 15.44},
           "distance": 245,
           "current_status": "sunny",
           "sun_until": "2025-12-11T16:53:00Z",
           "remaining_minutes": 194
         }
       ]
     }

GET  /api/benches/{id}
     Returns: Detailed bench information
     
     Response example:
     {
       "id": 1,
       "osm_id": 123456789,
       "location": {"lat": 47.07, "lon": 15.44},
       "elevation": 356.2,
       "current_status": "sunny",
       "sun_until": "2025-12-11T16:53:00Z",
       "remaining_minutes": 194,
       "weather": {
         "cloud_cover": 20,
         "conditions": "partly cloudy"
       }
     }

GET  /api/benches/{id}/exposure
     Query params:
       - from: ISO timestamp (optional, default: now)
       - to: ISO timestamp (optional, default: now + 24h)
     Returns: Sun exposure timeline for visualization
     
     Response example:
     {
       "bench_id": 1,
       "intervals": [
         {"timestamp": "2025-12-11T14:00:00Z", "exposed": true},
         {"timestamp": "2025-12-11T14:10:00Z", "exposed": true},
         {"timestamp": "2025-12-11T14:20:00Z", "exposed": false}
       ]
     }

GET  /api/health
     Returns: API health status
     
     Response example:
     {
       "status": "healthy",
       "database": "connected",
       "timestamp": "2025-12-11T14:30:00Z"
     }
```

**Weather Integration:**

```python
# Cache weather data to reduce API calls
import aiohttp
from datetime import datetime, timedelta

WEATHER_CACHE_TTL = 600  # 10 minutes

async def fetch_weather():
    """Fetch current weather from GeoSphere Austria API"""
    # API: https://dataset.api.hub.geosphere.at/
    # Endpoint: Current observations for Graz
    async with aiohttp.ClientSession() as session:
        async with session.get(GEOSPHERE_API_URL) as resp:
            data = await resp.json()
            return {
                'cloud_cover': data['cloud_cover_percent'],
                'conditions': data['weather_condition'],
                'timestamp': datetime.now()
            }
```

### 3. Reverse Proxy / Load Balancer

**Using Traefik (Existing VPS Setup)**

Traefik provides dynamic routing, automatic HTTPS via Let's Encrypt, and excellent Docker integration.

**Docker Compose Configuration with Traefik Labels:**

```yaml
services:
  api:
    build: ./backend
    networks:
      - traefik  # Your existing Traefik network
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonnenbankerl-api.rule=Host(`api.sonnenbankerl.com`)"
      - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
      
      # Rate limiting middleware
      - "traefik.http.middlewares.api-ratelimit.ratelimit.average=100"
      - "traefik.http.middlewares.api-ratelimit.ratelimit.burst=50"
      - "traefik.http.routers.sonnenbankerl-api.middlewares=api-ratelimit"
      
      # CORS headers
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowmethods=GET,OPTIONS,POST"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolalloworigin=*"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowheaders=Content-Type,Authorization"

networks:
  traefik:
    external: true  # Your existing Traefik network
  internal:
    internal: true
```

**Key Traefik Features:**
- **Dynamic Configuration:** Routes defined via Docker labels
- **Automatic SSL:** Let's Encrypt certificates auto-renewed
- **Rate Limiting:** Built-in middleware for API protection
- **Load Balancing:** Automatic distribution across replicas
- **Health Checks:** Monitors service availability

### 4. Precomputation Service

**Python Script Structure:**

```python
# precompute_exposure.py
import psycopg2
from multiprocessing import Pool, cpu_count
from datetime import datetime, timedelta
import argparse

def compute_bench_exposure(bench_id, year):
    """
    Compute sun exposure for a single bench across all timestamps
    Uses line-of-sight algorithm with DSM data
    """
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    # Get bench data
    cur.execute("SELECT id, geom, elevation FROM benches WHERE id = %s", (bench_id,))
    bench = cur.fetchone()
    
    # Get all timestamps for the year
    cur.execute("""
        SELECT ts.id, sp.azimuth_deg, sp.elevation_deg
        FROM timestamps ts
        JOIN sun_positions sp ON sp.ts_id = ts.id
        WHERE EXTRACT(YEAR FROM ts.ts) = %s
    """, (year,))
    
    timestamps = cur.fetchall()
    
    for ts_id, azimuth, elevation in timestamps:
        # Check line-of-sight to sun
        exposed = check_line_of_sight(bench['geom'], bench['elevation'], 
                                     azimuth, elevation, 'dsm_raster')
        
        # Insert result
        cur.execute("""
            INSERT INTO exposure (ts_id, bench_id, exposed, location)
            VALUES (%s, %s, %s, %s)
        """, (ts_id, bench_id, exposed, bench['geom']))
    
    conn.commit()
    conn.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--year', type=int, required=True)
    parser.add_argument('--parallel', type=int, default=cpu_count())
    args = parser.parse_args()
    
    # Get all bench IDs
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    cur.execute("SELECT id FROM benches")
    bench_ids = [row[0] for row in cur.fetchall()]
    conn.close()
    
    # Process in parallel
    with Pool(args.parallel) as pool:
        pool.starmap(compute_bench_exposure, 
                    [(bid, args.year) for bid in bench_ids])

if __name__ == '__main__':
    main()
```

**Cron Schedule:**
```bash
# Run incremental update every 6 months
0 0 1 1,7 * cd /opt/sonnenbankerl && python precompute_exposure.py --year $(date +\%Y) --incremental

# Cleanup old data (older than 1 year)
0 1 1 * * psql -d sonnenbankerl -c "SELECT drop_chunks('exposure', INTERVAL '1 year');"
```

### 5. Deployment Options

#### Option 1: Docker Compose (Recommended)

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  postgres:
    image: timescale/timescaledb-ha:pg14-latest
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: sonnenbankerl
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"
    restart: unless-stopped
    
  api:
    build: ./backend
    depends_on:
      - postgres
    environment:
      DATABASE_URL: postgres://postgres:${DB_PASSWORD}@postgres/sonnenbankerl
      GEOSPHERE_API_KEY: ${GEOSPHERE_API_KEY}
    networks:
      - traefik
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonnenbankerl-api.rule=Host(`api.sonnenbankerl.com`)"
      - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
    restart: unless-stopped

networks:
  traefik:
    external: true  # Use your existing Traefik network
  internal:
    internal: true

volumes:
  pgdata:
```

#### Option 2: Systemd Services

Manual installation with systemd service management.

**api.service:**
```ini
[Unit]
Description=Sonnenbankerl API Service
After=network.target postgresql.service

[Service]
Type=simple
User=sonnenbankerl
WorkingDirectory=/opt/sonnenbankerl/api
Environment="DATABASE_URL=postgres://user:pass@localhost/sonnenbankerl"
ExecStart=/usr/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

## VPS Requirements

### Minimum Specifications
- **CPU**: 4 cores (for parallel precomputation)
- **RAM**: 8 GB (PostgreSQL + PostGIS + API service)
- **Storage**: 50 GB SSD
- **Bandwidth**: 1-2 TB/month

### Recommended Specifications
- **CPU**: 6-8 cores
- **RAM**: 16 GB
- **Storage**: 100 GB SSD
- **Bandwidth**: 2-5 TB/month
- **Operating System**: Ubuntu 22.04 LTS or Debian 12

### Popular VPS Providers
- **Hetzner**: Excellent price/performance ratio in Europe
- **DigitalOcean**: Easy setup, good documentation
- **Linode**: Reliable, good support
- **Vultr**: Competitive pricing

## Security Considerations

### Database Security
- PostgreSQL listens only on localhost (127.0.0.1)
- Strong passwords with environment variables
- Regular automated backups
- Encrypted backups storage

### API Security
- Rate limiting per IP address (100 requests/minute)
- CORS configuration for Flutter app domains
- Input validation and sanitization
- Optional API key authentication
- SQL injection prevention (parameterized queries)

### Server Security
```bash
# Firewall configuration (ufw)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Install fail2ban for SSH protection
sudo apt install fail2ban

# Automatic security updates
sudo apt install unattended-upgrades
```

### SSL/TLS
- Automatic certificate management with Traefik
- Or use Certbot with nginx
- HTTPS only (redirect HTTP to HTTPS)
- HSTS headers enabled

## Monitoring & Maintenance

### Logging Strategy
```bash
# Application logs location
/var/log/sonnenbankerl/
  ├── api.log           # API access and errors
  ├── precompute.log    # Precomputation job logs
  └── cron.log          # Scheduled task logs

# Traefik logs
/var/log/traefik/
  └── access.log        # Access logs with rate limiting info

# PostgreSQL logs
/var/log/postgresql/
  └── postgresql-14-main.log
```

### Database Monitoring
```sql
-- Enable pg_stat_statements for query analysis
CREATE EXTENSION pg_stat_statements;

-- Monitor slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- queries slower than 100ms
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Backup Strategy
```bash
# Daily PostgreSQL backup script
#!/bin/bash
# /opt/sonnenbankerl/backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/postgresql"
DB_NAME="sonnenbankerl"

# Create backup
pg_dump -U postgres -d $DB_NAME | gzip > "$BACKUP_DIR/db_$DATE.sql.gz"

# Keep only last 30 days
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +30 -delete

# Upload to remote storage (optional)
# rclone copy "$BACKUP_DIR/db_$DATE.sql.gz" remote:backups/
```

**Crontab entry:**
```bash
# Daily backup at 2 AM
0 2 * * * /opt/sonnenbankerl/backup.sh >> /var/log/sonnenbankerl/backup.log 2>&1
```

### Health Checks
```bash
# Simple uptime monitoring script
#!/bin/bash
# /opt/sonnenbankerl/healthcheck.sh

API_URL="https://api.sonnenbankerl.com/api/health"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL)

if [ $RESPONSE -ne 200 ]; then
    echo "API health check failed: HTTP $RESPONSE"
    # Send alert (email, SMS, etc.)
    # systemctl restart api.service
fi
```

**Crontab entry:**
```bash
# Check every 5 minutes
*/5 * * * * /opt/sonnenbankerl/healthcheck.sh
```

### Optional: Prometheus + Grafana
For advanced monitoring and visualization:
- API request rates and latency
- Database connection pool stats
- System resources (CPU, RAM, disk)
- Custom alerts

## Scaling Considerations

### Current Architecture (Single VPS)
Suitable for:
- Up to 10,000 active users
- ~100 requests/second
- Single region (Austria/Central Europe)

### Future Scaling Options

**Horizontal Scaling:**
- Multiple API instances behind load balancer
- Read replicas for PostgreSQL
- Redis cache layer for frequent queries

**Vertical Scaling:**
- Upgrade VPS resources as needed
- TimescaleDB handles large datasets efficiently

**CDN Integration:**
- Cache static bench data at edge locations
- Reduce API server load

**Database Optimization:**
- Materialized views for common queries
- Additional spatial indexes
- Query result caching (Redis)

## Development Workflow

### Local Development Setup
```bash
# Clone repository
git clone <repository-url>
cd sonnenbankerl

# Start services with Docker Compose
docker-compose -f docker-compose.dev.yml up

# Run migrations
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f migrations/001_initial.sql

# Import test data
python scripts/import_test_benches.py
```

### Deployment Process
```bash
# 1. SSH into VPS
ssh user@your-vps-ip

# 2. Pull latest changes
cd /opt/sonnenbankerl
git pull origin main

# 3. Rebuild and restart services
docker-compose build
docker-compose up -d

# 4. Run migrations if needed
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f migrations/002_new_feature.sql

# 5. Check logs
docker-compose logs -f api
```

## Cost Estimation

### Monthly VPS Costs (Hetzner Example)
- **CX31** (4 cores, 8GB RAM, 80GB SSD): ~7 EUR/month
- **CX41** (8 cores, 16GB RAM, 160GB SSD): ~14 EUR/month

### Additional Costs
- Domain name: ~10-15 EUR/year
- GeoSphere API: Free for non-commercial use
- Backup storage (optional): 2-5 EUR/month

**Total estimated monthly cost: 7-20 EUR**

## Next Steps

1. **Choose VPS provider and provision server**
2. **Register domain name** (e.g., api.sonnenbankerl.com)
3. **Set up PostgreSQL with extensions** (PostGIS, TimescaleDB)
4. **Import OSM bench data and DSM/DEM rasters**
5. **Develop REST API service** (FastAPI recommended)
6. **Configure Traefik labels** (for automatic HTTPS routing)
7. **Run initial precomputation** (may take several days)
8. **Set up monitoring and backups**
9. **Deploy and test API**
10. **Integrate with Flutter mobile app**

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PostGIS Documentation](https://postgis.net/docs/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [GeoSphere Austria API](https://dataset.api.hub.geosphere.at/)
