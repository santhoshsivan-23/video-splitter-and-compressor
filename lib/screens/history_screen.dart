import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/video_model.dart';
import '../services/video_service.dart';
import '../utils/duration_utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _videoService = VideoService();
  List<VideoModel> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final history = await _videoService.getHistory();
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  Future<void> _openFolder(VideoModel video) async {
    final uri = Uri.directory(video.outputFolder);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the folder. It may have been moved or deleted.')),
      );
    }
  }

  Future<void> _confirmDelete(VideoModel video) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Remove "${video.originalName}" from history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'history_only'),
            child: const Text('History only'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'history_and_files'),
            child: const Text('History + files', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (choice == null) return;
    await _videoService.deleteHistoryEntry(video, alsoDeleteFiles: choice == 'history_and_files');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No videos split yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final video = _history[index];
                    final parts = DurationUtils.partCount(video.durationSeconds, video.splitDurationSeconds);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    video.originalName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _StatusChip(status: video.status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${DurationUtils.formatHms(video.durationSeconds)} • $parts parts • '
                              'split every ${DurationUtils.formatHms(video.splitDurationSeconds)}'
                              '${video.fileSizeBytes != null ? ' • ${filesize(video.fileSizeBytes)}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () => _openFolder(video),
                                  icon: const Icon(Icons.folder_open, size: 18),
                                  label: const Text('Open Folder'),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _confirmDelete(video),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color _color() {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: _color(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
