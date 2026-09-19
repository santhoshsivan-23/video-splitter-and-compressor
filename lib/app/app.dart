import 'package:flutter/material.dart';

import '../screens/tools_home_screen.dart';

class VideoSplitterApp extends StatelessWidget {
  const VideoSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const ToolsHomeScreen(),
    );
  }
}
