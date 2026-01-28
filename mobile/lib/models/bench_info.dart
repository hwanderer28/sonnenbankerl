import 'package:flutter/material.dart';
import 'bench.dart';
import '../theme/app_theme.dart';

class BenchInfoSheet extends StatefulWidget {
  final Bench bench;
  final bool initialIsFavorite;
  final Future<bool> Function(int benchId) onToggleFavorite;

  const BenchInfoSheet({
    super.key,
    required this.bench,
    required this.initialIsFavorite,
    required this.onToggleFavorite,
  });

  @override
  State<BenchInfoSheet> createState() => _BenchInfoSheetState();
}

class _BenchInfoSheetState extends State<BenchInfoSheet> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initialIsFavorite;
  }

  String _prettyStatus(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'sunny':
        return 'Sunny';
      case 'shady':
        return 'Shady';
      default:
        return 'Unknown';
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getStatusMessage() {
    final bench = widget.bench;
    final status = bench.currentStatus.trim().toLowerCase();

    if (bench.remainingMinutes == null || bench.sunUntil == null) {
      return 'No sun change within 7 days';
    }

    if (status == 'sunny') {
      return '☀️ Sunny for ${bench.remainingMinutes} more minutes';
    } else {
      return '☁️ Next sun in ${bench.remainingMinutes} minutes (${_formatTime(bench.sunUntil!)})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bench = widget.bench;
    final isSunny = bench.currentStatus.trim().toLowerCase() == 'sunny';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.deepBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.blueGrey,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),

            Stack(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSunny
                        ? AppColors.sunGold.withOpacity(0.15)
                        : AppColors.blueGrey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStatusMessage(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSunny ? AppColors.sunGold : AppColors.textLight,
                        ),
                      ),
                      if (bench.statusNote != null && bench.statusNote!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.deepBlue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'ℹ️  ${bench.statusNote!}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () async {
                      final newState = await widget.onToggleFavorite(bench.id);
                      if (!mounted) return;
                      setState(() => _isFavorite = newState);
                    },
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? AppColors.sunGold : AppColors.textMuted,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
