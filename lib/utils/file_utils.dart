import 'dart:io';

import 'package:path/path.dart' as p;

class FileUtils {
  /// Strips the extension and any characters that are unsafe in folder
  /// names on either Android or Windows.
  static String sanitizeFolderName(String originalFileName) {
    final base = p.basenameWithoutExtension(originalFileName);
    final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Video' : cleaned;
  }

  /// Returns a folder path guaranteed not to already exist, appending
  /// `_001`, `_002`, ... if the plain name is taken. This is what keeps
  /// re-splitting "My Holiday Video.mp4" twice from overwriting the
  /// first run's output.
  static Future<Directory> uniqueVideoFolder(String rootPath, String desiredName) async {
    var candidate = Directory(p.join(rootPath, desiredName));
    if (!await candidate.exists()) {
      return candidate.create(recursive: true);
    }
    var counter = 1;
    while (true) {
      final numbered = Directory(p.join(rootPath, '${desiredName}_${counter.toString().padLeft(3, '0')}'));
      if (!await numbered.exists()) {
        return numbered.create(recursive: true);
      }
      counter++;
    }
  }

  /// `Part_001.mp4`, `Part_002.mp4`, ... matching the source extension.
  static String partFileName(int partNumber, String sourceExtension) {
    final ext = sourceExtension.startsWith('.') ? sourceExtension : '.$sourceExtension';
    return 'Part_${partNumber.toString().padLeft(3, '0')}$ext';
  }

  static Future<int?> fileSizeOrNull(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }
}
