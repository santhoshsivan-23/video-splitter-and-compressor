import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/resize_service.dart';
import '../../utils/duration_utils.dart';
import 'resize_result_screen.dart';

class ResizingScreen extends StatefulWidget {
  final File sourceFile;
  final String outputPath;
  final int targetWidth;
  final int targetHeight;
  final int durationSeconds;
  final int originalSizeBytes;

  const ResizingScreen({
    super.key,
    required this.sourceFile,
    required this.outputPath,
    required this.targetWidth,
    required this.targetHeight,
    required this.durationSeconds,
    required this.originalSizeBytes,
  });

  @override
  State<ResizingScreen> createState() => _ResizingScreenState();
}

class _ResizingScreenState extends State<ResizingScreen> {
  final _resizeService = ResizeService();

  ResizeProgress? _progress;
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
      await for (final progress in _resizeService.resizeVideo(
        sourcePath: widget.sourceFile.path,
        outputPath: widget.outputPath,
        targetWidth: widget.targetWidth,
        targetHeight: widget.targetHeight,
        durationSeconds: widget.durationSeconds,
      )) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }

      if (!mounted) return;
      setState(() => _done = true);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResizeResultScreen(
            sourceFile: widget.sourceFile,
            outputFile: File(widget.outputPath),
            originalSizeBytes: widget.originalSizeBytes,
            targetWidth: widget.targetWidth,
            targetHeight: widget.targetHeight,
          ),
        ),
      );
    } on ResizeCancelledException {
      if (!mounted) return;
      setState(() => _cancelled = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _cancel() {
    _resizeService.cancel();
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
          title: const Text('Resizing Video'),
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
              child: Icon(Icons.photo_size_select_large, size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Resizing Video...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Re-encoding to ${widget.targetWidth}×${widget.targetHeight} offline using FFmpeg.',
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
              label: const Text('Cancel Resizing'),
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
        const Text('Resizing Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
        const Text('Resizing Cancelled', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}
