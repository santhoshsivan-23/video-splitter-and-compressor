/// Helpers for converting between hours/minutes/seconds input and the
/// raw second counts used by FFmpeg and stored in SQLite.
class DurationUtils {
  static int hmsToSeconds({required int hours, required int minutes, required int seconds}) {
    return hours * 3600 + minutes * 60 + seconds;
  }

  static ({int hours, int minutes, int seconds}) secondsToHms(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return (hours: hours, minutes: minutes, seconds: seconds);
  }

  /// Formats seconds as `HH:MM:SS`, matching the timestamps used in the
  /// FFmpeg `-ss` / `-t` arguments and shown throughout the UI.
  static String formatHms(int totalSeconds) {
    final hms = secondsToHms(totalSeconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(hms.hours)}:${two(hms.minutes)}:${two(hms.seconds)}';
  }

  /// Number of parts a video of [videoDurationSeconds] splits into, given
  /// a [splitDurationSeconds] chunk size. The final part may be shorter.
  static int partCount(int videoDurationSeconds, int splitDurationSeconds) {
    if (splitDurationSeconds <= 0) return 0;
    return (videoDurationSeconds / splitDurationSeconds).ceil();
  }

  /// Start time (seconds) and length (seconds) of a given 1-indexed part.
  static ({int start, int length}) partWindow({
    required int partNumber,
    required int videoDurationSeconds,
    required int splitDurationSeconds,
  }) {
    final start = (partNumber - 1) * splitDurationSeconds;
    final remaining = videoDurationSeconds - start;
    final length = remaining < splitDurationSeconds ? remaining : splitDurationSeconds;
    return (start: start, length: length);
  }
}
