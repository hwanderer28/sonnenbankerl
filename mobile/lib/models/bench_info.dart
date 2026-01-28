import 'package:flutter/material.dart';
import 'bench.dart';

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

  @override
  Widget build(BuildContext context) {
    final bench = widget.bench;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          Row(
            children: [
              Expanded(
                child: Text(
                  bench.displayName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () async {
                  final newState = await widget.onToggleFavorite(bench.id);
                  if (!mounted) return;
                  setState(() => _isFavorite = newState);
                },
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.red : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Text('Status: '),
              Icon(
                bench.currentStatus.trim().toLowerCase() == 'sunny'
                    ? Icons.wb_sunny
                    : Icons.cloud,
                color: bench.currentStatus.trim().toLowerCase() == 'sunny'
                    ? Colors.orange
                    : Colors.blueGrey,
                size: 18,
              ),
            ],
          ),

          if (bench.remainingMinutes != null) ...[
            const SizedBox(height: 6),
            Text('Remaining minutes: ${bench.remainingMinutes}'),
          ],
          if (bench.sunUntil != null) ...[
            const SizedBox(height: 6),
            Text('Sun until: ${bench.sunUntil}'),
          ],
          if (bench.statusNote != null && bench.statusNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Note: ${bench.statusNote}'),
          ],
        ],
      ),
    );
  }
}
