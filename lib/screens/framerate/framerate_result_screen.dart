import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../tools_home_screen.dart';

class FrameRateResultScreen extends StatefulWidget {
  final File sourceFile;
  final File outputFile;
  final int originalSizeBytes;
  final double? originalFps;
  final double targetFps;

  const FrameRateResultScreen({
    super.key,
    required this.sourceFile,
    required this.outputFile,
    required this.originalSizeBytes,
    this.originalFps,
    required this.targetFps,
  });

  @override
  State<FrameRateResultScreen> createState() => _FrameRateResultScreenState();
}

class _FrameRateResultScreenState extends State<FrameRateResultScreen> {
  int _outputSizeBytes = 0;
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
          _outputSizeBytes = size;
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conversion Complete'),
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
                    'Frame Rate Converted!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your video with the new frame rate is ready.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // FPS & Size Card
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
                                  Text('Original FPS', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.originalFps != null
                                        ? widget.originalFps!.toStringAsFixed(2)
                                        : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_forward, size: 24),
                              Column(
                                children: [
                                  Text('Output FPS', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.targetFps.toStringAsFixed(2),
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
                          const Divider(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text('Original Size', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    filesize(widget.originalSizeBytes),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('Output Size', style: Theme.of(context).textTheme.labelMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    filesize(_outputSizeBytes),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // File path
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
