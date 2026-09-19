import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

class FrameRatePreset {
  final String label;
  final String description;
  final double fromFps; // minimum source FPS to enable this preset
  final double targetFps;

  const FrameRatePreset({
    required this.label,
    required this.description,
    required this.fromFps,
    required this.targetFps,
  });

  static const List<FrameRatePreset> all = [
    FrameRatePreset(
      label: '60 FPS → 30 FPS',
      description: 'Halve the frame rate for smaller files',
      fromFps: 50.0,
      targetFps: 30.0,
    ),
    FrameRatePreset(
      label: '30 FPS → 24 FPS',
      description: 'Cinematic frame rate conversion',
      fromFps: 28.0,
      targetFps: 24.0,
    ),
    FrameRatePreset(
      label: '30 FPS → 60 FPS',
      description: 'Increase frame rate via frame interpolation',
      fromFps: 0.0, // always available
      targetFps: 60.0,
    ),
  ];

  /// Returns presets applicable for a given source FPS.
  static List<FrameRatePreset> availableFor(double sourceFps) {
    return all.where((p) => sourceFps >= p.fromFps).toList();
  }
}

class FrameRateProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;

  const FrameRateProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
  });
}

class FrameRateCancelledException implements Exception {
  @override
  String toString() => 'Frame rate conversion was cancelled by the user.';
}

class FrameRateService {
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

  /// Converts video frame rate to [targetFps].
  Stream<FrameRateProgress> convertFrameRate({
    required String sourcePath,
    required String outputPath,
    required double targetFps,
    required int durationSeconds,
  }) async* {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final args = <String>[
      '-y',
      '-i', sourcePath,
      '-r', targetFps.toStringAsFixed(2),
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'medium',
      '-crf', '18',
      '-c:a', 'copy',
      '-movflags', '+faststart',
      outputPath,
    ];

    if (Platform.isAndroid) {
      yield* _convertAndroid(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    if (Platform.isWindows) {
      yield* _convertWindows(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    throw UnsupportedError('Frame rate conversion is not supported on this platform.');
  }

  Stream<FrameRateProgress> _convertAndroid({
    required List<String> args,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<FrameRateProgress>();

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

      controller.add(FrameRateProgress(
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
        throw FrameRateCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg frame rate conversion failed: $logs');
      }

      controller.add(FrameRateProgress(
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

  Stream<FrameRateProgress> _convertWindows({
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

    final controller = StreamController<FrameRateProgress>();

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

        controller.add(FrameRateProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(FrameRateProgress(
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
      throw FrameRateCancelledException();
    }

    if (exitCode != 0) {
      await controller.close();
      throw Exception('FFmpeg frame rate conversion failed: $errorBuffer');
    }

    controller.add(FrameRateProgress(
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
