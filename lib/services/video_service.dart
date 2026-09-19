import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../database/split_part_dao.dart';
import '../database/video_dao.dart';
import '../models/split_part_model.dart';
import '../models/video_model.dart';
import '../utils/duration_utils.dart';
import '../utils/file_utils.dart';
import 'ffmpeg_service.dart';
import 'storage_service.dart';

/// Progress snapshot emitted while a split job runs, mirroring section
/// 18 of the design (part N / total, elapsed, remaining estimate).
class SplitProgress {
  final int currentPart;
  final int totalParts;
  final String currentFileName;
  final Duration elapsed;
  final Duration? estimatedRemaining;

  SplitProgress({
    required this.currentPart,
    required this.totalParts,
    required this.currentFileName,
    required this.elapsed,
    this.estimatedRemaining,
  });

  double get fraction => totalParts == 0 ? 0 : currentPart / totalParts;
}

class SplitCancelledException implements Exception {}

/// Ties file_picker + FFmpegService + StorageService + the DAOs
/// together: pick a source file, read its metadata, plan the parts,
/// then run the split job while writing progress into SQLite as it goes
/// so an interrupted run leaves an accurate `failed`/`cancelled` status
/// instead of a silently stuck `processing` row.
class VideoService {
  final _ffmpeg = FFmpegService();
  final _storage = StorageService();
  final _videoDao = VideoDao();
  final _partDao = SplitPartDao();

  bool _cancelRequested = false;

  Future<File?> pickVideo() async {
    final file = await FilePicker.pickFile(
      type: FileType.video,
    );
    if (file == null || file.path == null) return null;
    return File(file.path!);
  }

  Future<MediaInfo> probe(String path) => _ffmpeg.probe(path);

  /// Creates the `videos` row and pre-plans (but doesn't yet write) the
  /// `split_parts` rows, so the UI can show "30 parts" before splitting
  /// actually starts.
  Future<VideoModel> planJob({
    required File sourceFile,
    required MediaInfo info,
    required int splitDurationSeconds,
  }) async {
    final outputFolder = await _storage.createOutputFolderFor(sourceFile.path);

    final video = VideoModel(
      originalName: p.basename(sourceFile.path),
      originalPath: sourceFile.path,
      durationSeconds: info.durationSeconds,
      fileSizeBytes: await sourceFile.length(),
      width: info.width,
      height: info.height,
      splitDurationSeconds: splitDurationSeconds,
      outputFolder: outputFolder.path,
      status: ProcessStatus.pending,
      createdAt: DateTime.now(),
    );

    final id = await _videoDao.insert(video);
    return video.copyWith(id: id);
  }

  void cancel() => _cancelRequested = true;

  /// Runs the whole split job part by part, yielding [SplitProgress]
  /// after each completed part so the caller can drive a progress bar.
  /// Throws [SplitCancelledException] if `cancel()` was called mid-run.
  Stream<SplitProgress> runSplit(VideoModel video) async* {
    _cancelRequested = false;
    final stopwatch = Stopwatch()..start();

    await _videoDao.updateStatus(video.id!, ProcessStatus.processing);

    final sourceExt = p.extension(video.originalPath);
    final totalParts = DurationUtils.partCount(video.durationSeconds, video.splitDurationSeconds);

    try {
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        if (_cancelRequested) {
          await _videoDao.updateStatus(video.id!, ProcessStatus.cancelled);
          throw SplitCancelledException();
        }

        final window = DurationUtils.partWindow(
          partNumber: partNumber,
          videoDurationSeconds: video.durationSeconds,
          splitDurationSeconds: video.splitDurationSeconds,
        );

        final fileName = FileUtils.partFileName(partNumber, sourceExt);
        final outputPath = p.join(video.outputFolder, fileName);

        final partModel = SplitPartModel(
          videoId: video.id!,
          partNumber: partNumber,
          fileName: fileName,
          filePath: outputPath,
          startTimeSeconds: window.start,
          durationSeconds: window.length,
          status: ProcessStatus.processing,
        );
        final partId = await _partDao.insert(partModel);

        try {
          await _ffmpeg.extractSegment(
            sourcePath: video.originalPath,
            outputPath: outputPath,
            startSeconds: window.start,
            lengthSeconds: window.length,
          );
          final size = await FileUtils.fileSizeOrNull(outputPath);
          await _partDao.updateStatus(partId, ProcessStatus.completed, fileSizeBytes: size);
        } catch (e) {
          await _partDao.updateStatus(partId, ProcessStatus.failed);
          await _videoDao.updateStatus(video.id!, ProcessStatus.failed);
          rethrow;
        }

        final elapsed = stopwatch.elapsed;
        final avgPerPart = elapsed.inMilliseconds / partNumber;
        final remainingParts = totalParts - partNumber;
        final estimatedRemaining = Duration(milliseconds: (avgPerPart * remainingParts).round());

        yield SplitProgress(
          currentPart: partNumber,
          totalParts: totalParts,
          currentFileName: fileName,
          elapsed: elapsed,
          estimatedRemaining: partNumber < totalParts ? estimatedRemaining : Duration.zero,
        );
      }

      await _videoDao.updateStatus(video.id!, ProcessStatus.completed);
    } on SplitCancelledException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<List<SplitPartModel>> getParts(int videoId) => _partDao.getByVideoId(videoId);

  Future<List<VideoModel>> getHistory() => _videoDao.getAll();

  /// Deletes the history record, and optionally the generated files on
  /// disk (section 19: "Delete history" vs "Delete generated files").
  Future<void> deleteHistoryEntry(VideoModel video, {required bool alsoDeleteFiles}) async {
    await _partDao.deleteByVideoId(video.id!);
    await _videoDao.delete(video.id!);
    if (alsoDeleteFiles) {
      final dir = Directory(video.outputFolder);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }
}
