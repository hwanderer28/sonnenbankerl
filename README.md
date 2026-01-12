<div align="center">
  <img src="assets/Sonnenbankerl_Icon.png" alt="Sonnenbankerl" width="200"/>
  
  # Sonnenbankerl
  
  **Find the perfect sunny bench in Graz**
  
  A mobile application for locating park benches with optimal sun exposure
  
  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)](https://flutter.dev)
  [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=flat&logo=postgresql&logoColor=white)](https://www.postgresql.org)
  [![PostGIS](https://img.shields.io/badge/PostGIS-4169E1?style=flat&logo=postgis&logoColor=white)](https://postgis.net)
  [![OpenStreetMap](https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat&logo=openstreetmap&logoColor=white)](https://www.openstreetmap.org)

  ---
</div>

## About

Sonnenbankerl (Sun Bench) is a minimal Flutter-based mobile map application that helps users find park benches with optimal sun exposure in Graz, Austria. 

### Motivation

Existing sunlight analysis tools like [Shadowmap](https://shadowmap.org) provide sophisticated 3D solar simulations serving photographers, architects, urban planners, and real estate professionals. These "Swiss Army knife" solutions offer powerful features—solar irradiance mapping, custom 3D model uploads, drone shot planning—but require technical understanding and intentional exploration of complex interfaces.

Sonnenbankerl exists for a fundamentally different moment: you want to leave your house and sit somewhere sunny. Right now. No sliders, no learning curve, no professional analysis—just open the app, see which benches are sunny (yellow) or shady (blue), tap one, and know exactly how long you can enjoy the sun or when it will arrive. Simple, fast, beautiful.

The app displays benches with clear visual indicators: yellowish for sunny benches and dark-blueish for shady ones. Tapping a sunny bench shows remaining sun exposure time, while tapping a shady bench predicts the next sunny period, accounting for sun position, terrain obstacles, and weather forecasts.

## Project Status

### ✅ Backend - DEPLOYED & LIVE
- **API URL**: https://sonnenbankerl.ideanexus.cloud
- **Status**: Production, fully operational
- **Database**: PostgreSQL 14 + PostGIS + TimescaleDB
- **Data**: Empty by default; load via precomputation pipeline
- **Endpoints**: Health check, benches search, bench details
- **Documentation**: https://sonnenbankerl.ideanexus.cloud/docs

### 🚧 In Progress
- Mobile app development (Flutter)

### 📋 Planned
- Real OSM bench data import
- GeoSphere Austria weather API integration
- Actual sun position calculations (suncalc)
- Line-of-sight algorithm with DSM data
- Precomputation pipeline

## Features

### Interactive Map (Planned)
- Subtle OpenStreetMap humanitarian layer background
- Real-time user location tracking
- Visual bench indicators (yellow for sunny, dark blue for shady)

### Smart Bench Analysis (Minimal Implementation)
- **Sunny benches**: Display remaining sun exposure time
  ```
  until 16:53 | 3 hours 14 min
  ```
- **Shady benches**: Predict next sunny period
  ```
  next estimated sunlight: 14.12.2025 10:12 | in 2 days 3 hours 14 min
  ```

### Backend API (Live)
- **URL**: https://sonnenbankerl.ideanexus.cloud
- **Docs**: https://sonnenbankerl.ideanexus.cloud/docs
- REST API for bench locations and sun exposure data

## Technical Stack

### Frontend
| Component | Technology |
|-----------|-----------|
| Framework | Flutter |
| Platform  | iOS / Android |
| Map Layer | OpenStreetMap (Humanitarian) |

### Data Sources
| Source | Purpose | Details |
|--------|---------|---------|
| **OpenStreetMap** | Bench locations | Park benches within Graz |
| **GeoSphere Austria** | Weather data | Real-time conditions for Graz region |
| **DSM (1m/10m)** | Shadow calculations | Buildings and vegetation obstacles |
| **DEM** | Ground elevation | Accurate bench positioning |

### Backend Architecture

```
PostgreSQL + PostGIS + TimescaleDB
├── Geospatial data management
├── Time-series sun exposure profiles
└── Custom PL/pgSQL spatial functions
```

#### Precomputation Pipeline

The system uses a **weekly rolling computation** approach:

- **Dataset**: Binary sun exposure (sunny/shady) at 10-minute intervals
- **Coverage**: Current week only (rolling 7-day window)
- **Algorithm**: Sun position calculations (suncalc_postgres) + line-of-sight checks against 1m DSM
- **Bench Height**: DEM + 1.2m (upper body/head level)
- **Storage**: TimescaleDB hypertables for time-series efficiency
- **Processing**: Adaptive parallelization based on available hardware
- **Updates**: Manual on-demand (run `./compute_next_week.sh` or execute SQL scripts)

**Key Features:**
- ✅ Pure PostgreSQL (no external Python scripts)
- ✅ Adaptive performance (auto-detects CPU cores and memory)
- ✅ 15-30 minute computation (vs hours/days for full year)
- ✅ Optimized line-of-sight with pre-computed trigonometric values

📄 [Precomputation Pipeline](../docs/sunshine_calculation_pipeline.md)

#### Real-time Integration
- Pre-computed sun/terrain data combined with live weather API
- Fast query performance via pre-calculated profiles
- Instant predictions without on-the-fly calculations

## Quick Start

### 🚀 Using the API (For Frontend Developers)

The backend API is **deployed and ready to use**:

**Base URL**: `https://sonnenbankerl.ideanexus.cloud`

**Quick Test:**
```bash
# Health check
curl https://sonnenbankerl.ideanexus.cloud/api/health

# Get benches near Graz Stadtpark (47.07°N, 15.44°E)
curl "https://sonnenbankerl.ideanexus.cloud/api/benches?lat=47.07&lon=15.44&radius=1000"

# Get details for bench 1
curl https://sonnenbankerl.ideanexus.cloud/api/benches/1
```

**Interactive API Documentation:**
- Swagger UI: https://sonnenbankerl.ideanexus.cloud/docs
- Try all endpoints with live data
- See request/response schemas

**Available Data:**
- None by default; run the precomputation pipeline after loading OSM benches and rasters
- Supports distance-based spatial search and sun exposure lookups once data is computed

**For Flutter Integration:**
See [Mobile App Integration Guide](mobile/README.md) for complete examples.

### 🔧 Backend Development

For backend developers:
- [Backend Setup](backend/README.md) - API structure and development
- [Database Setup](database/README.md) - Schema and migrations
- [Deployment Guide](docs/DEPLOYMENT.md) - VPS deployment steps

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md) - **START HERE** for deployment
- [Precomputation Pipeline](docs/sunshine_calculation_pipeline.md) - Weekly computation workflow
- [Backend API](backend/README.md) - API endpoints and usage
- [Database Schema](database/README.md) - Database structure and migrations
- [Backend Architecture](docs/architecture.md) - Infrastructure and design
- [Resources & References](docs/resources.md) - Tools, data sources, APIs

## License

TBD

---

<div align="center">
  Made with ☀️ in Graz
</div>
