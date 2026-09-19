import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ffmpeg_service.dart';
import '../../services/resize_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'resizing_screen.dart';

class ResizeConfigScreen extends StatefulWidget {
  final File sourceFile;

  const ResizeConfigScreen({super.key, required this.sourceFile});

  @override
  State<ResizeConfigScreen> createState() => _ResizeConfigScreenState();
}

class _ResizeConfigScreenState extends State<ResizeConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;

  bool _useCustomResolution = false;
  ResizePreset? _selectedPreset;
  final _customWidthController = TextEditingController();
  final _customHeightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVideoMetadata();
  }

  @override
  void dispose() {
    _customWidthController.dispose();
    _customHeightController.dispose();
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

      // Auto-select the first available preset
      if (info.height != null) {
        final available = ResizePreset.availableFor(info.height!);
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

  int get _targetWidth {
    if (_useCustomResolution) {
      return int.tryParse(_customWidthController.text) ?? 0;
    }
    return _selectedPreset?.targetWidth ?? 0;
  }

  int get _targetHeight {
    if (_useCustomResolution) {
      return int.tryParse(_customHeightController.text) ?? 0;
    }
    return _selectedPreset?.targetHeight ?? 0;
  }

  int get _estimatedSizeBytes {
    final info = _info;
    if (info == null || info.width == null || info.height == null) return 0;
    final tw = _targetWidth;
    final th = _targetHeight;
    if (tw <= 0 || th <= 0) return 0;
    return ResizeService.estimateOutputSizeBytes(
      originalSizeBytes: _originalSizeBytes,
      sourceWidth: info.width!,
      sourceHeight: info.height!,
      targetWidth: tw,
      targetHeight: th,
    );
  }

  bool get _canStart {
    final tw = _targetWidth;
    final th = _targetHeight;
    return tw > 0 && th > 0 && _info != null;
  }

  Future<void> _startResizing() async {
    final info = _info;
    if (info == null) return;

    final outputPath = await _storageService.createResizedOutputPath(widget.sourceFile.path);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResizingScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          targetWidth: _targetWidth,
          targetHeight: _targetHeight,
          durationSeconds: info.durationSeconds,
          originalSizeBytes: _originalSizeBytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Resizing'),
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
    final availablePresets = info.height != null ? ResizePreset.availableFor(info.height!) : <ResizePreset>[];
    final estimatedSize = _estimatedSizeBytes;
    final reduction = _originalSizeBytes > 0 && estimatedSize > 0
        ? (((_originalSizeBytes - estimatedSize) / _originalSizeBytes) * 100).clamp(0.0, 99.9)
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

              // Original Resolution Badge
              if (info.width != null && info.height != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.aspect_ratio, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Original Resolution:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${info.width} × ${info.height}',
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

              // Resize Presets Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resolution Presets',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose a common downscale preset or enter a custom resolution.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Preset Chips
                      if (availablePresets.isNotEmpty) ...[
                        ...availablePresets.map((preset) {
                          final isSelected = !_useCustomResolution && _selectedPreset == preset;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PresetTile(
                              preset: preset,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _useCustomResolution = false;
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
                                  'No standard presets available for this video resolution. Use custom resolution below.',
                                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Divider(height: 28),

                      // Custom Resolution Toggle
                      _PresetTile(
                        customLabel: 'Custom Resolution',
                        customDescription: 'Enter any width × height',
                        customIcon: Icons.settings,
                        isSelected: _useCustomResolution,
                        onTap: () {
                          setState(() {
                            _useCustomResolution = true;
                            _selectedPreset = null;
                          });
                        },
                      ),

                      if (_useCustomResolution) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customWidthController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Width',
                                  suffixText: 'px',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _customHeightController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Height',
                                  suffixText: 'px',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Size Estimation Card
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
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('Original', style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(height: 4),
                              Text(
                                '${info.width ?? '?'} × ${info.height ?? '?'}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                filesize(_originalSizeBytes),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const Icon(Icons.arrow_forward, size: 28),
                          Column(
                            children: [
                              Text('Output', style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(height: 4),
                              Text(
                                '$_targetWidth × $_targetHeight',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '~${filesize(estimatedSize)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                          if (reduction > 0)
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
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Action Button
              FilledButton.icon(
                onPressed: _canStart ? _startResizing : null,
                icon: const Icon(Icons.photo_size_select_large),
                label: const Text('Resize Video', style: TextStyle(fontSize: 16)),
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

class _PresetTile extends StatelessWidget {
  final ResizePreset? preset;
  final String? customLabel;
  final String? customDescription;
  final IconData? customIcon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetTile({
    this.preset,
    this.customLabel,
    this.customDescription,
    this.customIcon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = customLabel ?? preset!.label;
    final desc = customDescription ?? preset!.description;
    final icon = customIcon ?? Icons.tv;
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
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                    const SizedBox(height: 2),
                    Text(desc, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.withAlpha(180))),
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
