import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

class ResizeProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;

  const ResizeProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
  });
}

class ResizeCancelledException implements Exception {
  @override
  String toString() => 'Video resizing was cancelled by the user.';
}

/// Preset describing a common downscale operation.
class ResizePreset {
  final String label;
  final String description;
  final int fromHeight; // minimum source height to enable this preset
  final int targetWidth;
  final int targetHeight;

  const ResizePreset({
    required this.label,
    required this.description,
    required this.fromHeight,
    required this.targetWidth,
    required this.targetHeight,
  });

  static const List<ResizePreset> all = [
    ResizePreset(
      label: '4K → 1080p',
      description: 'Downscale Ultra-HD to Full-HD',
      fromHeight: 2160,
      targetWidth: 1920,
      targetHeight: 1080,
    ),
    ResizePreset(
      label: '1080p → 720p',
      description: 'Downscale Full-HD to HD',
      fromHeight: 1080,
      targetWidth: 1280,
      targetHeight: 720,
    ),
    ResizePreset(
      label: '720p → 480p',
      description: 'Downscale HD to SD',
      fromHeight: 720,
      targetWidth: 854,
      targetHeight: 480,
    ),
  ];

  /// Returns only the presets that make sense for a source video with
  /// the given [sourceHeight].
  static List<ResizePreset> availableFor(int sourceHeight) {
    return all.where((p) => sourceHeight >= p.fromHeight).toList();
  }
}

class ResizeService {
  bool _cancelled = false;
  Process? _activeWindowsProcess;
  int? _activeAndroidSessionId;

  void cancel() {
    _cancelled = true;
    if (_activeWindowsProcess != null) {
      try {
        _activeWindowsProcess!.kill();
      } catch (_) {}
      _activeWindowsProcess = null;
    }
    if (_activeAndroidSessionId != null) {
      try {
        FFmpegKit.cancel(_activeAndroidSessionId!);
      } catch (_) {}
      _activeAndroidSessionId = null;
    }
  }

  /// Estimates the output size for a resize operation.
  ///
  /// Uses the ratio of output pixels to input pixels as a rough estimate,
  /// since file size scales roughly with pixel count for similar bitrates.
  static int estimateOutputSizeBytes({
    required int originalSizeBytes,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) return originalSizeBytes;
    final sourcePixels = sourceWidth * sourceHeight;
    final targetPixels = targetWidth * targetHeight;
    final ratio = targetPixels / sourcePixels;
    return (originalSizeBytes * ratio).round();
  }

  /// Resizes video to [targetWidth] × [targetHeight].
  /// Uses libx264 + aac with quality-preserving CRF 18 encoding.
  Stream<ResizeProgress> resizeVideo({
    required String sourcePath,
    required String outputPath,
    required int targetWidth,
    required int targetHeight,
    required int durationSeconds,
  }) async* {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    // Use scale filter with -2 for width to ensure divisibility by 2
    // while targeting the requested height.
    final args = <String>[
      '-y',
      '-i', sourcePath,
      '-vf', 'scale=-2:$targetHeight',
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'medium',
      '-crf', '18',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-movflags', '+faststart',
      outputPath,
    ];

    if (Platform.isAndroid) {
      yield* _resizeAndroid(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    if (Platform.isWindows) {
      yield* _resizeWindows(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    throw UnsupportedError('Video resizing is not supported on this platform.');
  }

  Stream<ResizeProgress> _resizeAndroid({
    required List<String> args,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<ResizeProgress>();

    final cmd = args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');

    FFmpegKitConfig.enableStatisticsCallback((stats) {
      if (_cancelled) return;
      final timeMs = stats.getTime();
      final progress = durationSeconds > 0
          ? (timeMs / 1000.0 / durationSeconds).clamp(0.0, 0.99)
          : 0.0;

      final elapsed = stopwatch.elapsed;
      Duration? eta;
      if (progress > 0.05) {
        final totalMs = elapsed.inMilliseconds / progress;
        eta = Duration(milliseconds: (totalMs - elapsed.inMilliseconds).round());
      }

      controller.add(ResizeProgress(
        progress: progress,
        elapsed: elapsed,
        eta: eta,
      ));
    });

    try {
      final session = await FFmpegKit.executeAsync(cmd);
      _activeAndroidSessionId = session.getSessionId();

      final returnCode = await session.getReturnCode();
      if (_cancelled) {
        throw ResizeCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg resizing failed: $logs');
      }

      controller.add(ResizeProgress(
        progress: 1.0,
        elapsed: stopwatch.elapsed,
        eta: Duration.zero,
      ));
    } finally {
      _activeAndroidSessionId = null;
      await controller.close();
    }

    yield* controller.stream;
  }

  Stream<ResizeProgress> _resizeWindows({
    required List<String> args,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final ffmpegPath = await _resolveWindowsFfmpeg();

    final fullArgs = List<String>.from(args);
    final outIndex = fullArgs.length - 1;
    fullArgs.insert(outIndex, '-progress');
    fullArgs.insert(outIndex + 1, 'pipe:1');

    final process = await Process.start(ffmpegPath, fullArgs);
    _activeWindowsProcess = process;

    final controller = StreamController<ResizeProgress>();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_cancelled) return;

      if (line.startsWith('out_time_us=')) {
        final timeUs = int.tryParse(line.substring('out_time_us='.length).trim()) ?? 0;
        final timeSec = timeUs / 1000000.0;
        final progress = durationSeconds > 0
            ? (timeSec / durationSeconds).clamp(0.0, 0.99)
            : 0.0;

        final elapsed = stopwatch.elapsed;
        Duration? eta;
        if (progress > 0.05) {
          final totalMs = elapsed.inMilliseconds / progress;
          eta = Duration(milliseconds: (totalMs - elapsed.inMilliseconds).round());
        }

        controller.add(ResizeProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(ResizeProgress(
          progress: 1.0,
          elapsed: stopwatch.elapsed,
          eta: Duration.zero,
        ));
      }
    });

    final errorBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen((data) {
      errorBuffer.write(data);
    });

    final exitCode = await process.exitCode;
    _activeWindowsProcess = null;

    if (_cancelled) {
      await controller.close();
      throw ResizeCancelledException();
    }

    if (exitCode != 0) {
      await controller.close();
      throw Exception('FFmpeg resizing failed: $errorBuffer');
    }

    controller.add(ResizeProgress(
      progress: 1.0,
      elapsed: stopwatch.elapsed,
      eta: Duration.zero,
    ));

    await controller.close();
    yield* controller.stream;
  }

  Future<String> _resolveWindowsFfmpeg() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundled = p.join(exeDir, 'ffmpeg', 'bin', 'ffmpeg.exe');
    if (await File(bundled).exists()) {
      return bundled;
    }
    return 'ffmpeg.exe';
  }
}
