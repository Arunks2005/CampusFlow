import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The three crowd levels used everywhere in the app.
/// Colour is never used alone: each level also has an icon and a text label.
enum CrowdLevel { quiet, busy, crowded }

extension CrowdLevelX on CrowdLevel {
  Color get color => switch (this) {
    CrowdLevel.quiet => AppColors.green,
    CrowdLevel.busy => AppColors.amber,
    CrowdLevel.crowded => AppColors.red,
  };

  /// Darker shade for text so it stays readable on light backgrounds.
  Color get textColor => switch (this) {
    CrowdLevel.quiet => const Color(0xFF1B5E20),
    CrowdLevel.busy => const Color(0xFF8A5A00),
    CrowdLevel.crowded => const Color(0xFFB71C1C),
  };

  String get label => switch (this) {
    CrowdLevel.quiet => 'Quiet',
    CrowdLevel.busy => 'Busy',
    CrowdLevel.crowded => 'Crowded',
  };

  IconData get icon => switch (this) {
    CrowdLevel.quiet => Icons.check_circle_rounded,
    CrowdLevel.busy => Icons.warning_amber_rounded,
    CrowdLevel.crowded => Icons.error_rounded,
  };
}
