import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/bench.dart';
import '../models/bench_info.dart';
import '../services/api_service.dart';
import '../services/favorites_service.dart';
import '../theme/app_theme.dart';
import 'settings_sheet.dart';
import 'welcome_screen.dart';

class BenchMap extends StatefulWidget {
  final Handedness handedness;

  const BenchMap({super.key, required this.handedness});

  @override
  State<BenchMap> createState() => _BenchMapState();
}

class _BenchMapState extends State<BenchMap> {
  final ApiService _apiService = ApiService();
  final FavoritesService _favoritesService = FavoritesService();

  MaplibreMapController? _mapController;

  late Handedness _handedness;


  // Server & UI State
  bool _serverOnline = true;
  bool _showFavoritesOnly = false;
  Set<int> _favoriteIds = {};

  // Sunshine Gate
  bool _isSunnyInGraz = false; // safer default
  String _sunMessage = '';

  final String styleUrl =
      'https://api.maptiler.com/maps/toner-v2/style.json?key=fBScLUgzlIfxNaaEbTn7';

  // Test-Position (Graz) – later replace with user location
  static const double _queryLat = 47.0707;
  static const double _queryLon = 15.4395;
  static const double _radiusMeters = 1500;

  // GeoJSON source + layers
  static const String _sourceId = 'benches_source';

  // Cluster layers
  static const String _clusterLayerId = 'benches_cluster_layer';
  static const String _clusterCountLayerId = 'benches_cluster_count_layer';

  // Single points (unclustered)
  static const String _unclusteredLayerId = 'benches_unclustered_layer';

  @override
  void initState() {
    super.initState();
    _handedness = widget.handedness;
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favs = await _favoritesService.getFavorites();
    if (!mounted) return;
    setState(() => _favoriteIds = favs);
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
    controller.onFeatureTapped.add(_onFeatureTapped);
  }

  void _onStyleLoaded() {
    _refreshAll(refreshWeather: false);
  }

  Future<void> _checkServerStatus() async {
    final online = await _apiService.checkServerHealth();
    if (!mounted) return;
    setState(() => _serverOnline = online);
  }

