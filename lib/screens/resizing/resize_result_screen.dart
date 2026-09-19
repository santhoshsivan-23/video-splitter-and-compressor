import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../tools_home_screen.dart';

class ResizeResultScreen extends StatefulWidget {
  final File sourceFile;
  final File outputFile;
  final int originalSizeBytes;
  final int targetWidth;
  final int targetHeight;

  const ResizeResultScreen({
    super.key,
    required this.sourceFile,
    required this.outputFile,
    required this.originalSizeBytes,
    required this.targetWidth,
    required this.targetHeight,
  });

  @override
  State<ResizeResultScreen> createState() => _ResizeResultScreenState();
}

class _ResizeResultScreenState extends State<ResizeResultScreen> {
  int _resizedSizeBytes = 0;
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
          _resizedSizeBytes = size;
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

  @override
  Widget build(BuildContext context) {
    final reduction = widget.originalSizeBytes > 0 && _resizedSizeBytes > 0
        ? (((widget.originalSizeBytes - _resizedSizeBytes) / widget.originalSizeBytes) * 100).clamp(0.0, 99.9)
        : 0.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Resize Complete'),
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
                    'Video Successfully Resized!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your resized video is ready to use.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Comparison Card
                  if (!_loading)
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
                                  Text('Original Size', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    filesize(widget.originalSizeBytes),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_forward, size: 24),
                              Column(
                                children: [
                                  Text('Resized Size', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    filesize(_resizedSizeBytes),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Output: ${widget.targetWidth} × ${widget.targetHeight}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (reduction > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade700,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '-${reduction.toStringAsFixed(1)}% Smaller',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
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
