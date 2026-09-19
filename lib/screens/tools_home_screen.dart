import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../services/video_service.dart';
import 'compression/compression_config_screen.dart';
import 'history_screen.dart';
import 'split_home_screen.dart';
import 'resizing/resize_config_screen.dart';
import 'trimming/trim_config_screen.dart';

class VideoToolItem {
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String badge;
  final VoidCallback onTap;
  final bool isAvailable;

  const VideoToolItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.badge,
    required this.onTap,
    this.isAvailable = true,
  });
}

class ToolsHomeScreen extends StatefulWidget {
  const ToolsHomeScreen({super.key});

  @override
  State<ToolsHomeScreen> createState() => _ToolsHomeScreenState();
}

class _ToolsHomeScreenState extends State<ToolsHomeScreen> {
  final _videoService = VideoService();
  final _permissionService = PermissionService();
  bool _busy = false;

  Future<void> _handleCompressionPick() async {
    setState(() => _busy = true);
    try {
      final granted = await _permissionService.ensureStoragePermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is needed to read videos.')),
          );
        }
        return;
      }

      final file = await _videoService.pickVideo();
      if (file == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CompressionConfigScreen(sourceFile: file),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick video: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleTrimPick() async {
    setState(() => _busy = true);
    try {
      final granted = await _permissionService.ensureStoragePermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is needed to read videos.')),
          );
        }
        return;
      }

      final file = await _videoService.pickVideo();
      if (file == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TrimConfigScreen(sourceFile: file),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick video: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleResizePick() async {
    setState(() => _busy = true);
    try {
      final granted = await _permissionService.ensureStoragePermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is needed to read videos.')),
          );
        }
        return;
      }

      final file = await _videoService.pickVideo();
      if (file == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResizeConfigScreen(sourceFile: file),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick video: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<VideoToolItem> _buildTools(BuildContext context) {
    return [
      VideoToolItem(
        title: 'Multiple Video Splitting',
        description: 'Split long videos into equal clips by duration with fast keyframe stream copy.',
        icon: Icons.call_split,
        accentColor: Colors.indigo,
        badge: 'Offline',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SplitHomeScreen()),
        ),
      ),
      VideoToolItem(
        title: 'Video Compression',
        description: 'Shrink video file sizes (e.g. 300MB → 30MB) with target size, presets & custom bitrate.',
        icon: Icons.compress,
        accentColor: Colors.teal,
        badge: 'Offline',
        onTap: _handleCompressionPick,
      ),
      VideoToolItem(
        title: 'Video Trimming',
        description: 'Cut unwanted beginning/end portions or extract clips with visual player preview.',
        icon: Icons.content_cut,
        accentColor: Colors.deepOrange,
        badge: 'Offline',
        onTap: _handleTrimPick,
      ),
      VideoToolItem(
        title: 'Video Resizing',
        description: 'Downscale resolution with presets (4K→1080p, 1080p→720p, 720p→480p) or custom size.',
        icon: Icons.photo_size_select_large,
        accentColor: Colors.purple,
        badge: 'Offline',
        onTap: _handleResizePick,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tools = _buildTools(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.video_settings, size: 26),
            SizedBox(width: 10),
            Text('Video Tools', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
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
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width > 900
                    ? 3
                    : width > 600
                        ? 2
                        : (width > 420 ? 2 : 1);
                final childAspectRatio = width > 600 ? 1.25 : 1.15;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select a Video Tool',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Local, secure, and fully offline video processing tools.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 24),

                          // Expandable Grid View
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: childAspectRatio,
                            ),
                            itemCount: tools.length,
                            itemBuilder: (context, index) {
                              return _ToolCard(tool: tools[index]);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final VideoToolItem tool;

  const _ToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tool.isAvailable ? tool.onTap : null,
        splashColor: tool.accentColor.withAlpha(40),
        highlightColor: tool.accentColor.withAlpha(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tool.accentColor.withAlpha(25),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tool.accentColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      tool.icon,
                      size: 32,
                      color: tool.accentColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tool.accentColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tool.badge,
                      style: TextStyle(
                        color: tool.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tool.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Open',
                    style: TextStyle(
                      color: tool.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: tool.accentColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
