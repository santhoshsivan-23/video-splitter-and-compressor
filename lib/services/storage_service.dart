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

  /// Lets the user jump straight to Explorer/file manager for a folder.
  /// See ResultScreen / HistoryScreen for the "Open Folder" button.
  Future<bool> folderExists(String path) => Directory(path).exists();
}
