# Sonnenbankerl API Integration Guide

Complete guide for integrating the Sonnenbankerl API into the Flutter mobile app.

## 🌐 API Overview

**Base URL**: `https://sonnenbankerl.ideanexus.cloud`

**Protocol**: HTTPS only
**Format**: JSON
**CORS**: Enabled for all origins

## 📡 Available Endpoints

### 1. Health Check

**Endpoint**: `GET /api/health`

**Purpose**: Check if API and database are operational

**Request:**
```bash
curl https://sonnenbankerl.ideanexus.cloud/api/health
```

**Response:**
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2025-12-30T16:18:08.607388"
}
```

**Fields:**
- `status`: `"healthy"` or `"unhealthy"`
- `database`: `"connected"` or `"disconnected"`
- `timestamp`: ISO 8601 timestamp (UTC)

---

### 2. Get Benches Near Location

**Endpoint**: `GET /api/benches`

**Purpose**: Find benches within a radius of a given location

**Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `lat` | float | Yes | - | Latitude (-90 to 90) |
| `lon` | float | Yes | - | Longitude (-180 to 180) |
| `radius` | float | No | 1000 | Search radius in meters (max: 10000) |

**Example Request:**
```bash
curl "https://sonnenbankerl.ideanexus.cloud/api/benches?lat=47.07&lon=15.44&radius=1000"
```

**Response:**
```json
{
  "benches": [
    {
      "id": 1,
      "osm_id": 1001,
      "name": "Stadtpark Bench 1",
      "location": {
        "lat": 47.0707,
        "lon": 15.4395
      },
      "elevation": 353.2,
      "distance": 86.59,
      "current_status": "sunny",
      "sun_until": "2025-12-30T18:00:00Z",
      "remaining_minutes": 210
    },
    {
      "id": 2,
      "osm_id": 1002,
      "name": "Stadtpark Bench 2",
      "location": {
        "lat": 47.0715,
        "lon": 15.4405
      },
      "elevation": 354.5,
      "distance": 171.03,
      "current_status": "shady",
      "sun_until": null,
      "remaining_minutes": null
    }
  ]
}
```

**Response Fields:**
- `id`: Unique bench identifier (integer)
- `osm_id`: OpenStreetMap ID (integer, nullable)
- `name`: Bench name (string, nullable)
- `location`: Geographic coordinates
  - `lat`: Latitude (float)
  - `lon`: Longitude (float)
- `elevation`: Elevation in meters (float, nullable)
- `distance`: Distance from query point in meters (float)
- `current_status`: Sun status - `"sunny"`, `"shady"`, or `"unknown"` (string)
- `sun_until`: Timestamp when sun status changes (ISO 8601, nullable)
- `remaining_minutes`: Minutes until sun status changes (integer, nullable)

**Empty Result:**
```json
{
  "benches": []
}
```

---

### 3. Get Bench Details

**Endpoint**: `GET /api/benches/{id}`

**Purpose**: Get detailed information about a specific bench

**Path Parameters:**
- `id`: Bench ID (integer)

**Example Request:**
```bash
curl https://sonnenbankerl.ideanexus.cloud/api/benches/1
```

**Response:**
```json
{
  "id": 1,
  "osm_id": 1001,
  "name": "Stadtpark Bench 1",
  "location": {
    "lat": 47.0707,
    "lon": 15.4395
  },
  "elevation": 353.2,
  "current_status": "sunny",
  "sun_until": "2025-12-30T18:00:00Z",
  "remaining_minutes": 210,
  "created_at": "2025-12-30T16:16:12.473628Z"
}
```

**Error Response (404):**
```json
{
  "detail": "Bench not found"
}
```

---

## 📱 Flutter Integration

### Setup

Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.1.0
  # Or use dio for more features:
  dio: ^5.4.0
```

### API Service Class

