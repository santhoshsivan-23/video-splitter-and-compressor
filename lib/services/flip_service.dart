import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

enum FlipDirection {
  horizontal,
  vertical,
}

class FlipProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;

  const FlipProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
  });
}

class FlipCancelledException implements Exception {
  @override
  String toString() => 'Video flipping was cancelled by the user.';
}

class FlipService {
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

  /// Flips video horizontally or vertically.
  Stream<FlipProgress> flipVideo({
    required String sourcePath,
    required String outputPath,
    required FlipDirection direction,
    required int durationSeconds,
  }) async* {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final vf = direction == FlipDirection.horizontal ? 'hflip' : 'vflip';

    final args = <String>[
      '-y',
      '-i', sourcePath,
      '-vf', vf,
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'medium',
      '-crf', '18',
      '-c:a', 'copy',
      '-movflags', '+faststart',
      outputPath,
    ];

    if (Platform.isAndroid) {
      yield* _flipAndroid(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    if (Platform.isWindows) {
      yield* _flipWindows(
        args: args,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    throw UnsupportedError('Video flipping is not supported on this platform.');
  }

  Stream<FlipProgress> _flipAndroid({
    required List<String> args,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<FlipProgress>();

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

      controller.add(FlipProgress(
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
        throw FlipCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg flip failed: $logs');
      }

      controller.add(FlipProgress(
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

  Stream<FlipProgress> _flipWindows({
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

    final controller = StreamController<FlipProgress>();

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

        controller.add(FlipProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(FlipProgress(
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
      throw FlipCancelledException();
    }

    if (exitCode != 0) {
      await controller.close();
      throw Exception('FFmpeg flip failed: $errorBuffer');
    }

    controller.add(FlipProgress(
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
