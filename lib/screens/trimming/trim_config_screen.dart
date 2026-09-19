import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/ffmpeg_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../utils/duration_utils.dart';
import 'trimming_screen.dart';

class TrimConfigScreen extends StatefulWidget {
  final File sourceFile;

  const TrimConfigScreen({super.key, required this.sourceFile});

  @override
  State<TrimConfigScreen> createState() => _TrimConfigScreenState();
}

class _TrimConfigScreenState extends State<TrimConfigScreen> {
  final _videoService = VideoService();
  final _storageService = StorageService();

  VideoPlayerController? _playerController;
  MediaInfo? _info;
  int _originalSizeBytes = 0;
  bool _loading = true;
  String? _error;

  double _startSeconds = 0.0;
  double _endSeconds = 10.0;
  double _totalDurationSeconds = 10.0;

  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isPreviewingSection = false;
  bool _reencode = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final size = await widget.sourceFile.length();
      final info = await _videoService.probe(widget.sourceFile.path);
      final duration = info.durationSeconds.toDouble();

      final controller = VideoPlayerController.file(widget.sourceFile);
      await controller.initialize();
      controller.addListener(_onPlayerTick);

      setState(() {
        _info = info;
        _originalSizeBytes = size;
        _totalDurationSeconds = duration > 0 ? duration : 1.0;
        _startSeconds = 0.0;
        _endSeconds = _totalDurationSeconds;
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

    if (_isPreviewingSection && isPlaying) {
      final posSec = controller.value.position.inMilliseconds / 1000.0;
      if (posSec >= _endSeconds) {
        controller.pause();
        setState(() => _isPreviewingSection = false);
      }
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

  void _toggleMute() {
    final controller = _playerController;
    if (controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _previewSelectedSection() {
    final controller = _playerController;
    if (controller == null) return;
    setState(() => _isPreviewingSection = true);
    controller.seekTo(Duration(milliseconds: (_startSeconds * 1000).round()));
    controller.play();
  }

  void _setStartToCurrent() {
    final controller = _playerController;
    if (controller == null) return;
    final currentSec = (controller.value.position.inMilliseconds / 1000.0)
        .clamp(0.0, _endSeconds - 0.5);
    setState(() => _startSeconds = currentSec);
  }

  void _setEndToCurrent() {
    final controller = _playerController;
    if (controller == null) return;
    final currentSec = (controller.value.position.inMilliseconds / 1000.0)
        .clamp(_startSeconds + 0.5, _totalDurationSeconds);
    setState(() => _endSeconds = currentSec);
  }

  void _adjustStart(double delta) {
    final newStart = (_startSeconds + delta).clamp(0.0, _endSeconds - 0.5);
    setState(() => _startSeconds = newStart);
    _playerController?.seekTo(Duration(milliseconds: (newStart * 1000).round()));
  }

  void _adjustEnd(double delta) {
    final newEnd = (_endSeconds + delta).clamp(_startSeconds + 0.5, _totalDurationSeconds);
    setState(() => _endSeconds = newEnd);
    _playerController?.seekTo(Duration(milliseconds: (newEnd * 1000).round()));
  }

  Future<void> _startTrimming() async {
    final outputPath = await _storageService.createTrimmedOutputPath(widget.sourceFile.path);

    _playerController?.pause();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrimmingScreen(
          sourceFile: widget.sourceFile,
          outputPath: outputPath,
          startSeconds: _startSeconds,
          endSeconds: _endSeconds,
          reencode: _reencode,
          originalSizeBytes: _originalSizeBytes,
        ),
      ),
    );
  }

  String _formatPreciseDuration(double seconds) {
    final totalSec = seconds.floor();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final tenths = ((seconds - totalSec) * 10).floor();

    final hStr = h > 0 ? '${h.toString().padLeft(2, '0')}:' : '';
    final mStr = m.toString().padLeft(2, '0');
    final sStr = s.toString().padLeft(2, '0');
    return '$hStr$mStr:$sStr.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trim Video'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final controller = _playerController!;
    final trimmedDuration = (_endSeconds - _startSeconds).clamp(0.0, _totalDurationSeconds);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Video Player Preview Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(controller),
                          if (!_isPlaying)
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                iconSize: 56,
                                icon: const Icon(Icons.play_arrow, color: Colors.white),
                                onPressed: _togglePlayPause,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Player Control Bar
                    Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: _togglePlayPause,
                          ),
                          IconButton(
                            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                            onPressed: _toggleMute,
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder(
                            valueListenable: controller,
                            builder: (context, VideoPlayerValue value, _) {
                              final currentSec = value.position.inSeconds;
                              return Text(
                                '${DurationUtils.formatHms(currentSec)} / ${DurationUtils.formatHms(_totalDurationSeconds.toInt())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            },
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            onPressed: _previewSelectedSection,
                            icon: const Icon(Icons.play_circle_outline, size: 18),
                            label: const Text('Preview Cut'),
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Range Slider Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Select Video Range', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Clip: ${_formatPreciseDuration(trimmedDuration)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      RangeSlider(
                        values: RangeValues(_startSeconds, _endSeconds),
                        min: 0.0,
                        max: _totalDurationSeconds,
                        divisions: _totalDurationSeconds.toInt() > 0 ? _totalDurationSeconds.toInt() * 2 : 100,
                        labels: RangeLabels(
                          _formatPreciseDuration(_startSeconds),
                          _formatPreciseDuration(_endSeconds),
                        ),
                        onChanged: (RangeValues values) {
                          setState(() {
                            _startSeconds = values.start;
                            _endSeconds = values.end;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Start and End controls
                      Row(
                        children: [
                          // Start Time
                          Expanded(
                            child: _BoundaryControlCard(
                              label: 'Start Cut',
                              timeStr: _formatPreciseDuration(_startSeconds),
                              onMinus: () => _adjustStart(-1.0),
                              onPlus: () => _adjustStart(1.0),
                              onSetCurrent: _setStartToCurrent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // End Time
                          Expanded(
                            child: _BoundaryControlCard(
                              label: 'End Cut',
                              timeStr: _formatPreciseDuration(_endSeconds),
                              onMinus: () => _adjustEnd(-1.0),
                              onPlus: () => _adjustEnd(1.0),
                              onSetCurrent: _setEndToCurrent,
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 32),

                      // Mode Switch (Stream Copy vs Re-encode)
                      SwitchListTile(
                        title: const Text('Frame-Accurate Cut (Re-encode)'),
                        subtitle: Text(
                          _reencode
                              ? 'Cuts at the exact millisecond using libx264.'
                              : 'Fast Cut enabled: Stream copy without quality loss (instant).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        value: _reencode,
                        onChanged: (val) => setState(() => _reencode = val),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // File summary badge
              Text(
                '${_info?.width != null && _info?.height != null ? '${_info!.width}x${_info!.height} • ' : ''}Source: ${widget.sourceFile.path.split(Platform.pathSeparator).last} • ${filesize(_originalSizeBytes)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              const SizedBox(height: 16),

              // Action Button
              FilledButton.icon(
                onPressed: _startTrimming,
                icon: const Icon(Icons.content_cut),
                label: const Text('Trim Video', style: TextStyle(fontSize: 16)),
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

class _BoundaryControlCard extends StatelessWidget {
  final String label;
  final String timeStr;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onSetCurrent;

  const _BoundaryControlCard({
    required this.label,
    required this.timeStr,
    required this.onMinus,
    required this.onPlus,
    required this.onSetCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.remove, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: onMinus,
                tooltip: '-1s',
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: onPlus,
                tooltip: '+1s',
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onSetCurrent,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text('Set Current', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
