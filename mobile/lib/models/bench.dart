class BenchLocation {
  final double lat;
  final double lon;

  BenchLocation({required this.lat, required this.lon});

  factory BenchLocation.fromJson(Map<String, dynamic> json) {
    return BenchLocation(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}

class Bench {
  final int id;
  final int? osmId;
  final String? name;
  final BenchLocation location;
  final double? elevation;

  final String currentStatus; // sunny | shady | unknown
  final DateTime? sunUntil;
  final int? remainingMinutes;
  final String? statusNote;
  final DateTime? createdAt;

  Bench({
    required this.id,
    this.osmId,
    this.name,
    required this.location,
    this.elevation,
    required this.currentStatus,
    this.sunUntil,
    this.remainingMinutes,
    this.statusNote,
    this.createdAt,
  });

  factory Bench.fromJson(Map<String, dynamic> json) {
    return Bench(
      id: json['id'] as int,
      osmId: json['osm_id'] as int?,
      name: json['name'] as String?,
      location: BenchLocation.fromJson(json['location'] as Map<String, dynamic>),
      elevation: (json['elevation'] as num?)?.toDouble(),
      currentStatus: (json['current_status'] as String?) ?? 'unknown',
      sunUntil: json['sun_until'] != null ? DateTime.parse(json['sun_until']) : null,
      remainingMinutes: json['remaining_minutes'] as int?,
      statusNote: json['status_note'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  String get displayName => name ?? 'Bench #$id';
}
