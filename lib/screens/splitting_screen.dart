import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../services/video_service.dart';
import '../widgets/progress_widget.dart';
import 'result_screen.dart';

class SplittingScreen extends StatefulWidget {
  final VideoModel video;

  const SplittingScreen({super.key, required this.video});

  @override
  State<SplittingScreen> createState() => _SplittingScreenState();
}

class _SplittingScreenState extends State<SplittingScreen> {
  final _videoService = VideoService();

  SplitProgress? _progress;
  String? _error;
  bool _cancelled = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await for (final progress in _videoService.runSplit(widget.video)) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }
      if (!mounted) return;
      setState(() => _done = true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultScreen(video: widget.video)),
      );
    } on SplitCancelledException {
      if (!mounted) return;
      setState(() => _cancelled = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _cancel() {
    _videoService.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent an accidental back-swipe from abandoning a running job
      // without properly cancelling and updating SQLite's status.
      canPop: _done || _cancelled || _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Splitting')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: _error != null
                ? _ErrorState(message: _error!)
                : _cancelled
                    ? const _CancelledState()
                    : _progress == null
                        ? const CircularProgressIndicator()
                        : SplitProgressCard(progress: _progress!, onCancel: _cancel),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        const Text('Splitting failed', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}

class _CancelledState extends StatelessWidget {
  const _CancelledState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cancel_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('Splitting cancelled'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}
