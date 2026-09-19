enum CompressionMode {
  targetSize,
  preset,
  custom,
}

enum QualityPreset {
  low,     // Maximum compression / smallest size (e.g. ~10-15% original)
  medium,  // Balanced
  high,    // High quality / light compression
}

class VideoResolutionOption {
  final String label;
  final int? width;
  final int? height;

  const VideoResolutionOption({
    required this.label,
    this.width,
    this.height,
  });

  bool get isOriginal => width == null && height == null;

  static const original = VideoResolutionOption(label: 'Original (No change)');
  static const p1080 = VideoResolutionOption(label: '1080p (FHD)', width: 1920, height: 1080);
  static const p720 = VideoResolutionOption(label: '720p (HD)', width: 1280, height: 720);
  static const p480 = VideoResolutionOption(label: '480p (SD)', width: 854, height: 480);
  static const p360 = VideoResolutionOption(label: '360p', width: 640, height: 360);

  static const List<VideoResolutionOption> standardList = [
    original,
    p1080,
    p720,
    p480,
    p360,
  ];
}

class CompressionConfig {
  final CompressionMode mode;
  final double? targetSizeMb;
  final QualityPreset preset;
  final VideoResolutionOption resolution;
  final int? customWidth;
  final int? customHeight;
  final int? customVideoBitrateKbps;
  final int audioBitrateKbps;

  const CompressionConfig({
    this.mode = CompressionMode.targetSize,
    this.targetSizeMb,
    this.preset = QualityPreset.medium,
    this.resolution = VideoResolutionOption.original,
    this.customWidth,
    this.customHeight,
    this.customVideoBitrateKbps,
    this.audioBitrateKbps = 128,
  });

  /// Calculates the video bitrate in kbps needed to achieve [targetSizeMb]
  /// for a video of [durationSeconds].
  static int calculateVideoBitrateKbps({
    required double targetSizeMb,
    required int durationSeconds,
    int audioBitrateKbps = 128,
  }) {
    if (durationSeconds <= 0) return 800;
    // Total bits = targetSizeMb * 8 * 1024 * 1024
    final totalBits = targetSizeMb * 8 * 1024 * 1024;
    final totalBitrateBps = totalBits / durationSeconds;
    final totalBitrateKbps = (totalBitrateBps / 1000).round();

    final videoBitrate = totalBitrateKbps - audioBitrateKbps;
    // Ensure at least 64 kbps minimum for video
    return videoBitrate < 64 ? 64 : videoBitrate;
  }

  /// Estimates the output size in bytes given the duration and bitrates.
  static int estimateOutputSizeBytes({
    required int durationSeconds,
    required int videoBitrateKbps,
    int audioBitrateKbps = 128,
  }) {
    if (durationSeconds <= 0) return 0;
    final totalBitrateKbps = videoBitrateKbps + audioBitrateKbps;
    // (totalBitrateKbps * 1000 * durationSeconds) / 8
    return ((totalBitrateKbps * 1000 * durationSeconds) / 8).round();
  }

  /// Resolves the actual video bitrate (kbps) to use for encoding
  /// based on the selected mode.
  int resolveVideoBitrateKbps({
    required int originalSizeBytes,
    required int durationSeconds,
  }) {
    switch (mode) {
      case CompressionMode.targetSize:
        final targetMb = targetSizeMb ?? ((originalSizeBytes / (1024 * 1024)) * 0.1);
        return calculateVideoBitrateKbps(
          targetSizeMb: targetMb,
          durationSeconds: durationSeconds,
          audioBitrateKbps: audioBitrateKbps,
        );

      case CompressionMode.preset:
        final originalBitrateKbps = durationSeconds > 0
            ? ((originalSizeBytes * 8) / (durationSeconds * 1000)).round()
            : 2000;
        switch (preset) {
          case QualityPreset.low:
            // ~15% of original bitrate (or min 300k)
            return (originalBitrateKbps * 0.15).round().clamp(150, 1500);
          case QualityPreset.medium:
            // ~35% of original bitrate
            return (originalBitrateKbps * 0.35).round().clamp(400, 3500);
          case QualityPreset.high:
            // ~65% of original bitrate
            return (originalBitrateKbps * 0.65).round().clamp(800, 8000);
        }

      case CompressionMode.custom:
        return customVideoBitrateKbps ?? 800;
    }
  }

  /// Resolves the estimated output size in bytes for UI display.
  int resolveEstimatedSizeBytes({
    required int originalSizeBytes,
    required int durationSeconds,
  }) {
    if (mode == CompressionMode.targetSize && targetSizeMb != null) {
      return (targetSizeMb! * 1024 * 1024).round();
    }
    final vBitrate = resolveVideoBitrateKbps(
      originalSizeBytes: originalSizeBytes,
      durationSeconds: durationSeconds,
    );
    return estimateOutputSizeBytes(
      durationSeconds: durationSeconds,
      videoBitrateKbps: vBitrate,
      audioBitrateKbps: audioBitrateKbps,
    );
  }
}
