class SunshineStatus {
  final bool isSunny;
  final int sunshineSeconds;
  final String stationId;
  final String stationName;
  final DateTime timestamp;
  final DateTime cachedAt;
  final String message;

  SunshineStatus({
    required this.isSunny,
    required this.sunshineSeconds,
    required this.stationId,
    required this.stationName,
    required this.timestamp,
    required this.cachedAt,
    required this.message,
  });

  factory SunshineStatus.fromJson(Map<String, dynamic> json) {
    return SunshineStatus(
      isSunny: (json['is_sunny'] as bool?) ?? false,
      sunshineSeconds: (json['sunshine_seconds'] as num?)?.toInt() ?? 0,
      stationId: json['station_id']?.toString() ?? '',
      stationName: json['station_name']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      cachedAt: DateTime.tryParse(json['cached_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      message: json['message']?.toString() ?? '',
    );
  }
}

class WeatherCurrentResponse {
  final SunshineStatus status;
  final bool cacheHit;

  WeatherCurrentResponse({
    required this.status,
    required this.cacheHit,
  });

  /// Unterstützt beide API-Formate:
  /// A) { status: {...}, cache_hit: true }
  /// B) { is_sunny: false, ..., cache_hit: true }  (flat)
  factory WeatherCurrentResponse.fromJson(Map<String, dynamic> json) {
    final bool cacheHit = (json['cache_hit'] as bool?) ?? false;

    final dynamic statusObj = json['status'];
    if (statusObj is Map<String, dynamic>) {
      return WeatherCurrentResponse(
        status: SunshineStatus.fromJson(statusObj),
        cacheHit: cacheHit,
      );
    }

    // fallback: flat response
    return WeatherCurrentResponse(
      status: SunshineStatus.fromJson(json),
      cacheHit: cacheHit,
    );
  }
}
