# Sonnenbankerl Mobile App

Flutter-based mobile application for iOS and Android.

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart              # App entry point
│   ├── models/                # Data models (Bench, Exposure, etc.)
│   ├── services/              # API clients, location services
│   ├── screens/               # UI screens (Map, BenchDetail)
│   ├── widgets/               # Reusable UI components
│   └── config/                # App configuration
├── test/                      # Unit and widget tests
└── pubspec.yaml              # Dependencies
```

## Setup

### Prerequisites
- Flutter SDK 3.0+
- Dart 2.18+
- Android Studio / Xcode (for mobile development)

### Installation

```bash
# Navigate to mobile directory
cd mobile

# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run
```

## Features

- Interactive map with OpenStreetMap
- Real-time user location tracking
- Bench markers (yellow = sunny, blue = shady)
- Bench detail view with sun exposure predictions
- Integration with backend API

## Configuration

Update API endpoint in `lib/config/api_config.dart`:

```dart
const String API_BASE_URL = 'https://api.sonnenbankerl.com';
```

## Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

## Build for Production

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## Documentation

For detailed architecture and API integration, see:
- [Main README](../README.md)
- [Backend Architecture](../docs/architecture.md)
