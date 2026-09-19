import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

enum VideoFormat {
  mp4,
  mov,
  mkv,
  avi,
  webm;

  String get extension => name;
  String get label => name.toUpperCase();

  String get description {
    switch (this) {
      case VideoFormat.mp4:
        return 'Universal compatibility (H.264 / AAC)';
      case VideoFormat.mov:
        return 'Apple QuickTime format (H.264 / AAC)';
      case VideoFormat.mkv:
        return 'Matroska multimedia container (H.264 / AAC)';
      case VideoFormat.avi:
        return 'Audio Video Interleave (H.264 / MP3)';
      case VideoFormat.webm:
        return 'Modern HTML5 web video (VP9 / Opus)';
    }
  }

  static VideoFormat? fromExtension(String ext) {
    final clean = ext.replaceFirst('.', '').toLowerCase();
    for (final f in VideoFormat.values) {
      if (f.extension == clean) return f;
    }
    return null;
  }
}

enum FormatQuality {
  high,
  medium,
  low;

  String get label {
    switch (this) {
      case FormatQuality.high:
        return 'High Quality';
      case FormatQuality.medium:
        return 'Medium Quality';
      case FormatQuality.low:
        return 'Low / Small File';
    }
  }

  String get description {
    switch (this) {
      case FormatQuality.high:
        return 'Near lossless, larger file size';
      case FormatQuality.medium:
        return 'Balanced quality and file size';
      case FormatQuality.low:
        return 'Maximum compression, smaller file';
    }
  }

  int get h264Crf {
    switch (this) {
      case FormatQuality.high:
        return 18;
      case FormatQuality.medium:
        return 23;
      case FormatQuality.low:
        return 28;
    }
  }

  int get vp9Crf {
    switch (this) {
      case FormatQuality.high:
        return 28;
      case FormatQuality.medium:
        return 33;
      case FormatQuality.low:
        return 40;
    }
  }
}

class FormatProgress {
  final double progress; // 0.0 to 1.0
  final Duration elapsed;
  final Duration? eta;

  const FormatProgress({
    required this.progress,
    required this.elapsed,
    this.eta,
  });
}

class FormatCancelledException implements Exception {
  @override
  String toString() => 'Format conversion was cancelled by the user.';
}

class FormatService {
  bool _cancelled = false;
  Process? _activeWindowsProcess;
  int? _activeAndroidSessionId;
  String? _cachedWindowsFfmpegPath;

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

  /// Converts [sourcePath] video into [targetFormat] saved at [outputPath].
  Stream<FormatProgress> convertFormat({
    required String sourcePath,
    required String outputPath,
    required VideoFormat targetFormat,
    required FormatQuality quality,
    int? targetWidth,
    int? targetHeight,
    required int durationSeconds,
  }) async* {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final args = <String>[
      '-y',
      '-i', sourcePath,
    ];

    // Video scaling filter if custom/preset resolution is specified
    if (targetWidth != null && targetHeight != null && targetWidth > 0 && targetHeight > 0) {
      final w = (targetWidth ~/ 2) * 2;
      final h = (targetHeight ~/ 2) * 2;
      args.addAll(['-vf', 'scale=$w:$h']);
    }

    // Codec and container specific arguments
    switch (targetFormat) {
      case VideoFormat.mp4:
        args.addAll([
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'medium',
          '-crf', quality.h264Crf.toString(),
          '-c:a', 'aac',
          '-b:a', '192k',
          '-movflags', '+faststart',
        ]);
        break;

      case VideoFormat.mov:
        args.addAll([
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'medium',
          '-crf', quality.h264Crf.toString(),
          '-c:a', 'aac',
          '-b:a', '192k',
          '-movflags', '+faststart',
        ]);
        break;

      case VideoFormat.mkv:
        args.addAll([
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'medium',
          '-crf', quality.h264Crf.toString(),
          '-c:a', 'aac',
          '-b:a', '192k',
        ]);
        break;

      case VideoFormat.avi:
        args.addAll([
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'medium',
          '-crf', quality.h264Crf.toString(),
          '-c:a', 'libmp3lame',
          '-b:a', '192k',
        ]);
        break;

      case VideoFormat.webm:
        args.addAll([
          '-c:v', 'libvpx-vp9',
          '-crf', quality.vp9Crf.toString(),
          '-b:v', '0',
          '-c:a', 'libopus',
          '-b:a', '128k',
        ]);
        break;
    }

    args.add(outputPath);

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

    throw UnsupportedError('Video format conversion is not supported on this platform.');
  }

  Stream<FormatProgress> _convertAndroid({
    required List<String> args,
    required int durationSeconds,
    required Stopwatch stopwatch,
  }) async* {
    final controller = StreamController<FormatProgress>();

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

      controller.add(FormatProgress(
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
        throw FormatCancelledException();
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg format conversion failed: $logs');
      }

      controller.add(FormatProgress(
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

  Stream<FormatProgress> _convertWindows({
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

    final controller = StreamController<FormatProgress>();

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

        controller.add(FormatProgress(
          progress: progress,
          elapsed: elapsed,
          eta: eta,
        ));
      } else if (line.startsWith('progress=end')) {
        controller.add(FormatProgress(
          progress: 1.0,
          elapsed: stopwatch.elapsed,
          eta: Duration.zero,
        ));
      }
    });

    final errorBuffer = StringBuffer();
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      errorBuffer.writeln(line);
    });

    try {
      final exitCode = await process.exitCode;
      if (_cancelled) {
        throw FormatCancelledException();
      }

      if (exitCode != 0) {
        throw Exception('FFmpeg failed (exit code $exitCode): ${errorBuffer.toString()}');
      }

      controller.add(FormatProgress(
        progress: 1.0,
        elapsed: stopwatch.elapsed,
        eta: Duration.zero,
      ));
    } finally {
      _activeWindowsProcess = null;
      await controller.close();
    }

    yield* controller.stream;
  }

  Future<String> _resolveWindowsFfmpeg() async {
    if (_cachedWindowsFfmpegPath != null) return _cachedWindowsFfmpegPath!;

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundled = p.join(exeDir, 'ffmpeg', 'bin', 'ffmpeg.exe');
    if (await File(bundled).exists()) {
      _cachedWindowsFfmpegPath = bundled;
      return bundled;
    }

    _cachedWindowsFfmpegPath = 'ffmpeg.exe';
    return 'ffmpeg.exe';
  }
}
