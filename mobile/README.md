# Sonnenbankerl Mobile App

Flutter-based mobile application for finding sunny park benches in Graz, Austria.

## Overview

The Sonnenbankerl mobile app provides an intuitive interface for users to discover park benches with optimal sun exposure. The app features an interactive map with real-time sun/shade indicators and detailed bench information.

## Features

- **Interactive Map**: MapLibre GL-based map showing bench locations
- **Real-time Sun Status**: Visual indicators (yellow for sunny, blue for shady benches)
- **Bench Details**: Tap any bench to see remaining sun exposure or next sunny period
- **Favorites**: Save favorite benches for quick access
- **Handedness Support**: UI adapts to left/right-handed users
- **Welcome Screen**: First-run introduction to app features
- **Settings**: Customize app behavior and preferences

## Architecture

```
mobile/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/                   # Data models
│   │   ├── bench.dart
│   │   ├── bench_info.dart
│   │   └── weather_status.dart
│   ├── screens/                  # UI screens
│   │   ├── bench_map.dart
│   │   ├── settings_sheet.dart
│   │   └── welcome_screen.dart
│   ├── services/                 # API and business logic
│   │   ├── api_service.dart
│   │   └── favorites_service.dart
│   └── theme/                    # App theming
│       └── app_theme.dart
└── assets/                       # Images and resources
```

## Key Dependencies

- **maplibre_gl** (^0.21.0): Interactive map rendering
- **dio** (^5.4.0): HTTP client for API communication
- **http** (^1.1.0): Additional HTTP support
- **shared_preferences** (^2.2.3): Local data persistence
- **flutter_phoenix** (^1.1.1): App restart functionality
- **latlong2** (^0.9.0): Coordinate handling
- **flutter_svg** (^2.0.7): SVG rendering

## API Integration

The app connects to the Sonnenbankerl backend API:

**Production API**: `https://sonnenbankerl-api.ideanexus.cloud`

**Key Endpoints**:
- `GET /api/benches?lat={lat}&lon={lon}&radius={radius}` - Search benches
- `GET /api/benches/{id}` - Get bench details with sun exposure
- `GET /api/weather/current` - Current weather conditions

For complete API documentation, visit: https://sonnenbankerl-api.ideanexus.cloud/docs

## Getting Started

### Prerequisites

- Flutter SDK ^3.10.1
- Android Studio / Xcode for platform-specific builds
- Connected device or emulator

### Installation

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Run the app:
   ```bash
   # Development mode
   flutter run

   # Release build (Android)
   flutter build apk --release

   # Release build (iOS)
   flutter build ios --release
   ```

### Development

The app uses a clean architecture pattern:

1. **Models** define data structures for benches, weather, and UI state
2. **Services** handle API communication and data persistence
3. **Screens** implement UI components and user interactions
4. **Theme** provides consistent styling across the app

## Configuration

API endpoint configuration is managed in `lib/services/api_service.dart`. For local development, update the base URL to point to your local backend instance.

## Platform Support

- ✅ Android
- ✅ iOS
- ⚠️ Web (partial support)
- ⚠️ Desktop (Linux, macOS, Windows - experimental)

## Contributing

This app is part of the Sonnenbankerl project. See the main [project README](../README.md) for more information.

## License

TBD
