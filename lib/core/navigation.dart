import 'package:flutter/material.dart';

/// Smooth cross-fade, used when replacing a whole screen (Splash -> Onboarding).
Route<T> fadeRoute<T>(Widget page, {int milliseconds = 450}) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration(milliseconds: milliseconds),
    reverseTransitionDuration: Duration(milliseconds: milliseconds),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// Gentle slide + fade, used when opening a page on top of another.
Route<T> slideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final position = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: position, child: child),
      );
    },
  );
}
