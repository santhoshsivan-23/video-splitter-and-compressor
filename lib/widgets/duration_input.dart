import 'package:flutter/material.dart';

/// Lets the user set the split length as Hours / Minutes / Seconds
/// instead of a hard-coded value (design doc section 8).
class DurationInput extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final ValueChanged<int> onHoursChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;

  const DurationInput({
    super.key,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onHoursChanged,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Stepper(label: 'Hours', value: hours, max: 23, onChanged: onHoursChanged),
        _Stepper(label: 'Minutes', value: minutes, max: 59, onChanged: onMinutesChanged),
        _Stepper(label: 'Seconds', value: seconds, max: 59, onChanged: onSecondsChanged),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.label, required this.value, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onChanged(value <= 0 ? max : value - 1),
            ),
            SizedBox(
              width: 36,
              child: Text(
                value.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(value >= max ? 0 : value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
