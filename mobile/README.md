# Sonnenbankerl Mobile App

Flutter-based mobile application for iOS and Android.

## 🌐 Backend API Integration

The backend API is **deployed and ready to use**:

**Base URL**: `https://sonnenbankerl.ideanexus.cloud`

**API Documentation**: https://sonnenbankerl.ideanexus.cloud/docs

### Quick Start

See the complete [API Integration Guide](../docs/API_INTEGRATION.md) for:
- ✅ All available endpoints
- ✅ Request/response examples  
- ✅ Flutter service classes
- ✅ Model definitions
- ✅ Error handling
- ✅ Testing guidelines

### Quick Example

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

// Get benches near user location
Future<List<dynamic>> getBenches(double lat, double lon) async {
  final url = Uri.parse(
    'https://sonnenbankerl.ideanexus.cloud/api/benches'
  ).replace(queryParameters: {
    'lat': lat.toString(),
    'lon': lon.toString(),
    'radius': '1000',
  });
  
  final response = await http.get(url);
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['benches'];
  }
  throw Exception('Failed to load benches');
}
```

### Available Sample Data

Currently 3 benches in Graz Stadtpark:
- Coordinates: ~47.07°N, 15.44°E
- Use radius: 1000m for testing

**Test coordinates:**
```dart
// Graz Stadtpark (has benches)
final benches = await getBenches(47.07, 15.44);

// Should return 3 benches
```

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
