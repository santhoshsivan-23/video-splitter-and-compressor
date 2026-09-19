import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/format_service.dart';
import '../../utils/duration_utils.dart';
import 'format_result_screen.dart';

class ConvertingFormatScreen extends StatefulWidget {
  final File sourceFile;
  final String outputPath;
  final VideoFormat targetFormat;
  final FormatQuality quality;
  final int? targetWidth;
  final int? targetHeight;
  final int durationSeconds;
  final int originalSizeBytes;
  final int? originalWidth;
  final int? originalHeight;

  const ConvertingFormatScreen({
    super.key,
    required this.sourceFile,
    required this.outputPath,
    required this.targetFormat,
    required this.quality,
    this.targetWidth,
    this.targetHeight,
    required this.durationSeconds,
    required this.originalSizeBytes,
    this.originalWidth,
    this.originalHeight,
  });

  @override
  State<ConvertingFormatScreen> createState() => _ConvertingFormatScreenState();
}

class _ConvertingFormatScreenState extends State<ConvertingFormatScreen> {
  final _formatService = FormatService();

  FormatProgress? _progress;
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
      await for (final progress in _formatService.convertFormat(
        sourcePath: widget.sourceFile.path,
        outputPath: widget.outputPath,
        targetFormat: widget.targetFormat,
        quality: widget.quality,
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
          builder: (_) => FormatResultScreen(
            sourceFile: widget.sourceFile,
            outputFile: File(widget.outputPath),
            targetFormat: widget.targetFormat,
            quality: widget.quality,
            originalSizeBytes: widget.originalSizeBytes,
            originalWidth: widget.originalWidth,
            originalHeight: widget.originalHeight,
            targetWidth: widget.targetWidth,
            targetHeight: widget.targetHeight,
          ),
        ),
      );
    } on FormatCancelledException {
      if (!mounted) return;
      setState(() => _cancelled = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _cancel() {
    _formatService.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final sourceExt = p.extension(widget.sourceFile.path).replaceFirst('.', '').toUpperCase();

    return PopScope(
      canPop: _done || _cancelled || _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Converting Format'),
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
                      : _buildProgressView(sourceExt),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressView(String sourceExt) {
    final progressVal = _progress?.progress ?? 0.0;
    final percent = (progressVal * 100).toStringAsFixed(0);
    final elapsed = _progress?.elapsed;
    final eta = _progress?.eta;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Format Conversion Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sourceExt.isNotEmpty ? sourceExt : 'ORIGINAL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Text(
                widget.targetFormat.label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text(
          p.basename(widget.sourceFile.path),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),

        const SizedBox(height: 36),

        // Animated Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progressVal > 0 ? progressVal : null,
            minHeight: 12,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),

        const SizedBox(height: 16),

        Text(
          '$percent%',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),

        const SizedBox(height: 24),

        // Time Stats
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Elapsed', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      elapsed != null ? DurationUtils.formatHms(elapsed.inSeconds) : '--:--',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Container(height: 28, width: 1, color: Theme.of(context).dividerColor),
                Column(
                  children: [
                    const Text('Remaining', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      eta != null ? DurationUtils.formatHms(eta.inSeconds) : '--:--',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 36),

        OutlinedButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
          label: const Text('Cancel Conversion', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelledView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cancel, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('Conversion Cancelled', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('The video conversion was stopped before completion.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Settings'),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Conversion Failed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unexpected error occurred.',
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.red),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Settings'),
        ),
      ],
    );
  }
}
