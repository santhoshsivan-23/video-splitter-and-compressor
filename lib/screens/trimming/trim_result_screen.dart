import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../tools_home_screen.dart';

class TrimResultScreen extends StatefulWidget {
  final File sourceFile;
  final File outputFile;
  final double startSeconds;
  final double endSeconds;
  final int originalSizeBytes;

  const TrimResultScreen({
    super.key,
    required this.sourceFile,
    required this.outputFile,
    required this.startSeconds,
    required this.endSeconds,
    required this.originalSizeBytes,
  });

  @override
  State<TrimResultScreen> createState() => _TrimResultScreenState();
}

class _TrimResultScreenState extends State<TrimResultScreen> {
  int _trimmedSizeBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFileStats();
  }

  Future<void> _loadFileStats() async {
    try {
      if (await widget.outputFile.exists()) {
        final size = await widget.outputFile.length();
        setState(() {
          _trimmedSizeBytes = size;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openFolder() async {
    final folderPath = p.dirname(widget.outputFile.path);
    final uri = Uri.directory(folderPath);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open folder automatically.')),
        );
      }
    }
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
    final clipDuration = (widget.endSeconds - widget.startSeconds).clamp(0.0, double.infinity);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trim Complete'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 64),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Video Successfully Trimmed!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your trimmed clip is ready to use.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Clip Details Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(140),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text('Clip Duration', style: Theme.of(context).textTheme.labelMedium),
                                const SizedBox(height: 4),
                                Text(
                                  _formatPreciseDuration(clipDuration),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            Container(width: 1, height: 36, color: Theme.of(context).colorScheme.outlineVariant),
                            Column(
                              children: [
                                Text('Clip Size', style: Theme.of(context).textTheme.labelMedium),
                                const SizedBox(height: 4),
                                Text(
                                  _loading ? '...' : filesize(_trimmedSizeBytes),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Cut Range:',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              '${_formatPreciseDuration(widget.startSeconds)} → ${_formatPreciseDuration(widget.endSeconds)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Original Size:',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              filesize(widget.originalSizeBytes),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // File Location Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.outputFile.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy Path',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: widget.outputFile.path));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('File path copied to clipboard!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Output Folder'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const ToolsHomeScreen()),
                        (route) => false,
                      ),
                      icon: const Icon(Icons.home),
                      label: const Text('Back to Video Tools'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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
