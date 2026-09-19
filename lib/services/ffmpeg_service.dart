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
  final double? fps;

  MediaInfo({required this.durationSeconds, this.width, this.height, this.fps});
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
    double? fps;
    final streams = info.getStreams();
    for (final stream in streams) {
      final type = stream.getType();
      if (type == 'video') {
        width = stream.getWidth();
        height = stream.getHeight();
        // Try to parse r_frame_rate (e.g. "30000/1001") or avg_frame_rate
        final props = stream.getAllProperties();
        if (props != null) {
          fps = _parseFps(props['r_frame_rate']?.toString()) ??
                _parseFps(props['avg_frame_rate']?.toString());
        }
        break;
      }
    }

    return MediaInfo(durationSeconds: durationSeconds, width: width, height: height, fps: fps);
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
    double? fps;
    final streams = (json['streams'] as List?) ?? [];
    for (final s in streams) {
      if (s['codec_type'] == 'video') {
        width = s['width'] as int?;
        height = s['height'] as int?;
        fps = _parseFps(s['r_frame_rate']?.toString()) ??
              _parseFps(s['avg_frame_rate']?.toString());
        break;
      }
    }

    return MediaInfo(durationSeconds: durationSeconds, width: width, height: height, fps: fps);
  }

  /// Parses FFmpeg fraction strings like "30000/1001" → 29.97, or "30/1" → 30.0.
  static double? _parseFps(String? raw) {
    if (raw == null || raw.isEmpty || raw == '0/0') return null;
    final parts = raw.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den > 0) {
        return double.parse((num / den).toStringAsFixed(2));
      }
    }
    return double.tryParse(raw);
  }

  /// Cuts one `[startSeconds, startSeconds + lengthSeconds)` window of
  /// [sourcePath] out to [outputPath].
  /// If [topText] or [bottomText] are provided, burns them into the video
  /// with horizontal centering and white font.
  Future<void> extractSegment({
    required String sourcePath,
    required String outputPath,
    required int startSeconds,
    required int lengthSeconds,
    bool reencode = false,
    String? topText,
    String? bottomText,
  }) async {
    final hasTop = topText != null && topText.trim().isNotEmpty;
    final hasBottom = bottomText != null && bottomText.trim().isNotEmpty;
    final hasSubtitles = hasTop || hasBottom;
    final effectiveReencode = reencode || hasSubtitles;

    final filterParts = <String>[];
    if (hasSubtitles) {
      // Pad video to portrait (9:16 aspect ratio) with solid black background, centering video horizontally & vertically
      filterParts.add('pad=max(iw\\,2*trunc((ih*9/16)/2)):max(ih\\,2*trunc((iw*16/9)/2)):(ow-iw)/2:(oh-ih)/2:color=black');

      if (hasTop) {
        final escaped = _escapeDrawText(topText.trim());
        // Top subtitle around 10% from top of screen, completely outside video
        filterParts.add("drawtext=text='$escaped':fontcolor=white:fontsize=h/28:x=(w-text_w)/2:y=h*0.10:shadowcolor=black@0.8:shadowx=2:shadowy=2");
      }
      if (hasBottom) {
        final escaped = _escapeDrawText(bottomText.trim());
        // Bottom subtitle around 10% from bottom of screen, completely outside video
        filterParts.add("drawtext=text='$escaped':fontcolor=white:fontsize=h/28:x=(w-text_w)/2:y=h*0.90-th:shadowcolor=black@0.8:shadowx=2:shadowy=2");
      }
    }

    final args = [
      '-y',
      '-ss', startSeconds.toString(),
      '-i', sourcePath,
      '-t', lengthSeconds.toString(),
      if (hasSubtitles) ...[
        '-vf', filterParts.join(','),
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'medium',
        '-crf', '18',
        '-c:a', 'aac',
      ] else if (!effectiveReencode) ...[
        '-c', 'copy',
      ] else ...[
        '-c:v', 'libx264',
        '-c:a', 'aac',
      ],
      '-avoid_negative_ts', 'make_zero',
      outputPath,
    ];

    if (Platform.isAndroid) {
      final cmd = args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
      final session = await FFmpegKit.execute(cmd);
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

  String _escapeDrawText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll('%', r'\%');
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
