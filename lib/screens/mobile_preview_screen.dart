import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MobilePreviewScreen extends StatefulWidget {
  final VideoPlayerController playerController;
  final String topSubtitle;
  final String bottomSubtitle;
  final double aspectRatio;

  const MobilePreviewScreen({
    super.key,
    required this.playerController,
    required this.topSubtitle,
    required this.bottomSubtitle,
    required this.aspectRatio,
  });

  @override
  State<MobilePreviewScreen> createState() => _MobilePreviewScreenState();
}

class _MobilePreviewScreenState extends State<MobilePreviewScreen> {
  bool _isPlaying = true;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.playerController.value.isPlaying;
    widget.playerController.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final isPlaying = widget.playerController.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  void _togglePlayPause() {
    if (widget.playerController.value.isPlaying) {
      widget.playerController.pause();
    } else {
      widget.playerController.play();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      widget.playerController.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight;

                  return Stack(
                    children: [
                      // Video centered vertically and horizontally
                      Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: AspectRatio(
                            aspectRatio: widget.aspectRatio > 0 ? widget.aspectRatio : 16 / 9,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(widget.playerController),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _togglePlayPause,
                                  child: Center(
                                    child: AnimatedOpacity(
                                      opacity: !_isPlaying ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          size: 48,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Top Subtitle at ~10% from top of screen, completely outside video
                      Positioned(
                        top: height * 0.10,
                        left: 20,
                        right: 20,
                        child: Text(
                          widget.topSubtitle.isNotEmpty ? widget.topSubtitle : '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      // Bottom Subtitle at ~10% from bottom of screen, completely outside video
                      Positioned(
                        bottom: height * 0.10,
                        left: 20,
                        right: 20,
                        child: Text(
                          widget.bottomSubtitle.isNotEmpty ? widget.bottomSubtitle : '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      // Top Header Bar (Back button)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Back',
                        ),
                      ),

                      // Bottom Controls Overlay
                      Positioned(
                        bottom: 8,
                        left: 16,
                        right: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                              onPressed: _togglePlayPause,
                            ),
                            IconButton(
                              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                              onPressed: _toggleMute,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                              label: const Text('Close Preview', style: TextStyle(color: Colors.white70)),
                            ),
                          ],
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
    );
  }
}
