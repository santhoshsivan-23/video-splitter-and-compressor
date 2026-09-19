import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';

import '../services/ffmpeg_service.dart';
import '../services/video_service.dart';
import '../utils/duration_utils.dart';
import '../utils/file_utils.dart';
import '../widgets/duration_input.dart';
import '../widgets/split_button.dart';
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

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _videoService.probe(widget.sourceFile.path);
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

    final video = await _videoService.planJob(
      sourceFile: widget.sourceFile,
      info: info,
      splitDurationSeconds: _splitSeconds,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Output: Download/Video Splitter/$fileName/',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SplitButton(enabled: _splitSeconds > 0, onPressed: _startSplit, label: 'SPLIT'),
                  ],
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