Create `lib/services/api_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://sonnenbankerl.ideanexus.cloud';
  
  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'healthy';
      }
      return false;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }
  
  // Get benches near location
  Future<List<Bench>> getBenches({
    required double lat,
    required double lon,
    double radius = 1000,
  }) async {
    final uri = Uri.parse('$baseUrl/api/benches').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radius.toString(),
      },
    );
    
    final response = await http.get(uri);
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['benches'] as List)
          .map((json) => Bench.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load benches: ${response.statusCode}');
    }
  }
  
  // Get bench details
  Future<Bench> getBenchDetails(int benchId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/benches/$benchId'),
    );
    
    if (response.statusCode == 200) {
      return Bench.fromJson(json.decode(response.body));
    } else if (response.statusCode == 404) {
      throw Exception('Bench not found');
    } else {
      throw Exception('Failed to load bench: ${response.statusCode}');
    }
  }
}
```

### Model Classes

Create `lib/models/bench.dart`:

```dart
class Location {
  final double lat;
  final double lon;
  
  Location({required this.lat, required this.lon});
  
  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      lat: json['lat'].toDouble(),
      lon: json['lon'].toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
  };
}

class Bench {
  final int id;
  final int? osmId;
  final String? name;
  final Location location;
  final double? elevation;
  final double? distance;
  final String currentStatus;
  final DateTime? sunUntil;
  final int? remainingMinutes;
  final DateTime? createdAt;
  
  Bench({
    required this.id,
    this.osmId,
    this.name,
    required this.location,
    this.elevation,
    this.distance,
    required this.currentStatus,
    this.sunUntil,
    this.remainingMinutes,
    this.createdAt,
  });
  
  factory Bench.fromJson(Map<String, dynamic> json) {
    return Bench(
      id: json['id'],
      osmId: json['osm_id'],
      name: json['name'],
      location: Location.fromJson(json['location']),
      elevation: json['elevation']?.toDouble(),
      distance: json['distance']?.toDouble(),
      currentStatus: json['current_status'],
      sunUntil: json['sun_until'] != null 
          ? DateTime.parse(json['sun_until']) 
          : null,
      remainingMinutes: json['remaining_minutes'],
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }
  
  bool get isSunny => currentStatus == 'sunny';
  bool get isShady => currentStatus == 'shady';
  bool get isUnknown => currentStatus == 'unknown';
  
  String get displayName => name ?? 'Bench #$id';
}
```

### Usage Example

```dart
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'models/bench.dart';

class BenchListScreen extends StatefulWidget {
  @override
  _BenchListScreenState createState() => _BenchListScreenState();
}

class _BenchListScreenState extends State<BenchListScreen> {
  final ApiService _apiService = ApiService();
  List<Bench> _benches = [];
  bool _loading = true;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadBenches();
  }
  
  Future<void> _loadBenches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Get benches near Graz Stadtpark
      final benches = await _apiService.getBenches(
        lat: 47.07,
        lon: 15.44,
        radius: 1000,
      );
      
      setState(() {
        _benches = benches;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            ElevatedButton(
              onPressed: _loadBenches,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_benches.isEmpty) {
      return Center(child: Text('No benches found nearby'));
    }
    
    return ListView.builder(
      itemCount: _benches.length,
      itemBuilder: (context, index) {
        final bench = _benches[index];
        return ListTile(
          leading: Icon(
            bench.isSunny ? Icons.wb_sunny : Icons.cloud,
            color: bench.isSunny ? Colors.orange : Colors.grey,
          ),
          title: Text(bench.displayName),
          subtitle: Text(
            '${bench.distance?.toStringAsFixed(0)}m away - ${bench.currentStatus}',
          ),
          trailing: bench.remainingMinutes != null
              ? Text('${bench.remainingMinutes} min')
              : null,
          onTap: () {
            // Navigate to bench details
          },
        );
      },
    );
  }
}
```

---

## 🧪 Testing & Development

### Interactive API Testing

Use the Swagger UI for testing:
```
https://sonnenbankerl.ideanexus.cloud/docs
```

Features:
- Try all endpoints interactively
- See request/response schemas
- Test with different parameters
- No authentication needed (for now)

