import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/split_part_model.dart';
import '../models/video_model.dart';
import '../services/video_service.dart';
import 'home_screen.dart';

class ResultScreen extends StatefulWidget {
  final VideoModel video;

  const ResultScreen({super.key, required this.video});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _videoService = VideoService();
  List<SplitPartModel> _parts = [];

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    final parts = await _videoService.getParts(widget.video.id!);
    if (mounted) setState(() => _parts = parts);
  }

  Future<void> _openFolder() async {
    final uri = Uri.directory(widget.video.outputFolder);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the folder automatically.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _parts.where((p) => p.status == 'completed').length;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Done'), automaticallyImplyLeading: false),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text('Splitting completed', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('$completedCount files created'),
                  const SizedBox(height: 16),
                  Text('Output:', style: Theme.of(context).textTheme.bodySmall),
                  Text(widget.video.outputFolder, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Folder'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
