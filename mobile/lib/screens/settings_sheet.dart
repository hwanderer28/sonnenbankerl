import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';

import '../services/favorites_service.dart';
import 'welcome_screen.dart';

class SettingsSheet extends StatefulWidget {
  final Handedness initialHandedness;
  final ValueChanged<Handedness> onHandednessChanged;
  final VoidCallback onFavoritesCleared;

  const SettingsSheet({
    super.key,
    required this.initialHandedness,
    required this.onHandednessChanged,
    required this.onFavoritesCleared,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final FavoritesService _favoritesService = FavoritesService();
  late Handedness _handedness;

  @override
  void initState() {
    super.initState();
    _handedness = widget.initialHandedness;
  }

  Future<void> _saveHandedness(Handedness h) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dominant_hand', h == Handedness.left ? 'left' : 'right');
  }

  Future<void> _setHandedness(Handedness h) async {
    setState(() => _handedness = h);
    await _saveHandedness(h);
    widget.onHandednessChanged(h);
  }

  Future<void> _confirmClearFavorites() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear favorites'),
        content: const Text('Delete all your favorite benches?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _favoritesService.clearFavorites();
      if (!mounted) return;
      widget.onFavoritesCleared();
      Navigator.pop(context); // Settings schließen
    }
  }

  Future<void> _confirmFactoryReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Factory reset'),
        content: const Text(
          'Are you sure? All settings will be deleted and the app will restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (!mounted) return;
      Phoenix.rebirth(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLeft = _handedness == Handedness.left;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          const Text(
            'Change UI placement',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),

          Center(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
              child: ToggleButtons(
                borderRadius: BorderRadius.circular(999),
                isSelected: [isLeft, !isLeft],
                onPressed: (index) {
                  _setHandedness(index == 0 ? Handedness.left : Handedness.right);
                },
                constraints: const BoxConstraints(minWidth: 110, minHeight: 42),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Left')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Right')),
                ],
              ),
            ),
          ),

          const Divider(height: 32),

          Center(
            child: TextButton(
              onPressed: _confirmClearFavorites,
              child: const Text('Clear favorites'),
            ),
          ),

          const SizedBox(height: 8),

          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _confirmFactoryReset,
              child: const Text('Factory reset'),
            ),
          ),
        ],
      ),
    );
  }
}
