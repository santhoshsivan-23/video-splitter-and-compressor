import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/ffmpeg_service.dart';
import '../../services/flip_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'flipping_screen.dart';

class FlipConfigScreen extends StatefulWidget {
  final File sourceFile;

  const FlipConfigScreen({super.key, required this.sourceFile});

  @override
  State<FlipConfigScreen> createState() => _FlipConfigScreenState();
}

class _FlipConfigScreenState extends State<FlipConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  VideoPlayerController? _playerController;
  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;
  bool _isPlaying = false;

  FlipDirection _direction = FlipDirection.horizontal;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final size = await widget.sourceFile.length();
      final info = await _videoService.probe(widget.sourceFile.path);

      final controller = VideoPlayerController.file(widget.sourceFile);
      await controller.initialize();
      controller.addListener(_onPlayerTick);

      setState(() {
        _info = info;
        _originalSizeBytes = size;
        _playerController = controller;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onPlayerTick() {
    final controller = _playerController;
    if (controller == null || !mounted) return;
    final isPlaying = controller.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  void dispose() {
    _playerController?.removeListener(_onPlayerTick);
    _playerController?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _playerController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  Future<void> _startFlipping() async {
    final info = _info;
    if (info == null) return;

    final outputPath = await _storageService.createFlippedOutputPath(widget.sourceFile.path);
    _playerController?.pause();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlippingScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          direction: _direction,
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
        title: const Text('Video Flip'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final info = _info!;
    final controller = _playerController;

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

              // Video Preview with Flip Transform
              if (controller != null && controller.value.isInitialized)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: _direction == FlipDirection.horizontal
                              ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                              : Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                          child: VideoPlayer(controller),
                        ),
                      ),
                      // Play/Pause overlay
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            color: _isPlaying
                                ? Colors.transparent
                                : Colors.black38,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _isPlaying ? 0.0 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Colors.white70,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow, size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              Text(
                'Preview shows how the flipped video will look',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              const SizedBox(height: 20),

              // Flip Direction Selector
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flip Direction',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _FlipOptionTile(
                              icon: Icons.flip,
                              label: 'Horizontal',
                              description: 'Mirror left ↔ right',
                              isSelected: _direction == FlipDirection.horizontal,
                              onTap: () => setState(() => _direction = FlipDirection.horizontal),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FlipOptionTile(
                              icon: Icons.flip_camera_android,
                              label: 'Vertical',
                              description: 'Mirror top ↕ bottom',
                              isSelected: _direction == FlipDirection.vertical,
                              onTap: () => setState(() => _direction = FlipDirection.vertical),
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
                onPressed: _startFlipping,
                icon: const Icon(Icons.flip),
                label: Text(
                  'Flip ${_direction == FlipDirection.horizontal ? "Horizontally" : "Vertically"}',
                  style: const TextStyle(fontSize: 16),
                ),
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Could not open video for preview', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}

class _FlipOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _FlipOptionTile({
    required this.icon,
    required this.label,
    required this.description,
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withAlpha(120)
                  : Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.withAlpha(180)),
              ),
              if (isSelected) ...[
                const SizedBox(height: 6),
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
