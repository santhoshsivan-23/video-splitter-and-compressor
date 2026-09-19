import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/ffmpeg_service.dart';
import '../../services/format_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'converting_format_screen.dart';

class FormatResolutionPreset {
  final String label;
  final int? width;
  final int? height;

  const FormatResolutionPreset({
    required this.label,
    this.width,
    this.height,
  });
}

class FormatConfigScreen extends StatefulWidget {
  final File sourceFile;

  const FormatConfigScreen({super.key, required this.sourceFile});

  @override
  State<FormatConfigScreen> createState() => _FormatConfigScreenState();
}

class _FormatConfigScreenState extends State<FormatConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;

  VideoFormat _selectedFormat = VideoFormat.mp4;
  FormatQuality _selectedQuality = FormatQuality.high;
  
  // Resolution selection: 0 = Original, 1 = 1080p, 2 = 720p, 3 = 480p, 4 = Custom
  int _selectedResIndex = 0;
  final _customWidthController = TextEditingController();
  final _customHeightController = TextEditingController();

  final List<FormatResolutionPreset> _resolutionPresets = const [
    FormatResolutionPreset(label: 'Original (Keep Source)'),
    FormatResolutionPreset(label: '1080p (1920×1080)', width: 1920, height: 1080),
    FormatResolutionPreset(label: '720p (1280×720)', width: 1280, height: 720),
    FormatResolutionPreset(label: '480p (854×480)', width: 854, height: 480),
    FormatResolutionPreset(label: 'Custom Resolution'),
  ];

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

      final currentExt = p.extension(widget.sourceFile.path);
      final currentFormat = VideoFormat.fromExtension(currentExt);

      // Default target format: if current is MP4, default to WebM, otherwise MP4
      VideoFormat defaultTarget = VideoFormat.mp4;
      if (currentFormat == VideoFormat.mp4) {
        defaultTarget = VideoFormat.webm;
      }

      setState(() {
        _info = info;
        _originalSizeBytes = size;
        _selectedFormat = defaultTarget;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int? get _targetWidth {
    if (_selectedResIndex == 0) return null; // Original
    if (_selectedResIndex == 4) {
      return int.tryParse(_customWidthController.text);
    }
    return _resolutionPresets[_selectedResIndex].width;
  }

  int? get _targetHeight {
    if (_selectedResIndex == 0) return null; // Original
    if (_selectedResIndex == 4) {
      return int.tryParse(_customHeightController.text);
    }
    return _resolutionPresets[_selectedResIndex].height;
  }

  bool get _canStart {
    if (_info == null) return false;
    if (_selectedResIndex == 4) {
      final w = _targetWidth;
      final h = _targetHeight;
      if (w == null || h == null || w <= 0 || h <= 0) return false;
    }
    return true;
  }

  Future<void> _startConversion() async {
    final info = _info;
    if (info == null) return;

    final outputPath = await _storageService.createFormatOutputPath(
      widget.sourceFile.path,
      _selectedFormat.extension,
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConvertingFormatScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          targetFormat: _selectedFormat,
          quality: _selectedQuality,
          targetWidth: _targetWidth,
          targetHeight: _targetHeight,
          durationSeconds: info.durationSeconds,
          originalSizeBytes: _originalSizeBytes,
          originalWidth: info.width,
          originalHeight: info.height,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Format Conversion'),
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
    final currentExt = p.extension(widget.sourceFile.path).replaceFirst('.', '').toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Source File Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(64)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.video_file, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.basename(widget.sourceFile.path),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currentExt.isNotEmpty ? currentExt : 'VIDEO',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _buildDetailChip(Icons.data_usage, filesize(_originalSizeBytes)),
                          _buildDetailChip(Icons.timer_outlined, DurationUtils.formatHms(info.durationSeconds)),
                          if (info.width != null && info.height != null)
                            _buildDetailChip(Icons.aspect_ratio, '${info.width}×${info.height}'),
                          if (info.fps != null)
                            _buildDetailChip(Icons.speed, '${info.fps!.toStringAsFixed(0)} FPS'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section 1: Output Format
              const Text(
                '1. Select Output Format',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),

              ...VideoFormat.values.map((format) {
                final isSelected = _selectedFormat == format;
                final isCurrent = currentExt.toLowerCase() == format.extension;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128)
                        : Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor.withAlpha(64),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedFormat = format),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        format.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isSelected
                                              ? Theme.of(context).colorScheme.primary
                                              : null,
                                        ),
                                      ),
                                      if (isCurrent) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withAlpha(64),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    format.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).textTheme.bodySmall?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 24),

              // Section 2: Quality Preset
              const Text(
                '2. Select Quality',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),

              Row(
                children: FormatQuality.values.map((quality) {
                  final isSelected = _selectedQuality == quality;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            quality.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedQuality = quality),
                      ),
                    ),
                  );
                }).toList(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  _selectedQuality.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section 3: Output Resolution
              const Text(
                '3. Output Resolution',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_resolutionPresets.length, (index) {
                  final preset = _resolutionPresets[index];
                  final isSelected = _selectedResIndex == index;
                  return ChoiceChip(
                    label: Text(preset.label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedResIndex = index),
                  );
                }),
              ),

              // Custom Resolution Inputs
              if (_selectedResIndex == 4) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customWidthController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Width (px)',
                          hintText: 'e.g. 1920',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _customHeightController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Height (px)',
                          hintText: 'e.g. 1080',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 28),

              // Summary Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.primary.withAlpha(90)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SOURCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(
                                currentExt.isNotEmpty ? currentExt : 'Original',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                info.width != null && info.height != null ? '${info.width}×${info.height}' : 'Original Res',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.primary),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('CONVERT TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFormat.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Text(
                                _selectedResIndex == 0
                                    ? 'Original Res'
                                    : '${_targetWidth ?? '?'}×${_targetHeight ?? '?'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Quality: ${_selectedQuality.label}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Output: .${_selectedFormat.extension}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Button
              FilledButton.icon(
                onPressed: _canStart ? _startConversion : null,
                icon: const Icon(Icons.transform),
                label: Text('Convert Video to ${_selectedFormat.label}'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
