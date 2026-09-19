import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

class TrimProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;

  const TrimProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
  });
}

class TrimCancelledException implements Exception {
  @override
  String toString() => 'Video trimming was cancelled by the user.';
}

class TrimService {
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

  /// Trims video from [startSeconds] to [endSeconds].
  /// If [reencode] is false, uses fast keyframe stream copy (-c copy).
  /// If [reencode] is true, uses frame-accurate re-encoding (-c:v libx264 -c:a aac).
  Stream<TrimProgress> trimVideo({
    required String sourcePath,
    required String outputPath,
    required double startSeconds,
    required double endSeconds,
    bool reencode = false,
  }) async* {
    _cancelled = false;
    final lengthSeconds = (endSeconds - startSeconds).clamp(0.1, double.infinity);
    final stopwatch = Stopwatch()..start();

    final args = <String>[
      '-y',
      '-ss', startSeconds.toStringAsFixed(3),
      '-i', sourcePath,
      '-t', lengthSeconds.toStringAsFixed(3),
      if (!reencode) ...[
        '-c', 'copy',
        '-avoid_negative_ts', 'make_zero',
      ] else ...[
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'medium',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
      ],
      outputPath,
    ];

    if (Platform.isAndroid) {
      yield* _trimAndroid(
        args: args,
        lengthSeconds: lengthSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    if (Platform.isWindows) {
      yield* _trimWindows(
        args: args,
        lengthSeconds: lengthSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    throw UnsupportedError('Video trimming is not supported on this platform.');
  }

  Stream<TrimProgress> _trimAndroid({
    required List<String> args,
    required double lengthSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<TrimProgress>();

    final cmd = args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');

    FFmpegKitConfig.enableStatisticsCallback((stats) {
      if (_cancelled) return;
      final timeMs = stats.getTime();
      final progress = lengthSeconds > 0
          ? (timeMs / 1000.0 / lengthSeconds).clamp(0.0, 0.99)
          : 0.0;

      final elapsed = stopwatch.elapsed;
      Duration? eta;
      if (progress > 0.05) {
        final totalMs = elapsed.inMilliseconds / progress;
        eta = Duration(milliseconds: (totalMs - elapsed.inMilliseconds).round());
      }

      controller.add(TrimProgress(
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
        throw TrimCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg trimming failed: $logs');
      }

      controller.add(TrimProgress(
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

  Stream<TrimProgress> _trimWindows({
    required List<String> args,
    required double lengthSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final ffmpegPath = await _resolveWindowsFfmpeg();

    final fullArgs = List<String>.from(args);
    final outIndex = fullArgs.length - 1;
    fullArgs.insert(outIndex, '-progress');
    fullArgs.insert(outIndex + 1, 'pipe:1');

    final process = await Process.start(ffmpegPath, fullArgs);
    _activeWindowsProcess = process;

    final controller = StreamController<TrimProgress>();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_cancelled) return;

      if (line.startsWith('out_time_us=')) {
        final timeUs = int.tryParse(line.substring('out_time_us='.length).trim()) ?? 0;
        final timeSec = timeUs / 1000000.0;
        final progress = lengthSeconds > 0
            ? (timeSec / lengthSeconds).clamp(0.0, 0.99)
            : 0.0;

        final elapsed = stopwatch.elapsed;
        Duration? eta;
        if (progress > 0.05) {
          final totalMs = elapsed.inMilliseconds / progress;
          eta = Duration(milliseconds: (totalMs - elapsed.inMilliseconds).round());
        }

        controller.add(TrimProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(TrimProgress(
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
      throw TrimCancelledException();
    }

    if (exitCode != 0) {
      await controller.close();
      throw Exception('FFmpeg trimming failed: $errorBuffer');
    }

    controller.add(TrimProgress(
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
