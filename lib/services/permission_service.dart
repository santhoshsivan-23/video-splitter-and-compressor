import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests only the Android permissions actually needed to read the
/// source video and write split output, matching the "minimum necessary
/// permissions" requirement from the design doc. Windows needs none of
/// this - it's a no-op there.
class PermissionService {
  Future<bool> ensureStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      // Android 13+: scoped storage + granular media permissions.
      // Reading a user-picked file via file_picker/SAF doesn't require
      // READ_MEDIA_VIDEO, but we request it so the app can also show
      // recently split files if needed later.
      final status = await Permission.videos.status;
      if (status.isGranted) return true;
      final result = await Permission.videos.request();
      return result.isGranted;
    } else {
      // Android 12 and below.
      final status = await Permission.storage.status;
      if (status.isGranted) return true;
      final result = await Permission.storage.request();
      return result.isGranted;
    }
  }
}
