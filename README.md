# Video Splitter

A local/offline Flutter app that splits a long video into fixed-length
clips, for Android and Windows. No backend, no server, no internet
access required — matches the architecture discussed in the design doc.

```
Flutter UI  ->  SQLite (metadata/history)  +  FFmpeg (splitting)  ->  local files
```

## What's implemented

- **Home screen** — pick a video (`lib/screens/home_screen.dart`)
- **Video details screen** — shows duration/resolution/size (via
  ffprobe), lets you set the split length in H/M/S
  (`lib/screens/video_details_screen.dart`)
- **Splitting screen** — live progress (part N/total, %, elapsed,
  estimated remaining), cancel button
  (`lib/screens/splitting_screen.dart`)
- **Result screen** — completion summary + "Open Folder"
  (`lib/screens/result_screen.dart`)
- **History screen** — past jobs from SQLite, open folder, delete
  history and/or the generated files (`lib/screens/history_screen.dart`)
- **SQLite** — `videos` + `split_parts` tables exactly as specced
  (`lib/database/`)
- **FFmpeg splitting** — stream-copy (`-c copy`) by default, so there's
  no re-encoding quality loss; a `reencode: true` path exists in
  `FFmpegService.extractSegment` for when a cut must land on an exact
  frame rather than the nearest keyframe (`lib/services/ffmpeg_service.dart`)
- **Storage** — resolves `Download/Video Splitter/<name>/` on Android
  and `Downloads/Video Splitter/<name>/` on Windows, auto-numbering
  (`_001`, `_002`, ...) if a folder with that name already exists, so
  re-splitting the same file never overwrites a previous run
  (`lib/services/storage_service.dart`, `lib/utils/file_utils.dart`)
- **Permissions** — requests only `READ_MEDIA_VIDEO` (Android 13+) or
  the legacy storage permission (Android 12-), never broad grabs
  (`lib/services/permission_service.dart`)

## Project layout

This matches section 14 of the design doc:

```
lib/
├── main.dart
├── app/app.dart
├── screens/          home, video_details, splitting, result, history
├── widgets/          video_picker, duration_input, split_button, progress_widget
├── database/         database_helper, video_dao, split_part_dao
├── models/           video_model, split_part_model
├── services/         ffmpeg_service, video_service, storage_service, permission_service
└── utils/            duration_utils, file_utils
```

## Setting up the platform folders

Only `lib/`, `pubspec.yaml`, and a couple of platform notes are
included here — the actual `android/` and `windows/` Gradle/CMake
scaffolding is thousands of lines of boilerplate that `flutter create`
generates for you and that only makes sense once regenerated against
the Flutter SDK version you actually have installed. To finish setup:

```bash
# From inside this video_splitter/ folder:
flutter create --platforms=android,windows .
flutter pub get
```

This will *not* touch your `lib/` folder or `pubspec.yaml` dependencies
— it only fills in the missing `android/` and `windows/` runner
projects.

Then:

1. **Android permissions** — open the newly generated
   `android/app/src/main/AndroidManifest.xml` and merge in the
   permissions from
   `android/app/src/main/AndroidManifest_ADDITIONS.xml` (already
   included in this zip).
2. **Android minSdkVersion** — set `minSdkVersion 21` (or higher) and
   `compileSdkVersion`/`targetSdkVersion` to the latest, in
   `android/app/build.gradle`, per `ffmpeg_kit_flutter_new`'s
   requirements.
3. **Windows FFmpeg binaries** — `ffmpeg_kit_flutter_new` only supports
   Android/iOS; there is no Flutter plugin that bundles FFmpeg for
   Windows. Download static Windows builds of `ffmpeg.exe` and
   `ffprobe.exe` (e.g. from https://www.gyan.dev/ffmpeg/builds/) and
   drop them in `windows/ffmpeg/bin/` (a placeholder file with the exact
   instructions is already there). `FFmpegService` looks there first,
   then falls back to `PATH`.

## Running

```bash
flutter run -d windows     # Windows desktop
flutter run                # a connected Android device/emulator
```

## Building

```bash
flutter build apk --release        # Android
flutter build windows --release    # Windows
```

For the Windows release build, also copy `ffmpeg.exe`/`ffprobe.exe`
into `build/windows/x64/runner/Release/ffmpeg/bin/` so they ship next
to `video_splitter.exe` (see the note file in `windows/ffmpeg/bin/` for
wiring this into `CMakeLists.txt` as an automatic post-build step).

## Known limitations / next steps

- **Frame-accurate cuts**: default splitting uses `-c copy`, which
  snaps to the nearest keyframe (typically within a couple of seconds).
  Pass `reencode: true` in `FFmpegService.extractSegment` if you need
  exact-second boundaries; this re-encodes and is much slower.
- **Video preview playback**: not wired up yet. `video_player` is
  included in `pubspec.yaml` for a future "preview before splitting"
  feature, but note it has no official Windows backend — that would
  need `media_kit` or similar if you want in-app preview on desktop.
- **Progress granularity**: progress currently updates once per
  completed part (part 3 of 30 done), not smoothly within a single
  FFmpeg call. For finer-grained progress, parse FFmpeg's `-progress
  pipe:1` output per part.
- Automated tests aren't included; `flutter test` scaffolding
  (`flutter_test`) is in `pubspec.yaml` ready for you to add widget/unit
  tests against `DurationUtils`, `FileUtils`, and the DAOs.
