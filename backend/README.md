# Sonnenbankerl Backend API

FastAPI-based REST API service for the Sonnenbankerl application.

## Status: ✅ Deployed

- **Environment**: Production
- **URL**: https://sonnenbankerl-api.ideanexus.cloud (local: http://localhost:8000)
- **API Docs**: https://sonnenbankerl-api.ideanexus.cloud/docs
- **Database**: PostgreSQL 14 + PostGIS + TimescaleDB
- **Data**: 21 benches (Stadtpark subset) from `data/osm/graz_benches.geojson`; populate exposure via precomputation pipeline

## Project Structure

```
backend/
├── app/
│   ├── main.py                # FastAPI app entry point
│   ├── config.py              # Configuration management
│   ├── api/                   # API endpoint routes
│   │   ├── benches.py         # Bench-related endpoints
│   │   └── health.py          # Health check endpoint
│   ├── models/                # Pydantic models
│   │   └── bench.py           # Bench data models
│   ├── db/                    # Database layer
│   │   ├── connection.py      # PostgreSQL connection pool
│   │   └── queries.py         # SQL queries
│   └── services/              # Business logic
│       └── exposure.py        # Sun exposure calculations
├── requirements.txt           # Python dependencies
├── Dockerfile                 # Docker container definition
└── .dockerignore              # Docker build exclusions
```

## Technologies

- **Framework**: FastAPI 0.109.0
- **Python**: 3.11
- **Database**: PostgreSQL 14 with PostGIS and TimescaleDB extensions
- **Database Driver**: asyncpg (async PostgreSQL)
- **Validation**: Pydantic v2
- **Server**: Uvicorn with ASGI

## Dependencies

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
asyncpg==0.29.0
pydantic==2.5.3
pydantic-settings==2.1.0
python-dotenv==1.0.0
```

## API Endpoints

### Health Check

**GET `/api/health`**

Returns API and database health status.

**Response:**
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2025-12-30T15:30:00.123456"
}
```

### Get Benches Near Location

**GET `/api/benches`**

Query Parameters:
- `lat` (required): Latitude (-90 to 90)
- `lon` (required): Longitude (-180 to 180)
- `radius` (optional): Search radius in meters (default: 1000, max: 10000)

**Example:**
```bash
curl "https://sonnenbankerl-api.ideanexus.cloud/api/benches?lat=47.07&lon=15.44&radius=1000"
```

**Response:**
```json
{
  "benches": [
    {
      "id": 1,
      "osm_id": 1001,
      "name": "Stadtpark Bench 1",
      "location": {"lat": 47.0707, "lon": 15.4395},
      "elevation": 353.2,
      "distance": 245.3,
      "current_status": "sunny",
      "sun_until": "2025-12-30T18:00:00Z",
      "remaining_minutes": 210,
      "status_note": null
    }
  ],
  "window_start": "2025-12-30T00:00:00Z",
  "window_end": "2026-01-05T23:50:00Z"
}
```

### Get Bench Details

**GET `/api/benches/{id}`**

Path Parameters:
- `id`: Bench ID

**Example:**
```bash
curl "https://sonnenbankerl-api.ideanexus.cloud/api/benches/1"
```

**Response:**
```json
{
  "id": 1,
  "osm_id": 1001,
  "name": "Stadtpark Bench 1",
  "location": {"lat": 47.0707, "lon": 15.4395},
  "elevation": 353.2,
  "current_status": "sunny",
  "sun_until": "2025-12-30T18:00:00Z",
  "remaining_minutes": 210,
  "created_at": "2025-12-30T10:00:00Z"
}
```

### Interactive Documentation

**GET `/docs`**

Swagger UI with interactive API documentation and testing interface.

**GET `/redoc`**

ReDoc alternative documentation interface.

## Configuration

The API is configured via environment variables. See `.env.example` for all options.

**Key settings:**
- `DATABASE_URL`: PostgreSQL connection string
- `ENVIRONMENT`: production/development
- `ALLOWED_ORIGINS`: CORS allowed origins
- `API_PORT`: Server port (default: 8000)

## Database Schema

The API uses PostgreSQL with PostGIS and TimescaleDB extensions.

**Tables:**
- `benches`: Bench locations with spatial data (PostGIS)
- `timestamps`: 10-minute interval timestamps
- `sun_positions`: Precomputed sun azimuth/elevation
- `exposure`: TimescaleDB hypertable with sun exposure data

See `database/migrations/` for full schema.

## Current Notes

- Weather gate is temporarily skipped for local testing; re-enable when network/API access is stable.
- Exposure depends on the imported benches and computed exposure window (7 days, 10-minute resolution).
- Bench import currently uses a static insert list (21 benches); align SQL with the GeoJSON for future updates.

## Deployment

The backend is deployed via Docker Compose to VPS with Traefik.

See [Deployment Guide](../docs/DEPLOYMENT.md) for complete instructions.

**Quick deploy:**
```bash
cd infrastructure/docker
docker-compose up -d --build
```

## Monitoring

**View logs:**
```bash
docker-compose logs -f api
```

**Check health:**
```bash
curl https://sonnenbankerl-api.ideanexus.cloud/health
```

## Data refresh (local/CLI)
```bash
cd infrastructure/docker
psql -U postgres -d sonnenbankerl -c "TRUNCATE benches CASCADE; TRUNCATE sun_positions; TRUNCATE exposure; DELETE FROM timestamps WHERE ts >= CURRENT_DATE;"
psql -U postgres -d sonnenbankerl -f /precomputation/03_import_benches.sql   # imports 21 benches
psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql
psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql
psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"
```

## Documentation

- [Deployment Guide](../docs/DEPLOYMENT.md) - Step-by-step deployment
- [Architecture](../docs/architecture.md) - System design
- [Database Schema](../database/README.md) - Database structure