### Sample Test Coordinates

**Graz Stadtpark (has benches):**
- Latitude: `47.07`
- Longitude: `15.44`
- Radius: `1000` meters

**Vienna Stadtpark (no benches in sample data):**
- Latitude: `48.2082`
- Longitude: `16.3738`
- Expected: Empty result

### Error Handling

Always handle these scenarios:

1. **Network Errors**
   ```dart
   try {
     final benches = await apiService.getBenches(...);
   } catch (e) {
     // Show error message to user
   }
   ```

2. **Empty Results**
   ```dart
   if (benches.isEmpty) {
     // Show "no benches nearby" message
   }
   ```

3. **Invalid Coordinates**
   - Validate latitude: -90 to 90
   - Validate longitude: -180 to 180

4. **API Unavailable**
   ```dart
   final isHealthy = await apiService.checkHealth();
   if (!isHealthy) {
     // Show maintenance message
   }
   ```

---

## 📊 Current Data

**Sample benches (3 total):**

| ID | Name | Latitude | Longitude | Elevation |
|----|------|----------|-----------|-----------|
| 1 | Stadtpark Bench 1 | 47.0707 | 15.4395 | 353.2m |
| 2 | Stadtpark Bench 2 | 47.0715 | 15.4405 | 354.5m |
| 3 | Stadtpark Bench 3 | 47.0695 | 15.4385 | 352.8m |

**Location**: All benches are in Graz Stadtpark area

**Search Radius**: Use 1000m (1km) radius for best results

---

## 🔒 Security & Best Practices

### API Keys
Currently no authentication required. Will be added later if needed.

### Rate Limiting
No rate limiting currently implemented. Be respectful with request frequency.

### HTTPS Only
Always use `https://` - HTTP requests will fail.

### Caching
Consider caching bench data:
```dart
// Cache benches for 5 minutes
final cacheExpiry = Duration(minutes: 5);
```

### Location Permissions
Request location permissions before calling API:
```dart
import 'package:geolocator/geolocator.dart';

Future<Position> getCurrentLocation() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return await Geolocator.getCurrentPosition();
}
```

---

## 🐛 Troubleshooting

### Common Issues

**1. "Failed to load benches: 500"**
- Backend server error
- Check API health: `/api/health`
- Contact backend team

**2. Empty bench list when you expect results**
- Check coordinates are in Graz (47.07°N, 15.44°E)
- Increase search radius
- Sample data only has 3 benches in Stadtpark

**3. "current_status" is always "unknown"**
- Sample data has future timestamps
- Will be fixed with real-time data

**4. SSL Certificate errors**
- Ensure using `https://` not `http://`
- Let's Encrypt certificate is valid

### Debug Mode

Add logging to track API calls:

```dart
class ApiService {
  static const bool _debug = true;
  
  Future<List<Bench>> getBenches(...) async {
    if (_debug) {
      print('API Request: GET /api/benches?lat=$lat&lon=$lon&radius=$radius');
    }
    
    final response = await http.get(uri);
    
    if (_debug) {
      print('API Response: ${response.statusCode}');
      print('API Body: ${response.body}');
    }
    
    // ... rest of implementation
  }
}
```

---

## 📝 Future API Changes

**Planned additions:**
- Real OSM bench data (hundreds of benches)
- Real-time sun position calculation
- Weather integration
- Exposure timeline endpoint
- Push notifications for sun changes
- User favorites/bookmarks

**Breaking changes will be:**
- Documented in advance
- Versioned (`/api/v2/...`)
- Communicated to team

---

## 🔗 Related Documentation

- [Backend API README](../backend/README.md) - Backend architecture
- [Database Schema](../database/README.md) - Data structure
- [Deployment Guide](DEPLOYMENT.md) - Production deployment

---

## ❓ Support

**For API questions:**
- Check interactive docs: https://sonnenbankerl.ideanexus.cloud/docs
- Review this guide
- Contact backend team

**For Flutter integration help:**
- See usage examples above
- Check mobile app README
