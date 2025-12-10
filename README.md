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

## Features

### Interactive Map
- Subtle OpenStreetMap humanitarian layer background
- Real-time user location tracking
- Visual bench indicators (yellow for sunny, dark blue for shady)

### Smart Bench Analysis
- **Sunny benches**: Display remaining sun exposure time
  ```
  until 16:53 | 3 hours 14 min
  ```
- **Shady benches**: Predict next sunny period based on sun position, terrain obstacles, and weather forecasts
  ```
  next estimated sunlight: 14.12.2025 10:12 | in 2 days 3 hours 14 min
  ```

### Real-time Data
- Server-side pre-calculated sun exposure profiles
- Live weather integration for accurate predictions

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
- **Dataset**: Binary sun exposure (sunny/shady) at 10-minute intervals
- **Coverage**: ~200-1000 benches, annual pre-calculation
- **Algorithm**: Sun position calculations (suncalc_postgres) + line-of-sight checks against 1m DSM
- **Bench Height**: DEM + 1.2m (upper body/head level)
- **Storage**: Compressed time-series profiles in TimescaleDB hypertables
- **Processing**: Python parallelization for batch computation
- **Updates**: Incremental recomputation every 6 months; automatic cleanup of data >1 year old

📄 [Detailed pipeline documentation](docs/sunshine_calculation_pipeline.md)

#### Real-time Integration
- Pre-computed sun/terrain data combined with live weather API
- Fast query performance via pre-calculated profiles
- Instant predictions without on-the-fly calculations

## Documentation

- [Resources & References](docs/resources.md) - Tools, data sources, APIs, and documentation
- [Sunshine Calculation Pipeline](docs/sunshine_calculation_pipeline.md) - Detailed precomputation workflow

## License

TBD

---

<div align="center">
  Made with ☀️ in Graz
</div>
