/// Status values used across [VideoModel] and [SplitPartModel].
class ProcessStatus {
  static const pending = 'pending';
  static const processing = 'processing';
  static const completed = 'completed';
  static const failed = 'failed';
  static const cancelled = 'cancelled';
}

/// Represents one row of the `videos` table: a source video the user
/// picked, plus the settings used to split it and where the output went.
class VideoModel {
  final int? id;
  final String originalName;
  final String originalPath;
  final int durationSeconds;
  final int? fileSizeBytes;
  final int? width;
  final int? height;
  final int splitDurationSeconds;
  final String outputFolder;
  final String status;
  final DateTime createdAt;

  VideoModel({
    this.id,
    required this.originalName,
    required this.originalPath,
    required this.durationSeconds,
    this.fileSizeBytes,
    this.width,
    this.height,
    required this.splitDurationSeconds,
    required this.outputFolder,
    required this.status,
    required this.createdAt,
  });

  VideoModel copyWith({
    int? id,
    String? status,
  }) {
    return VideoModel(
      id: id ?? this.id,
      originalName: originalName,
      originalPath: originalPath,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      width: width,
      height: height,
      splitDurationSeconds: splitDurationSeconds,
      outputFolder: outputFolder,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_name': originalName,
      'original_path': originalPath,
      'duration': durationSeconds,
      'file_size': fileSizeBytes,
      'width': width,
      'height': height,
      'split_duration': splitDurationSeconds,
      'output_folder': outputFolder,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory VideoModel.fromMap(Map<String, dynamic> map) {
    return VideoModel(
      id: map['id'] as int?,
      originalName: map['original_name'] as String,
      originalPath: map['original_path'] as String,
      durationSeconds: map['duration'] as int,
      fileSizeBytes: map['file_size'] as int?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      splitDurationSeconds: map['split_duration'] as int,
      outputFolder: map['output_folder'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
