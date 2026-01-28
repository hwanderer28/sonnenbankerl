import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/bench.dart';
import '../models/weather_status.dart';

class ApiService {
  static const bool simulateOffline = false;  //Um Server Offline zu simulieren hier true eintragen
  static const String baseUrl = 'https://sonnenbankerl-api.ideanexus.cloud';

  Future<bool> checkServerHealth() async {
    if (simulateOffline) return false;

    try {
      final response = await http.get(Uri.parse('$baseUrl/api/health'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'healthy';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Bench>> getBenches({
    required double lat,
    required double lon,
    double radius = 4000,
  }) async {
    if (simulateOffline) return [];

    final uri = Uri.parse('$baseUrl/api/benches').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radius.toString(),
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load benches: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final benchesJson = (data['benches'] as List<dynamic>?) ?? [];
    return benchesJson
        .map((e) => Bench.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Bench> getBenchDetails(int benchId) async {
    if (simulateOffline) throw Exception('Offline simulated');

    final resp = await http.get(Uri.parse('$baseUrl/api/benches/$benchId'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load bench details: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Bench.fromJson(data);
  }

  // ✅ NEW: Sunshine Gate
  Future<WeatherCurrentResponse> getCurrentSunshineStatus({bool refresh = false}) async {
    if (simulateOffline) {
      throw Exception('Offline simulated');
    }

    final uri = Uri.parse('$baseUrl/api/weather/current').replace(
      queryParameters: {'refresh': refresh.toString()},
    );

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load weather status: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return WeatherCurrentResponse.fromJson(data);
  }
}