  Future<void> _loadWeather({bool refresh = false}) async {
    if (!_serverOnline) return;

    try {
      final res = await _apiService.getCurrentSunshineStatus(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _isSunnyInGraz = res.status.isSunny;
        _sunMessage = res.status.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSunnyInGraz = false;
        _sunMessage = 'Weather status unavailable';
      });
    }
  }

  Future<void> _refreshAll({required bool refreshWeather}) async {
    await _checkServerStatus();

    if (!_serverOnline) {
      // UI is updated via setState in _checkServerStatus
      return;
    }

    await _loadWeather(refresh: refreshWeather);
    await _loadAndRenderBenches();
  }

  Future<void> _loadAndRenderBenches() async {
    final c = _mapController;
    if (c == null) return;
    if (!_serverOnline) return;

    late final List<Bench> benches;
    try {
      benches = await _apiService.getBenches(
        lat: _queryLat,
        lon: _queryLon,
        radius: _radiusMeters,
      );
    } catch (_) {
      return;
    }

    final visible = _showFavoritesOnly
        ? benches.where((b) => _favoriteIds.contains(b.id)).toList()
        : benches;

    // Sunshine Gate: if not sunny -> display ALL as shady
    final fc = {
      "type": "FeatureCollection",
      "features": visible.map((b) {
        final effectiveStatus = _isSunnyInGraz ? b.currentStatus : 'shady';
        return {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [b.location.lon, b.location.lat],
          },
          "properties": {
            "id": b.id,
            "current_status": effectiveStatus,
          },
        };
      }).toList(),
    };

    // Remove old layers + source
    for (final id in [_clusterCountLayerId, _clusterLayerId, _unclusteredLayerId]) {
      try {
        await c.removeLayer(id);
      } catch (_) {}
    }
    try {
      await c.removeSource(_sourceId);
    } catch (_) {}

    // Add clustered source
    await c.addSource(
      _sourceId,
      GeojsonSourceProperties(
        data: fc,
        cluster: true,
        clusterRadius: 50,
        clusterMaxZoom: 14,
      ),
    );

    // Cluster circles
    await c.addCircleLayer(
      _sourceId,
      _clusterLayerId,
      CircleLayerProperties(
        circleOpacity: 0.85,
        circleRadius: [
          "step",
          ["get", "point_count"],
          16,
          10,
          20,
          30,
          26,
          75,
          32,
        ],
        circleColor: [
          "step",
          ["get", "point_count"],
          "#D6C2A8", // sand
          10,
          "#D4A84F", // sunGold
          30,
          "#1C2A3A", // deepBlue
        ],
      ),
      filter: ["has", "point_count"],
      enableInteraction: true,
    );

    // Cluster count text
    await c.addSymbolLayer(
      _sourceId,
      _clusterCountLayerId,
      SymbolLayerProperties(
        textField: ["get", "point_count_abbreviated"],
        textSize: 12,
        textColor: "#FFFFFF",
      ),
      filter: ["has", "point_count"],
      enableInteraction: true,
    );

    // Unclustered points
    await c.addCircleLayer(
      _sourceId,
      _unclusteredLayerId,
      CircleLayerProperties(
        circleRadius: 10,
        circleOpacity: 0.9,
        circleColor: [
          "match",
          ["get", "current_status"],
          "sunny",
          "#FFD54F",
          "shady",
          "#42A5F5",
          "#9E9E9E",
        ],
      ),
      filter: ["!", ["has", "point_count"]],
      enableInteraction: true,
    );
  }

  void _onFeatureTapped(
      dynamic id,
      Point<double> point,
      LatLng coordinates,
      String layerId,
      ) {
    if (!_serverOnline) return;

    // Cluster tap -> zoom in
    if (layerId == _clusterLayerId || layerId == _clusterCountLayerId) {
      _zoomIntoCluster(coordinates);
      return;
    }

// Single bench tap
    if (layerId == _unclusteredLayerId) {
      _handleBenchTap(point);
    }
  }

  Future<void> _zoomIntoCluster(LatLng where) async {
    final c = _mapController;
    if (c == null) return;

    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: where,
          zoom: 15.5,
        ),
      ),
    );
  }


  Future<void> _handleBenchTap(Point<double> point) async {
    final c = _mapController;
    if (c == null) return;
    if (!_serverOnline) return;

    try {
      final features =
      await c.queryRenderedFeatures(point, [_unclusteredLayerId], null);
      if (features.isEmpty) return;

      final props = features.first['properties'];
      if (props is! Map) return;

      final rawId = props['id'];
      if (rawId == null) return;

      int? benchId;
      if (rawId is int) {
        benchId = rawId;
      } else if (rawId is num) {
        benchId = rawId.toInt();
      } else {
        benchId = int.tryParse(rawId.toString().split('.').first);
      }
      if (benchId == null) return;

      final bench = await _apiService.getBenchDetails(benchId);
      final isFav = _favoriteIds.contains(benchId);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => BenchInfoSheet(
          bench: bench,
          initialIsFavorite: isFav,
          onToggleFavorite: (id) async {
            final nowFav = await _favoritesService.toggleFavorite(id);
            final favs = await _favoritesService.getFavorites();
            if (mounted) setState(() => _favoriteIds = favs);

            if (_showFavoritesOnly) {
              await _loadAndRenderBenches();
            }
            return nowFav;
          },
        ),
      );
    } catch (_) {}
  }

  Future<void> _refreshPressed() async {
    await _loadFavorites();
    await _refreshAll(refreshWeather: true);
  }

  Future<void> _toggleFavoritesOnly() async {
    setState(() => _showFavoritesOnly = !_showFavoritesOnly);
    await _loadAndRenderBenches();
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
        initialHandedness: _handedness,
        onHandednessChanged: (h) => setState(() => _handedness = h),
        onFavoritesCleared: () async {
          await _loadFavorites();
          await _loadAndRenderBenches();
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.onFeatureTapped.remove(_onFeatureTapped);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MaplibreMap(
            styleString: styleUrl,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            initialCameraPosition: const CameraPosition(
              target: LatLng(_queryLat, _queryLon),
              zoom: 12.5,
            ),
          ),

          // Status badge (bottom-left) – maxWidth 370
          Positioned(
            left: 12,
            bottom: 16,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 370),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.deepBlue.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(blurRadius: 8, color: Colors.black26),
                ],
              ),
              child: !_serverOnline
                  ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.cloud_off, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Server currently offline. Please try again later.',
                      style:
                      TextStyle(fontSize: 13, color: AppColors.textLight),
                      softWrap: true,
                    ),
                  ),
                ],
              )
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _isSunnyInGraz ? Icons.wb_sunny : Icons.cloud,
                    color: _isSunnyInGraz
                        ? AppColors.sunGold
                        : AppColors.blueGrey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (_sunMessage.trim().isEmpty)
                          ? (_isSunnyInGraz
                          ? 'Sunny in Graz'
                          : 'No direct sunlight in Graz')
                          : _sunMessage,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Buttons (handedness-aware)
          Positioned(
            bottom: 120,
            left: _handedness == Handedness.left ? 16 : null,
            right: _handedness == Handedness.right ? 16 : null,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'settings',
                  onPressed: _openSettings,
                  child: const Icon(Icons.settings),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'refresh',
                  onPressed: _refreshPressed,
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'favorites_filter',
                  onPressed: _toggleFavoritesOnly,
                  child: Icon(
                    _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                    color: _showFavoritesOnly ? AppColors.sunGold : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
