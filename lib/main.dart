import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player_win/video_player_win_plugin.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    WindowsVideoPlayer.registerWith();
  }
  runApp(const VideoSplitterApp());
}
