# Sonnenbankerl

A mobile application for finding park benches with optimal sun exposure in Graz, Austria.

## Overview

Sonnenbankerl (Sun Bench) is a Flutter-based mobile map application that helps users find park benches and view their current and predicted sun exposure. The app combines real-time weather data, sun position calculations, and terrain modeling to provide accurate information about which benches are currently sunny.

## Features

- **Interactive Map**: Minimal basemap displaying park benches with clear, distinguishable symbols
- **User Location**: Shows your current position on the map
- **Sun Exposure Information**: View current sun status for each bench
- **Detailed Bench Information**: 
  - Total sun duration throughout the day
  - Next time the bench will be in the sun
  - Current weather conditions
- **Real-time Updates**: Sun exposure status is pre-calculated on the server and updated based on current weather

## Technical Architecture

### Frontend
- **Framework**: Flutter
- **Platform**: Mobile (iOS/Android)
- **Map Display**: Interactive map showing benches and user location

### Data Sources

#### OpenStreetMap (OSM)
- Source of park bench locations within Graz
- Data stored in database for efficient querying

#### Weather Data
- **Provider**: GeoSphere Austria API
- **Scope**: Weather data for Graz region
- **Usage**: Real-time weather conditions affecting sun exposure

#### Terrain Model
- **Resolution**: 1m/10m Digital Height Model (DHM)
- **Purpose**: Shadow calculation considering terrain and buildings

### Backend Processing
- **Sun Position Calculation**: Pre-computed sun positions throughout the year (constant astronomical data)
- **Shadow Modeling**: GIS-based shadow calculations using terrain model
- **Cloud Processing**: Server-side computation of sun exposure status before app requests

## Scope

- **Geographic Area**: Graz, Austria
- **Distance Calculation**: Straight-line (aerial) distance from user to benches

## Project Status

This is a proposal for a location-based services course project (VU_LBS, Winter 2025).

## Data Requirements

1. OSM data for all park benches in Graz
2. Sun position and shadow calculation system (potentially GIS-based)
3. Digital Height Model (DHM) at 1m or 10m resolution
4. Weather API integration (GeoSphere Austria)

## Development Notes

- Dynamic elements: Weather conditions (clouds, precipitation)
- Static elements: Sun position (predictable), terrain model
- Backend must pre-calculate sun exposure to ensure instant display when app opens
- APIs will be used extensively for weather and geographic data

## License

TBD

## Contributors

TBD
