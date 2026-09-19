import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

/// Basic metadata pulled from the source file before splitting.
class MediaInfo {
  final int durationSeconds;
  final int? width;
  final int? height;

  MediaInfo({required this.durationSeconds, this.width, this.height});
}

/// Wraps FFmpeg/FFprobe access for both supported platforms.
///
/// - Android: uses `ffmpeg_kit_flutter_new`, a self-contained native
///   binary bundled inside the plugin - nothing to install.
/// - Windows: this plugin has no desktop build, so we shell out to a
///   real `ffmpeg.exe` / `ffprobe.exe`. Ship them under
///   `windows/ffmpeg/bin/` next to the built .exe (see README), or make
///   sure they're on the user's PATH - either is detected automatically.
///
/// Splitting uses stream copy (`-c copy`) by default so there is no
/// re-encoding generation loss, per the design doc. Because copy cuts
/// snap to the nearest keyframe, very precise frame-accurate boundaries
/// would require `reencode: true`, which is exposed for that case.
class FFmpegService {
  String? _cachedWindowsFfmpegPath;
  String? _cachedWindowsFfprobePath;

  Future<MediaInfo> probe(String sourcePath) async {
    if (Platform.isAndroid) {
      return _probeAndroid(sourcePath);
    }
    if (Platform.isWindows) {
      return _probeWindows(sourcePath);
    }
    throw UnsupportedError('Unsupported platform for video probing.');
  }

  Future<MediaInfo> _probeAndroid(String sourcePath) async {
    final session = await FFprobeKit.getMediaInformation(sourcePath);
    final info = session.getMediaInformation();
    if (info == null) {
      throw Exception('Could not read video information.');
    }

    final durationStr = info.getDuration();
    final durationSeconds = durationStr != null
        ? double.tryParse(durationStr)?.round() ?? 0
        : 0;

    int? width;
    int? height;
    final streams = info.getStreams();
    for (final stream in streams) {
      final type = stream.getType();
      if (type == 'video') {
        width = stream.getWidth();
        height = stream.getHeight();
        break;
      }
    }

    return MediaInfo(durationSeconds: durationSeconds, width: width, height: height);
  }

  Future<MediaInfo> _probeWindows(String sourcePath) async {
    final ffprobePath = await _resolveWindowsBinary('ffprobe.exe');
    final result = await Process.run(ffprobePath, [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      sourcePath,
    ]);

    if (result.exitCode != 0) {
      throw Exception('ffprobe failed: ${result.stderr}');
    }

    final Map<String, dynamic> json = jsonDecode(result.stdout as String);
    final format = json['format'] as Map<String, dynamic>?;
    final durationSeconds = format != null && format['duration'] != null
        ? double.tryParse(format['duration'].toString())?.round() ?? 0
        : 0;

    int? width;
    int? height;
    final streams = (json['streams'] as List?) ?? [];
    for (final s in streams) {
      if (s['codec_type'] == 'video') {
        width = s['width'] as int?;
        height = s['height'] as int?;
        break;
      }
    }

    return MediaInfo(durationSeconds: durationSeconds, width: width, height: height);
  }

  /// Cuts one `[startSeconds, startSeconds + lengthSeconds)` window of
  /// [sourcePath] out to [outputPath]. Reports nothing itself; the
  /// caller (SplittingScreen) tracks part N / total for progress, since
  /// each part is one discrete ffmpeg process.
  Future<void> extractSegment({
    required String sourcePath,
    required String outputPath,
    required int startSeconds,
    required int lengthSeconds,
    bool reencode = false,
  }) async {
    final args = [
      '-y',
      '-ss', startSeconds.toString(),
      '-i', sourcePath,
      '-t', lengthSeconds.toString(),
      if (!reencode) ...['-c', 'copy'] else ...['-c:v', 'libx264', '-c:a', 'aac'],
      '-avoid_negative_ts', 'make_zero',
      outputPath,
    ];

    if (Platform.isAndroid) {
      final session = await FFmpegKit.execute('-y -ss $startSeconds -i "$sourcePath" -t '
          '$lengthSeconds ${reencode ? '-c:v libx264 -c:a aac' : '-c copy'} '
          '-avoid_negative_ts make_zero "$outputPath"');
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg failed for part at $outputPath: $logs');
      }
      return;
    }

    if (Platform.isWindows) {
      final ffmpegPath = await _resolveWindowsBinary('ffmpeg.exe');
      final result = await Process.run(ffmpegPath, args);
      if (result.exitCode != 0) {
        throw Exception('FFmpeg failed for part at $outputPath: ${result.stderr}');
      }
      return;
    }

    throw UnsupportedError('Unsupported platform for splitting.');
  }

  Future<String> _resolveWindowsBinary(String exeName) async {
    if (exeName == 'ffmpeg.exe' && _cachedWindowsFfmpegPath != null) {
      return _cachedWindowsFfmpegPath!;
    }
    if (exeName == 'ffprobe.exe' && _cachedWindowsFfprobePath != null) {
      return _cachedWindowsFfprobePath!;
    }

    // 1) Look next to the running executable, in ffmpeg/bin/<exe>.
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundled = p.join(exeDir, 'ffmpeg', 'bin', exeName);
    if (await File(bundled).exists()) {
      _cache(exeName, bundled);
      return bundled;
    }

    // 2) Fall back to whatever is on PATH; Process.run will throw a
    // clear ProcessException if it truly isn't installed anywhere.
    _cache(exeName, exeName);
    return exeName;
  }

  void _cache(String exeName, String resolved) {
    if (exeName == 'ffmpeg.exe') {
      _cachedWindowsFfmpegPath = resolved;
    } else {
      _cachedWindowsFfprobePath = resolved;
    }
  }
}
