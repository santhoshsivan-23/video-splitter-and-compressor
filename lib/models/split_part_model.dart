/// Represents one row of the `split_parts` table: a single output clip
/// produced from a source [VideoModel].
class SplitPartModel {
  final int? id;
  final int videoId;
  final int partNumber;
  final String fileName;
  final String filePath;
  final int startTimeSeconds;
  final int durationSeconds;
  final int? fileSizeBytes;
  final String status;

  SplitPartModel({
    this.id,
    required this.videoId,
    required this.partNumber,
    required this.fileName,
    required this.filePath,
    required this.startTimeSeconds,
    required this.durationSeconds,
    this.fileSizeBytes,
    required this.status,
  });

  SplitPartModel copyWith({
    int? id,
    String? status,
    int? fileSizeBytes,
  }) {
    return SplitPartModel(
      id: id ?? this.id,
      videoId: videoId,
      partNumber: partNumber,
      fileName: fileName,
      filePath: filePath,
      startTimeSeconds: startTimeSeconds,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'video_id': videoId,
      'part_number': partNumber,
      'file_name': fileName,
      'file_path': filePath,
      'start_time': startTimeSeconds,
      'duration': durationSeconds,
      'file_size': fileSizeBytes,
      'status': status,
    };
  }

  factory SplitPartModel.fromMap(Map<String, dynamic> map) {
    return SplitPartModel(
      id: map['id'] as int?,
      videoId: map['video_id'] as int,
      partNumber: map['part_number'] as int,
      fileName: map['file_name'] as String,
      filePath: map['file_path'] as String,
      startTimeSeconds: map['start_time'] as int,
      durationSeconds: map['duration'] as int,
      fileSizeBytes: map['file_size'] as int?,
      status: map['status'] as String,
    );
  }
}
