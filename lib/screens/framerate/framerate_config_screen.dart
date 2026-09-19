import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ffmpeg_service.dart';
import '../../services/framerate_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'converting_framerate_screen.dart';

class FrameRateConfigScreen extends StatefulWidget {
  final File sourceFile;

  const FrameRateConfigScreen({super.key, required this.sourceFile});

  @override
  State<FrameRateConfigScreen> createState() => _FrameRateConfigScreenState();
}

class _FrameRateConfigScreenState extends State<FrameRateConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;

  bool _useCustomFps = false;
  FrameRatePreset? _selectedPreset;
  final _customFpsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVideoMetadata();
  }

  @override
  void dispose() {
    _customFpsController.dispose();
    super.dispose();
  }

  Future<void> _loadVideoMetadata() async {
    try {
      final size = await widget.sourceFile.length();
      final info = await _videoService.probe(widget.sourceFile.path);

      setState(() {
        _info = info;
        _originalSizeBytes = size;
        _loading = false;
      });

      // Auto-select best preset
      if (info.fps != null) {
        final available = FrameRatePreset.availableFor(info.fps!);
        if (available.isNotEmpty) {
          setState(() => _selectedPreset = available.first);
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double get _targetFps {
    if (_useCustomFps) {
      return double.tryParse(_customFpsController.text) ?? 0;
    }
    return _selectedPreset?.targetFps ?? 0;
  }

  bool get _canStart => _targetFps > 0 && _info != null;

  Future<void> _startConversion() async {
    final info = _info;
    if (info == null) return;

    final outputPath = await _storageService.createFrameRateOutputPath(widget.sourceFile.path);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConvertingFrameRateScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          targetFps: _targetFps,
          durationSeconds: info.durationSeconds,
          originalSizeBytes: _originalSizeBytes,
          originalFps: info.fps,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frame Rate Conversion'),
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
    final sourceFps = info.fps;
    final availablePresets = sourceFps != null
        ? FrameRatePreset.availableFor(sourceFps)
        : <FrameRatePreset>[];

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

              // Original FPS Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.speed, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Original Frame Rate:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sourceFps != null ? '${sourceFps.toStringAsFixed(2)} FPS' : 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Frame Rate Presets Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Frame Rate Options',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose a preset conversion or enter a custom frame rate.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Preset Tiles
                      if (availablePresets.isNotEmpty) ...[
                        ...availablePresets.map((preset) {
                          final isSelected = !_useCustomFps && _selectedPreset == preset;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FpsPresetTile(
                              label: preset.label,
                              description: preset.description,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _useCustomFps = false;
                                  _selectedPreset = preset;
                                });
                              },
                            ),
                          );
                        }),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No standard presets available for this frame rate. Use custom FPS below.',
                                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Divider(height: 28),

                      // Custom FPS Toggle
                      _FpsPresetTile(
                        label: 'Custom FPS',
                        description: 'Enter any frame rate value',
                        icon: Icons.settings,
                        isSelected: _useCustomFps,
                        onTap: () {
                          setState(() {
                            _useCustomFps = true;
                            _selectedPreset = null;
                          });
                        },
                      ),

                      if (_useCustomFps) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _customFpsController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: InputDecoration(
                            labelText: 'Target FPS',
                            suffixText: 'FPS',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.speed),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [15, 24, 25, 30, 48, 60, 120].map((fps) {
                            return ActionChip(
                              label: Text('$fps'),
                              onPressed: () {
                                _customFpsController.text = fps.toString();
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // FPS Comparison
              if (_canStart)
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
                          Text('Original FPS', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Text(
                            sourceFps != null ? sourceFps.toStringAsFixed(2) : '?',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                      const Icon(Icons.arrow_forward, size: 28),
                      Column(
                        children: [
                          Text('Output FPS', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Text(
                            _targetFps.toStringAsFixed(2),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Action Button
              FilledButton.icon(
                onPressed: _canStart ? _startConversion : null,
                icon: const Icon(Icons.speed),
                label: const Text('Convert Frame Rate', style: TextStyle(fontSize: 16)),
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

class _FpsPresetTile extends StatelessWidget {
  final String label;
  final String description;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FpsPresetTile({
    required this.label,
    required this.description,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(120)
          : Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withAlpha(120)
                  : Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon ?? Icons.speed, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                    const SizedBox(height: 2),
                    Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.withAlpha(180))),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
