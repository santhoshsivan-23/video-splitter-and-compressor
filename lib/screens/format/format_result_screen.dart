import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../services/format_service.dart';
import '../tools_home_screen.dart';

class FormatResultScreen extends StatefulWidget {
  final File sourceFile;
  final File outputFile;
  final VideoFormat targetFormat;
  final FormatQuality quality;
  final int originalSizeBytes;
  final int? originalWidth;
  final int? originalHeight;
  final int? targetWidth;
  final int? targetHeight;

  const FormatResultScreen({
    super.key,
    required this.sourceFile,
    required this.outputFile,
    required this.targetFormat,
    required this.quality,
    required this.originalSizeBytes,
    this.originalWidth,
    this.originalHeight,
    this.targetWidth,
    this.targetHeight,
  });

  @override
  State<FormatResultScreen> createState() => _FormatResultScreenState();
}

class _FormatResultScreenState extends State<FormatResultScreen> {
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

  void _copyPath() {
    Clipboard.setData(ClipboardData(text: widget.outputFile.path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Output path copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceExt = p.extension(widget.sourceFile.path).replaceFirst('.', '').toUpperCase();
    final sourceResStr = widget.originalWidth != null && widget.originalHeight != null
        ? '${widget.originalWidth}×${widget.originalHeight}'
        : 'Original';
    final targetResStr = widget.targetWidth != null && widget.targetHeight != null
        ? '${widget.targetWidth}×${widget.targetHeight}'
        : sourceResStr;

    final percentChange = _outputSizeBytes > 0 && widget.originalSizeBytes > 0
        ? ((_outputSizeBytes - widget.originalSizeBytes) / widget.originalSizeBytes * 100).round()
        : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conversion Complete'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
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
                    'Video Converted to ${widget.targetFormat.label}!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.basename(widget.outputFile.path),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                  const SizedBox(height: 28),

                  // Comparison Card
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(64)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('ORIGINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        sourceExt.isNotEmpty ? sourceExt : 'VIDEO',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      filesize(widget.originalSizeBytes),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text(
                                      sourceResStr,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.primary),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('CONVERTED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        widget.targetFormat.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _loading
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(
                                            filesize(_outputSizeBytes),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                    Text(
                                      targetResStr,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (percentChange != null) ...[
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  percentChange < 0 ? Icons.arrow_downward : Icons.arrow_upward,
                                  size: 16,
                                  color: percentChange < 0 ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  percentChange < 0
                                      ? '${percentChange.abs()}% smaller file size'
                                      : '+$percentChange% file size change',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: percentChange < 0 ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Output Path Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(64)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 20, color: Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.outputFile.path,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy Path',
                            onPressed: _copyPath,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Action Buttons
                  FilledButton.icon(
                    onPressed: _openFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Output Folder'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const ToolsHomeScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.home),
                    label: const Text('Back to Video Tools'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
