import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/ffmpeg_service.dart';
import '../services/video_service.dart';
import '../utils/duration_utils.dart';
import '../utils/file_utils.dart';
import '../widgets/duration_input.dart';
import '../widgets/split_button.dart';
import 'mobile_preview_screen.dart';
import 'splitting_screen.dart';

class VideoDetailsScreen extends StatefulWidget {
  final File sourceFile;

  const VideoDetailsScreen({super.key, required this.sourceFile});

  @override
  State<VideoDetailsScreen> createState() => _VideoDetailsScreenState();
}

class _VideoDetailsScreenState extends State<VideoDetailsScreen> {
  final _videoService = VideoService();

  MediaInfo? _info;
  String? _error;
  bool _loading = true;

  int _hours = 0;
  int _minutes = 4;
  int _seconds = 0;

  // Video Preview & Subtitles
  VideoPlayerController? _playerController;
  bool _isPlaying = false;
  bool _isMuted = false;

  final _topSubtitleController = TextEditingController();
  final _bottomSubtitleController = TextEditingController();
  bool _incrementalTopNumbering = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void dispose() {
    _playerController?.removeListener(_onPlayerTick);
    _playerController?.dispose();
    _topSubtitleController.dispose();
    _bottomSubtitleController.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _videoService.probe(widget.sourceFile.path);

      // Initialize video player for live preview
      final controller = VideoPlayerController.file(widget.sourceFile);
      await controller.initialize();
      controller.addListener(_onPlayerTick);
      controller.setLooping(true);

      setState(() {
        _info = info;
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

  void _openMobilePreview(double aspectRatio, String topText, String bottomText) {
    if (_playerController == null || !_playerController!.value.isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobilePreviewScreen(
          playerController: _playerController!,
          topSubtitle: topText,
          bottomSubtitle: bottomText,
          aspectRatio: aspectRatio,
        ),
      ),
    );
  }

  int get _splitSeconds => DurationUtils.hmsToSeconds(hours: _hours, minutes: _minutes, seconds: _seconds);

  Future<void> _startSplit() async {
    final info = _info;
    if (info == null) return;

    if (_splitSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split duration must be greater than zero.')),
      );
      return;
    }

    final rawTopSub = _topSubtitleController.text.trim();
    final bottomSub = _bottomSubtitleController.text.trim();

    String? topSub;
    if (rawTopSub.isNotEmpty) {
      if (_incrementalTopNumbering) {
        topSub = rawTopSub.contains('{part}') ? rawTopSub : '$rawTopSub {part}';
      } else {
        topSub = rawTopSub;
      }
    }

    final video = await _videoService.planJob(
      sourceFile: widget.sourceFile,
      info: info,
      splitDurationSeconds: _splitSeconds,
      topSubtitle: topSub,
      bottomSubtitle: bottomSub.isNotEmpty ? bottomSub : null,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SplittingScreen(video: video)),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = FileUtils.sanitizeFolderName(widget.sourceFile.path);

    return Scaffold(
      appBar: AppBar(title: const Text('Selected Video')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not read video info:\n$_error', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Existing Section 1: Video Information
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.movie),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.sourceFile.path.split(Platform.pathSeparator).last,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InfoRow('Duration', DurationUtils.formatHms(_info!.durationSeconds)),
                            if (_info!.width != null && _info!.height != null)
                              _InfoRow('Resolution', '${_info!.width} x ${_info!.height}'),
                            FutureBuilder<int>(
                              future: widget.sourceFile.length(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox.shrink();
                                return _InfoRow('Size', filesize(snapshot.data));
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Existing Section 2: Split every Duration
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text('Split every', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            DurationInput(
                              hours: _hours,
                              minutes: _minutes,
                              seconds: _seconds,
                              onHoursChanged: (v) => setState(() => _hours = v),
                              onMinutesChanged: (v) => setState(() => _minutes = v),
                              onSecondsChanged: (v) => setState(() => _seconds = v),
                            ),
                            const SizedBox(height: 12),
                            if (_splitSeconds > 0)
                              Text(
                                '≈ ${DurationUtils.partCount(_info!.durationSeconds, _splitSeconds)} parts will be created',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Existing Section 3: Output Folder
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Output: Download/Video Splitter/$fileName/',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Existing Section 4: SPLIT Button
                    SplitButton(enabled: _splitSeconds > 0, onPressed: _startSplit, label: 'SPLIT'),

                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),

                    // NEW SECTION: Video Preview & Subtitle Settings
                    _buildSubtitlePreviewSection(),
                  ],
                ),
    );
  }

  Widget _buildSubtitlePreviewSection() {
    final topText = _topSubtitleController.text.trim();
    final bottomTemplate = _bottomSubtitleController.text.trim();

    // Resolve top subtitle preview
    final topPreviewText = topText.isNotEmpty
        ? (_incrementalTopNumbering
            ? (topText.contains('{part}') ? topText.replaceAll('{part}', '1') : '$topText 1')
            : topText)
        : (_incrementalTopNumbering ? 'Top Subtitle 1' : 'Top Subtitle');

    // Resolve bottom subtitle preview (using Part 1 as example)
    final bottomPreviewText = bottomTemplate.contains('{part}')
        ? bottomTemplate.replaceAll('{part}', '1')
        : bottomTemplate;

    // Calculate aspect ratio dynamically from video player or probed metadata
    final double aspectRatio;
    if (_playerController != null &&
        _playerController!.value.isInitialized &&
        _playerController!.value.aspectRatio > 0) {
      aspectRatio = _playerController!.value.aspectRatio;
    } else if (_info != null &&
        _info!.width != null &&
        _info!.height != null &&
        _info!.height! > 0) {
      aspectRatio = _info!.width! / _info!.height!;
    } else {
      aspectRatio = 16 / 9;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section Header
            Row(
              children: [
                Icon(Icons.subtitles, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Video Preview & Subtitle Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Add top and bottom subtitles to burn into each generated clip.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 20),

            // Top Subtitle Input
            TextField(
              controller: _topSubtitleController,
              decoration: const InputDecoration(
                labelText: 'Top Subtitle',
                hintText: 'Enter top subtitle (e.g. Birthday)',
                prefixIcon: Icon(Icons.vertical_align_top),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            // Incremental Numbering Toggle
            SwitchListTile(
              title: const Text(
                'Incremental Numbering',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Automatically append part number to Top Subtitle (e.g. Birthday 1, Birthday 2...)',
                style: TextStyle(fontSize: 12),
              ),
              value: _incrementalTopNumbering,
              onChanged: (val) => setState(() => _incrementalTopNumbering = val),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(height: 16),

            // LIVE PORTRAIT VIDEO PREVIEW CONTAINER
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final h = constraints.maxHeight;

                        return Stack(
                          children: [
                            // Full solid black background
                            Container(color: Colors.black),

                            // Video centered vertically and horizontally
                            Center(
                              child: SizedBox(
                                width: double.infinity,
                                child: AspectRatio(
                                  aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (_playerController != null && _playerController!.value.isInitialized)
                                        VideoPlayer(_playerController!)
                                      else
                                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                                      if (!_isPlaying && _playerController != null && _playerController!.value.isInitialized)
                                        Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black45,
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            iconSize: 48,
                                            icon: const Icon(Icons.play_arrow, color: Colors.white),
                                            onPressed: _togglePlayPause,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Top Subtitle at ~10% from top of screen, completely outside video
                            Positioned(
                              top: h * 0.10,
                              left: 16,
                              right: 16,
                              child: Text(
                                topPreviewText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: topText.isNotEmpty ? Colors.white : Colors.white38,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),

                            // Bottom Subtitle at ~10% from bottom of screen, completely outside video
                            Positioned(
                              bottom: h * 0.10,
                              left: 16,
                              right: 16,
                              child: Text(
                                bottomPreviewText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: bottomPreviewText.isNotEmpty ? Colors.white : Colors.white38,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),

                            // Controls bar at bottom
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: const Color(0xCC000000),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    IconButton(
                                      iconSize: 20,
                                      color: Colors.white,
                                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                      onPressed: _togglePlayPause,
                                    ),
                                    IconButton(
                                      iconSize: 20,
                                      color: Colors.white,
                                      icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                                      onPressed: _toggleMute,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      iconSize: 20,
                                      color: Colors.white70,
                                      icon: const Icon(Icons.fullscreen),
                                      tooltip: 'Full Screen Mobile Preview',
                                      onPressed: () => _openMobilePreview(aspectRatio, topPreviewText, bottomPreviewText),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Bottom Subtitle Input
            TextField(
              controller: _bottomSubtitleController,
              decoration: const InputDecoration(
                labelText: 'Bottom Subtitle',
                hintText: 'Enter bottom subtitle (e.g. Video {part})',
                prefixIcon: Icon(Icons.vertical_align_bottom),
                helperText: 'Tip: Use {part} for auto part numbers (e.g. Video 1, Video 2...)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            // Quick Template Chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Video {part}'),
                  onPressed: () {
                    setState(() {
                      _bottomSubtitleController.text = 'Video {part}';
                    });
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Part {part}'),
                  onPressed: () {
                    setState(() {
                      _bottomSubtitleController.text = 'Part {part}';
                    });
                  },
                ),
                if (_bottomSubtitleController.text.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                    onPressed: () {
                      setState(() {
                        _bottomSubtitleController.clear();
                      });
                    },
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // Action Buttons: [ Preview ] and [ SPLIT ]
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMobilePreview(aspectRatio, topPreviewText, bottomPreviewText),
                    icon: const Icon(Icons.smartphone),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _splitSeconds > 0 ? _startSplit : null,
                    icon: const Icon(Icons.movie_filter),
                    label: const Text('SPLIT'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
