import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/framerate_service.dart';
import '../../utils/duration_utils.dart';
import 'framerate_result_screen.dart';

class ConvertingFrameRateScreen extends StatefulWidget {
  final File sourceFile;
  final String outputPath;
  final double targetFps;
  final int durationSeconds;
  final int originalSizeBytes;
  final double? originalFps;

  const ConvertingFrameRateScreen({
    super.key,
    required this.sourceFile,
    required this.outputPath,
    required this.targetFps,
    required this.durationSeconds,
    required this.originalSizeBytes,
    this.originalFps,
  });

  @override
  State<ConvertingFrameRateScreen> createState() => _ConvertingFrameRateScreenState();
}

class _ConvertingFrameRateScreenState extends State<ConvertingFrameRateScreen> {
  final _frameRateService = FrameRateService();

  FrameRateProgress? _progress;
  String? _error;
  bool _cancelled = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await for (final progress in _frameRateService.convertFrameRate(
        sourcePath: widget.sourceFile.path,
        outputPath: widget.outputPath,
        targetFps: widget.targetFps,
        durationSeconds: widget.durationSeconds,
      )) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }

      if (!mounted) return;
      setState(() => _done = true);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FrameRateResultScreen(
            sourceFile: widget.sourceFile,
            outputFile: File(widget.outputPath),
            originalSizeBytes: widget.originalSizeBytes,
            originalFps: widget.originalFps,
            targetFps: widget.targetFps,
          ),
        ),
      );
    } on FrameRateCancelledException {
      if (!mounted) return;
      setState(() => _cancelled = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _cancel() {
    _frameRateService.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done || _cancelled || _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Converting Frame Rate'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error != null
                  ? _buildErrorView()
                  : _cancelled
                      ? _buildCancelledView()
                      : _buildProgressView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressView() {
    final percent = ((_progress?.progress ?? 0.0) * 100).clamp(0.0, 100.0);
    final elapsed = _progress?.elapsed ?? Duration.zero;
    final eta = _progress?.eta;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(120),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.speed, size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Converting to ${widget.targetFps.toStringAsFixed(0)} FPS...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Re-encoding frame rate offline using FFmpeg.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress?.progress,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Elapsed: ${DurationUtils.formatHms(elapsed.inSeconds)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (eta != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Estimated remaining: ${DurationUtils.formatHms(eta.inSeconds)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
                ),
              ),
            ],
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Conversion'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 56, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Conversion Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _buildCancelledView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cancel_outlined, size: 56, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('Conversion Cancelled', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}
