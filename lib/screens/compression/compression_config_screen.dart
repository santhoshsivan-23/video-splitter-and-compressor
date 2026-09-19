import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/compression_config.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'compressing_screen.dart';

class CompressionConfigScreen extends StatefulWidget {
  final File sourceFile;

  const CompressionConfigScreen({super.key, required this.sourceFile});

  @override
  State<CompressionConfigScreen> createState() => _CompressionConfigScreenState();
}

class _CompressionConfigScreenState extends State<CompressionConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;

  CompressionMode _mode = CompressionMode.targetSize;
  QualityPreset _preset = QualityPreset.medium;
  VideoResolutionOption _resolution = VideoResolutionOption.original;

  final _targetSizeController = TextEditingController();
  final _customBitrateController = TextEditingController(text: '800');
  final _customWidthController = TextEditingController();
  final _customHeightController = TextEditingController();
  final int _audioBitrateKbps = 128;

  @override
  void initState() {
    super.initState();
    _loadVideoMetadata();
  }

  @override
  void dispose() {
    _targetSizeController.dispose();
    _customBitrateController.dispose();
    _customWidthController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  Future<void> _loadVideoMetadata() async {
    try {
      final size = await widget.sourceFile.length();
      final info = await _videoService.probe(widget.sourceFile.path);

      final defaultTargetMb = ((size / (1024 * 1024)) * 0.1).clamp(5.0, 500.0).roundToDouble();
      _targetSizeController.text = defaultTargetMb.toInt().toString();

      setState(() {
        _info = info;
        _originalSizeBytes = size;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  CompressionConfig _buildConfig() {
    final targetMb = double.tryParse(_targetSizeController.text);
    final customBitrate = int.tryParse(_customBitrateController.text);
    final customW = int.tryParse(_customWidthController.text);
    final customH = int.tryParse(_customHeightController.text);

    return CompressionConfig(
      mode: _mode,
      targetSizeMb: targetMb,
      preset: _preset,
      resolution: _resolution,
      customWidth: customW,
      customHeight: customH,
      customVideoBitrateKbps: customBitrate,
      audioBitrateKbps: _audioBitrateKbps,
    );
  }

  Future<void> _startCompression() async {
    final info = _info;
    if (info == null) return;

    final config = _buildConfig();
    final outputPath = await _storageService.createCompressedOutputPath(widget.sourceFile.path);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompressingScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          config: config,
          originalSizeBytes: _originalSizeBytes,
          durationSeconds: info.durationSeconds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Compression'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        const Text('Could not inspect video', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                      ],
                    ),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final info = _info!;
    final config = _buildConfig();
    final estimatedSizeBytes = config.resolveEstimatedSizeBytes(
      originalSizeBytes: _originalSizeBytes,
      durationSeconds: info.durationSeconds,
    );

    final reduction = _originalSizeBytes > 0
        ? (((_originalSizeBytes - estimatedSizeBytes) / _originalSizeBytes) * 100).clamp(0.0, 99.9)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Source File Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(120),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.movie, color: Theme.of(context).colorScheme.primary, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.sourceFile.path.split(Platform.pathSeparator).last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${filesize(_originalSizeBytes)} • ${DurationUtils.formatHms(info.durationSeconds)}'
                              '${info.width != null ? ' • ${info.width}x${info.height}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Compression Mode Selector
              SegmentedButton<CompressionMode>(
                segments: const [
                  ButtonSegment(
                    value: CompressionMode.targetSize,
                    label: Text('Target Size'),
                    icon: Icon(Icons.tune),
                  ),
                  ButtonSegment(
                    value: CompressionMode.preset,
                    label: Text('Presets'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                  ButtonSegment(
                    value: CompressionMode.custom,
                    label: Text('Custom'),
                    icon: Icon(Icons.settings),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (set) => setState(() => _mode = set.first),
              ),

              const SizedBox(height: 16),

              // Configuration Card based on Mode
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_mode == CompressionMode.targetSize) ...[
                        Text(
                          'Target File Size',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter the desired file size in MB. Bitrate is automatically adjusted.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _targetSizeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: InputDecoration(
                            labelText: 'Desired Size (MB)',
                            suffixText: 'MB',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.save_alt),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [10, 25, 30, 50, 100].map((mb) {
                            return ActionChip(
                              label: Text('$mb MB'),
                              onPressed: () {
                                _targetSizeController.text = mb.toString();
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ] else if (_mode == CompressionMode.preset) ...[
                        Text(
                          'Quality Preset',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Select your preferred balance between file size and visual quality.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<QualityPreset>(
                            segments: const [
                              ButtonSegment(
                                value: QualityPreset.low,
                                label: Text('Low'),
                                icon: Icon(Icons.speed),
                              ),
                              ButtonSegment(
                                value: QualityPreset.medium,
                                label: Text('Medium'),
                                icon: Icon(Icons.balance),
                              ),
                              ButtonSegment(
                                value: QualityPreset.high,
                                label: Text('High'),
                                icon: Icon(Icons.hd),
                              ),
                            ],
                            selected: {_preset},
                            onSelectionChanged: (set) => setState(() => _preset = set.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _preset == QualityPreset.low
                                      ? 'Low Quality: ~85%–90% size reduction (Smallest file)'
                                      : _preset == QualityPreset.medium
                                          ? 'Medium Quality: ~60%–70% size reduction (Recommended)'
                                          : 'High Quality: ~30%–40% size reduction (Visually near original)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Custom Video Bitrate',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _customBitrateController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'Video Bitrate (kbps)',
                            suffixText: 'kbps',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.speed),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],

                      const Divider(height: 32),

                      // Resolution Options
                      Text(
                        'Target Resolution',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<VideoResolutionOption>(
                        initialValue: _resolution,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          prefixIcon: const Icon(Icons.aspect_ratio),
                        ),
                        items: VideoResolutionOption.standardList.map((res) {
                          return DropdownMenuItem(
                            value: res,
                            child: Text(res.label),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _resolution = val!),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Size Comparison & Estimation Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer.withAlpha(160),
                      Theme.of(context).colorScheme.tertiaryContainer.withAlpha(140),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('Original Size', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(
                          filesize(_originalSizeBytes),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, size: 28),
                    Column(
                      children: [
                        Text('Estimated Size', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(
                          filesize(estimatedSizeBytes),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '-${reduction.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Button
              FilledButton.icon(
                onPressed: _startCompression,
                icon: const Icon(Icons.compress),
                label: const Text('Compress Video', style: TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
