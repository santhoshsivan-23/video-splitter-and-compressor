import 'dart:io';

import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../services/video_service.dart';
import '../widgets/video_picker.dart';
import 'history_screen.dart';
import 'video_details_screen.dart';

class SplitHomeScreen extends StatefulWidget {
  const SplitHomeScreen({super.key});

  @override
  State<SplitHomeScreen> createState() => _SplitHomeScreenState();
}

class _SplitHomeScreenState extends State<SplitHomeScreen> {
  final _videoService = VideoService();
  final _permissionService = PermissionService();

  File? _selectedFile;
  bool _busy = false;

  Future<void> _pickVideo() async {
    setState(() => _busy = true);
    try {
      final granted = await _permissionService.ensureStoragePermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage/media permission is needed to read and save videos.')),
          );
        }
        return;
      }

      final file = await _videoService.pickVideo();
      if (file == null) return;

      setState(() => _selectedFile = file);

      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => VideoDetailsScreen(sourceFile: file)),
      );
      if (result != null) {
        setState(() => _selectedFile = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open video: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multiple Video Splitting'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Splitting History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.call_split,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Split long videos into smaller clips — entirely offline.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else
                  VideoPickerCard(selectedFile: _selectedFile, onPick: _pickVideo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
