import 'package:flutter/material.dart';

import '../services/video_service.dart';

String _fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Mirrors the "Splitting video..." card from design doc section 18.
class SplitProgressCard extends StatelessWidget {
  final SplitProgress progress;
  final VoidCallback onCancel;

  const SplitProgressCard({super.key, required this.progress, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Splitting video...', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Part ${progress.currentPart} / ${progress.totalParts}'),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress.fraction, minHeight: 10),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${(progress.fraction * 100).toStringAsFixed(0)}%'),
            ),
            const SizedBox(height: 12),
            Text('Current: ${progress.currentFileName}'),
            const SizedBox(height: 4),
            Text('Elapsed: ${_fmtDuration(progress.elapsed)}'),
            if (progress.estimatedRemaining != null)
              Text('Remaining: approximately ${_fmtDuration(progress.estimatedRemaining!)}'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
