# Video Splitter - Troubleshooting & Key Points

## 1. Android Build Issue (`flutter build apk --release`)

### Why the issue occurred
1. **Invalid Windows File URI in `ffmpeg_kit_flutter_android`**:
   The project previously depended on `ffmpeg_kit_flutter_new: ^1.6.0`, which pulled in the obsolete `ffmpeg_kit_flutter_android: 1.7.0`. In its Gradle script, it generated a local Maven repository using `maven { url "file://$localMavenPath" }`. On Windows, this produced a malformed file URI with backslashes (`file://D:\...`), causing Gradle's `:app:mergeReleaseNativeLibs` task to fail with:
   ```text
   Cannot convert URI 'file://D:\...\build\ffmpeg_kit_flutter_android\localMaven' to a file.
   ```
2. **`compileSdk 36` Conflict**:
   The older `file_picker: ^8.1.2` had hardcoded `compileSdk 34` and depended on `flutter_plugin_android_lifecycle`, which required `compileSdk 36`.

### What was done to fix it
1. **Upgraded `ffmpeg_kit_flutter_new` to `^4.6.2`**:
   Starting in v3+, `ffmpeg_kit_flutter_new` completely removed the obsolete `ffmpeg_kit_flutter_android` dependency and its broken Gradle script.
2. **Upgraded `file_picker` to `^13.1.0` and `device_info_plus` to `^13.2.0`**:
   Eliminated the legacy dependency on `flutter_plugin_android_lifecycle` and resolved version constraints.
3. **Updated API calls in `lib/services/video_service.dart`**:
   Migrated `FilePicker.platform.pickFiles(...)` to the new `FilePicker.pickFile(type: FileType.video)` API.

---

## 2. Windows App Execution Issue (`ffprobe.exe not found`)

### Why the issue occurred
* On **Android**, FFmpeg is bundled natively inside the app via the Android plugin.
* On **Windows**, Flutter plugins do not bundle FFmpeg desktop binaries. The app's logic in [`lib/services/ffmpeg_service.dart`](lib/services/ffmpeg_service.dart) runs real Windows command-line binaries:
  1. It first checks for `ffmpeg.exe` and `ffprobe.exe` in an `ffmpeg\bin\` folder located right next to `video_splitter.exe`.
  2. If not found there, it falls back to checking the system `PATH`.
* Because neither `ffprobe.exe` nor `ffmpeg.exe` existed on the system or in the app's output folder, the app failed with:
  ```text
  Could not read video info:
  ProcessException: The system cannot find the file specified
  Command: ffprobe.exe -v quiet -print_format json -show_format -show_streams "..."
  ```

### What was done to fix it
1. **Downloaded official Windows FFmpeg binaries**:
   Downloaded static Windows builds of `ffmpeg.exe` and `ffprobe.exe` (v9.0.1).
2. **Placed binaries where `video_splitter.exe` expects them**:
   * Copied to release folder: [`build\windows\x64\runner\Release\ffmpeg\bin\`](build/windows/x64/runner/Release/ffmpeg/bin/)
   * Copied to project source: [`windows\ffmpeg\bin\`](windows/ffmpeg/bin/)
3. **Automated future Windows builds in [`windows/CMakeLists.txt`](windows/CMakeLists.txt)**:
   Added an install step (lines 110–116) so that every `flutter build windows` automatically bundles `ffmpeg\bin\` next to `video_splitter.exe`:
   ```cmake
   # Install bundled ffmpeg binaries next to the executable if present
   set(FFMPEG_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/bin")
   if(EXISTS "${FFMPEG_BIN_DIR}")
     install(DIRECTORY "${FFMPEG_BIN_DIR}"
       DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/ffmpeg"
       COMPONENT Runtime)
   endif()
   ```

---

## 3. Verification & Build Commands

### Android APK
* **Command**: `flutter build apk --release`
* **Output**: [`build/app/outputs/flutter-apk/app-release.apk`](build/app/outputs/flutter-apk/app-release.apk)

### Windows Desktop App
* **Command**: `flutter build windows --release`
* **Output**: [`build/windows/x64/runner/Release/video_splitter.exe`](build/windows/x64/runner/Release/video_splitter.exe)
* Both `ffmpeg.exe` and `ffprobe.exe` reside in `build/windows/x64/runner/Release/ffmpeg/bin/` and execute properly.

---

## 4. What to Do on a New Device (After Cloning / Pulling)

### For Android:
No extra steps required! All dependencies and API fixes are committed to git:
```bash
flutter pub get
flutter build apk --release
```

### For Windows:
Because `ffmpeg.exe` and `ffprobe.exe` are large (>100MB each), they are ignored by git to prevent GitHub push errors. On any new Windows machine, run one of the following:

* **Option 1 (One-click script - Recommended)**:
  Run the included setup script from PowerShell:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\windows\setup_ffmpeg.ps1
  ```
  This will automatically download and place `ffmpeg.exe` and `ffprobe.exe` into `windows/ffmpeg/bin/` and the build folders.

* **Option 2 (System-wide with winget)**:
  ```powershell
  winget install Gyan.FFmpeg.Essentials
  ```
  This adds FFmpeg to the system `PATH`. The app will detect it automatically.
