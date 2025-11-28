# Sonnenbankerl

A mobile application for finding park benches with optimal sun exposure in Graz, Austria.

## Overview

Sonnenbankerl (Sun Bench) is a minimal Flutter-based mobile map application that helps users find park benches with optimal sun exposure in Graz, Austria. The app features a subtle OpenStreetMap humanitarian layer as background, displaying benches with clear symbols: yellowish for sunny benches and dark-blueish for shady ones. Tapping a sunny bench shows remaining sun exposure time, while tapping a shady bench predicts the next sunny period, accounting for sun position, terrain obstacles, and weather forecasts.

## Features

- **Minimal Interactive Map**: Subtle OpenStreetMap humanitarian layer background with park benches displayed as yellowish symbols (sunny) or dark-blueish symbols (shady)
- **User Location**: Shows your current position on the map
- **Bench Interactions**:
  - Tap sunny bench: Display remaining sun exposure time (e.g., "until 16:53 | 3 hours 14 min")
  - Tap shady bench: Show prediction for next sunny period, factoring in sun position, elevation model obstacles, and weather forecast
- **Real-time Updates**: Sun exposure status pre-calculated on server, updated with current weather

## Technical Architecture

### Frontend
- **Framework**: Flutter
- **Platform**: Mobile (iOS/Android)
- **Map Display**: Minimal interactive map with OpenStreetMap humanitarian layer, bench symbols (yellowish for sunny, dark-blueish for shady), and tap interactions for sun exposure details

### Data Sources

#### OpenStreetMap (OSM)
- Source of park bench locations within Graz
- Data stored in database for efficient querying

#### Weather Data
- **Provider**: GeoSphere Austria API
- **Scope**: Weather data for Graz region
- **Usage**: Real-time weather conditions affecting sun exposure

#### Terrain Model
- **Digital Surface Model (DSM)**: 1m/10m resolution including buildings and vegetation
- **Digital Elevation Model (DEM)**: Ground elevation for bench heights
- **Purpose**: DSM for shadow calculations; benches draped to DEM for accurate ground positioning

### Backend Processing
- **Database**: PostgreSQL with PostGIS extension for geospatial data and calculations
- **Precomputation**: Sun positions and shadow modeling pre-calculated for each bench using DEM-derived z-coordinates and Digital Surface Model (DSM); stored as sun exposure profiles in database
- **Calculations**: Defined as SQL queries/stored procedures in PostGIS for spatial operations, sun position formulas, and line-of-sight checks; complex shadows handled via external scripts if needed
- **Real-time Integration**: App pairs precomputed data with live weather API for current exposure status and predictions
- **Updates**: Recomputation pipeline for new user-added benches or data changes

## Scope

- **Geographic Area**: Graz, Austria
- **Distance Calculation**: Straight-line (aerial) distance from user to benches

## Project Status

This is a proposal for a location-based services course project (VU_LBS, Winter 2025).

## Data Requirements

1. OSM data for all park benches in Graz (draped to DEM for ground elevation z-coordinates)
2. Digital Surface Model (DSM) at 1m or 10m resolution for shadow calculations (including buildings and vegetation)
3. Digital Elevation Model (DEM) for accurate bench ground heights
4. Weather API integration (GeoSphere Austria) for real-time conditions
5. PostgreSQL with PostGIS for geospatial storage and SQL-based calculations

## Development Notes

- **Precomputation Strategy**: Sun exposure profiles pre-calculated and stored in PostGIS database for fast queries; recomputation triggered for new benches or data updates
- **Dynamic vs. Static**: Weather (dynamic, via API) paired with precomputed sun/DSM data (static)
- **User Contributions**: Design supports user-added benches with elevation data, integrated into recomputation pipeline
- **Performance**: Instant app display via precalculated data; predictions simplified by stored profiles
- **APIs**: Weather and geographic data; PostGIS handles spatial calculations

## License

TBD

## Contributors

TBD
