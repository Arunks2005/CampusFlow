import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/validators.dart';

/// Four-segment bar that shows how strong the typed password is.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = Validators.passwordScore(password);

    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      Colors.transparent,
      AppColors.red,
      AppColors.amber,
      Color(0xFF7CB342),
      AppColors.green,
    ];
    final color = colors[score];

    return Semantics(
      label: score == 0
          ? 'Password strength'
          : 'Password strength ${labels[score]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final filled = i < score;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: filled ? color : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            score == 0
                ? 'Use 8+ characters with upper and lower case letters and a number.'
                : 'Strength: ${labels[score]}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
