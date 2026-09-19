import 'package:flutter/material.dart';

class SplitButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;
  final String label;

  const SplitButton({super.key, required this.enabled, required this.onPressed, this.label = 'SPLIT VIDEO'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.content_cut),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }
}
