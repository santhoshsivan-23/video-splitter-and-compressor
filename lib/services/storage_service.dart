import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/file_utils.dart';

/// Resolves the platform-appropriate "Video Splitter" root folder, and
/// creates the per-source-video subfolder that each split job writes
/// into. Matches sections 2/3/12/13 of the design: everything lands
/// under the OS Downloads location, visible in the normal file manager
/// / Explorer, with no server or cloud storage involved.
class StorageService {
  static const _appFolderName = 'Video Splitter';

  /// The `.../Download/Video Splitter` (Android) or
  /// `.../Downloads/Video Splitter` (Windows) root, created if missing.
  Future<Directory> getAppRootFolder() async {
    final Directory downloads = await _resolveDownloadsDirectory();
    final root = Directory(p.join(downloads.path, _appFolderName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> _resolveDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // Scoped storage: public Download is a fixed, well-known path on
      // all Android versions, but we still go through path_provider's
      // external storage root first and fall back to the conventional
      // path so this doesn't hard-fail on unusual OEM layouts.
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          // external.path looks like
          // /storage/emulated/0/Android/data/<pkg>/files
          // Walk up to the public /storage/emulated/0 root, then into
          // Download, which is where files should be user-visible.
          final segments = p.split(external.path);
          final androidIndex = segments.indexOf('Android');
          if (androidIndex > 0) {
            final publicRoot = p.joinAll(segments.sublist(0, androidIndex));
            return Directory(p.join(publicRoot, 'Download'));
          }
        }
      } catch (_) {
        // fall through to the hard-coded default below
      }
      return Directory('/storage/emulated/0/Download');
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return Directory(p.join(userProfile, 'Downloads'));
      }
      // Fallback if USERPROFILE isn't set for some reason.
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'Downloads'));
    }

    // Any other desktop platform this ever runs on during development.
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'Downloads'));
  }

  /// Creates `Video Splitter/<Source Name>` (or `_001`, `_002`, ... if
  /// that name is already taken by a previous run).
  Future<Directory> createOutputFolderFor(String originalFileName) async {
    final root = await getAppRootFolder();
    final desiredName = FileUtils.sanitizeFolderName(originalFileName);
    return FileUtils.uniqueVideoFolder(root.path, desiredName);
  }

  /// Returns the `Video Splitter/Compressed` folder, creating it if needed.
  Future<Directory> getCompressedFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'Compressed'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a compressed video,
  /// e.g. `<root>/Compressed/<name>_compressed.mp4`
  Future<String> createCompressedOutputPath(String originalFilePath) async {
    final folder = await getCompressedFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = p.extension(originalFilePath).isNotEmpty ? p.extension(originalFilePath) : '.mp4';
    
    var candidate = p.join(folder.path, '${base}_compressed$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_compressed_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Returns the `Video Splitter/Trimmed` folder, creating it if needed.
  Future<Directory> getTrimmedFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'Trimmed'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a trimmed video,
  /// e.g. `<root>/Trimmed/<name>_trimmed.mp4`
  Future<String> createTrimmedOutputPath(String originalFilePath) async {
    final folder = await getTrimmedFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = p.extension(originalFilePath).isNotEmpty ? p.extension(originalFilePath) : '.mp4';
    
    var candidate = p.join(folder.path, '${base}_trimmed$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_trimmed_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Returns the `Video Splitter/Resized` folder, creating it if needed.
  Future<Directory> getResizedFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'Resized'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a resized video,
  /// e.g. `<root>/Resized/<name>_resized.mp4`
  Future<String> createResizedOutputPath(String originalFilePath) async {
    final folder = await getResizedFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = p.extension(originalFilePath).isNotEmpty ? p.extension(originalFilePath) : '.mp4';
    
    var candidate = p.join(folder.path, '${base}_resized$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_resized_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Returns the `Video Splitter/Flipped` folder, creating it if needed.
  Future<Directory> getFlippedFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'Flipped'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a flipped video.
  Future<String> createFlippedOutputPath(String originalFilePath) async {
    final folder = await getFlippedFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = p.extension(originalFilePath).isNotEmpty ? p.extension(originalFilePath) : '.mp4';
    
    var candidate = p.join(folder.path, '${base}_flipped$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_flipped_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Returns the `Video Splitter/FrameRate` folder, creating it if needed.
  Future<Directory> getFrameRateFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'FrameRate'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a frame-rate-converted video.
  Future<String> createFrameRateOutputPath(String originalFilePath) async {
    final folder = await getFrameRateFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = p.extension(originalFilePath).isNotEmpty ? p.extension(originalFilePath) : '.mp4';
    
    var candidate = p.join(folder.path, '${base}_fps$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_fps_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Returns the `Video Splitter/Converted` folder, creating it if needed.
  Future<Directory> getConvertedFolder() async {
    final root = await getAppRootFolder();
    final folder = Directory(p.join(root.path, 'Converted'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  /// Creates a unique output file path for a format-converted video.
  Future<String> createFormatOutputPath(String originalFilePath, String formatExtension) async {
    final folder = await getConvertedFolder();
    final base = p.basenameWithoutExtension(originalFilePath);
    final ext = formatExtension.startsWith('.') ? formatExtension : '.$formatExtension';
    
    var candidate = p.join(folder.path, '${base}_converted$ext');
    if (!await File(candidate).exists()) {
      return candidate;
    }

    var counter = 1;
    while (true) {
      final suffix = counter.toString().padLeft(3, '0');
      candidate = p.join(folder.path, '${base}_converted_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  /// Lets the user jump straight to Explorer/file manager for a folder.
  /// See ResultScreen / HistoryScreen for the "Open Folder" button.
  Future<bool> folderExists(String path) => Directory(path).exists();
}
