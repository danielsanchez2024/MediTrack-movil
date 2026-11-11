import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum DayOption { yesterday, today, tomorrow }

DateTime dateForDay(DayOption day) {
  final now = DateTime.now();
  switch (day) {
    case DayOption.yesterday:
      return now.subtract(const Duration(days: 1));
    case DayOption.tomorrow:
      return now.add(const Duration(days: 1));
    case DayOption.today:
      return now;
  }
}

class DaySelector extends StatelessWidget {
  const DaySelector({super.key, required this.value, required this.onChanged});

  final DayOption value;
  final ValueChanged<DayOption> onChanged;

  static const _options = [
    (DayOption.yesterday, 'Ayer'),
    (DayOption.today, 'Hoy'),
    (DayOption.tomorrow, 'Mañana'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (option, label) in _options)
            GestureDetector(
              onTap: () => onChanged(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: value == option ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: value == option ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
