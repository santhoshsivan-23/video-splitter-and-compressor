import 'dart:io';

import 'package:flutter/material.dart';

/// The "Select Video" card on the Home screen (design doc section 6).
class VideoPickerCard extends StatelessWidget {
  final File? selectedFile;
  final VoidCallback onPick;

  const VideoPickerCard({super.key, required this.selectedFile, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              selectedFile == null ? Icons.video_library_outlined : Icons.movie,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              selectedFile == null ? 'No video selected' : selectedFile!.path.split(Platform.pathSeparator).last,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: Text(selectedFile == null ? 'Choose Video' : 'Choose Different Video'),
            ),
          ],
        ),
      ),
    );
  }
}
