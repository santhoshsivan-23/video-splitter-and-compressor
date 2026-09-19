import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import '../models/compression_config.dart';

class CompressionProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;
  final double? speed;
  final int currentBytes;

  const CompressionProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
    this.speed,
    this.currentBytes = 0,
  });
}

class CompressionCancelledException implements Exception {
  @override
  String toString() => 'Video compression was cancelled by the user.';
}

class CompressionService {
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

  /// Runs the video compression task and yields [CompressionProgress].
  Stream<CompressionProgress> compressVideo({
    required String sourcePath,
    required String outputPath,
    required CompressionConfig config,
    required int originalSizeBytes,
    required int durationSeconds,
  }) async* {
    _cancelled = false;

    final videoBitrateKbps = config.resolveVideoBitrateKbps(
      originalSizeBytes: originalSizeBytes,
      durationSeconds: durationSeconds,
    );

    // Build FFmpeg arguments
    final args = <String>[
      '-y',
      '-i', sourcePath,
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'medium',
      '-b:v', '${videoBitrateKbps}k',
      '-maxrate', '${(videoBitrateKbps * 1.5).round()}k',
      '-bufsize', '${(videoBitrateKbps * 2).round()}k',
      '-c:a', 'aac',
      '-b:a', '${config.audioBitrateKbps}k',
    ];

    // Handle resolution scaling
    if (!config.resolution.isOriginal && config.resolution.height != null) {
      args.addAll(['-vf', 'scale=-2:${config.resolution.height}']);
    } else if (config.customWidth != null && config.customHeight != null) {
      args.addAll(['-vf', 'scale=${config.customWidth}:${config.customHeight}']);
    }

    args.addAll([
      '-movflags', '+faststart',
      outputPath,
    ]);

    final stopwatch = Stopwatch()..start();

    if (Platform.isAndroid) {
      yield* _compressAndroid(
        args: args,
        outputPath: outputPath,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    if (Platform.isWindows) {
      yield* _compressWindows(
        args: args,
        outputPath: outputPath,
        durationSeconds: durationSeconds,
        stopwatch: stopwatch,
      );
      return;
    }

    throw UnsupportedError('Video compression is not supported on this platform.');
  }

  Stream<CompressionProgress> _compressAndroid({
    required List<String> args,
    required String outputPath,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<CompressionProgress>();

    // Escape arguments for FFmpegKit string command
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
        final totalEstimatedMs = elapsed.inMilliseconds / progress;
        final remainingMs = totalEstimatedMs - elapsed.inMilliseconds;
        eta = Duration(milliseconds: remainingMs.round());
      }

      controller.add(CompressionProgress(
        progress: progress,
        elapsed: elapsed,
        eta: eta,
        speed: stats.getSpeed(),
        currentBytes: stats.getSize(),
      ));
    });

    try {
      final session = await FFmpegKit.executeAsync(cmd);
      _activeAndroidSessionId = session.getSessionId();

      final returnCode = await session.getReturnCode();
      if (_cancelled) {
        throw CompressionCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg compression failed: $logs');
      }

      controller.add(CompressionProgress(
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

  Stream<CompressionProgress> _compressWindows({
    required List<String> args,
    required String outputPath,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final ffmpegPath = await _resolveWindowsFfmpeg();

    // Insert -progress pipe:1 before outputPath
    final fullArgs = List<String>.from(args);
    final outIndex = fullArgs.length - 1;
    fullArgs.insert(outIndex, '-progress');
    fullArgs.insert(outIndex + 1, 'pipe:1');

    final process = await Process.start(ffmpegPath, fullArgs);
    _activeWindowsProcess = process;

    final controller = StreamController<CompressionProgress>();

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

        controller.add(CompressionProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(CompressionProgress(
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
      throw CompressionCancelledException();
    }

    if (exitCode != 0) {
      await controller.close();
      throw Exception('FFmpeg compression failed: $errorBuffer');
    }

    controller.add(CompressionProgress(
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
