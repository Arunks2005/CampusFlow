import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../core/app_prefs.dart';
import '../../core/crowd_level.dart';
import '../../core/navigation.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/capacity_ring.dart';
import '../../widgets/mini_zone_card.dart';
import '../welcome/welcome_page.dart';

/// Page 2: three intro slides, shown on first launch only.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  final List<_SlideData> _slides = const [
    _SlideData(
      title: 'See the crowd before you go',
      body:
          'Live crowd levels for every cafeteria counter and lift lobby, '
          'so you can pick the quietest spot.',
      illustration: _CrowdIllustration(),
    ),
    _SlideData(
      title: 'Know your wait time',
      body:
          'Sensors count people anonymously and estimate how long you will '
          'wait, updated every few seconds. No cameras, no faces.',
      illustration: _WaitIllustration(),
    ),
    _SlideData(
      title: "Get notified when it's quiet",
      body:
          'Set an alert for your favourite spot and we will tell you the '
          'moment the wait drops.',
      illustration: _NotifyIllustration(),
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await AppPrefs.setOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(const WelcomePage()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // On slides 2 and 3 the Android back button goes to the previous slide.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _previous();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                child: Row(
                  children: [
                    Text(
                      '${_index + 1} / ${_slides.length}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: _isLast,
                        child: TextButton(
                          onPressed: _finish,
                          child: const Text('Skip'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _SlideView(data: _slides[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Dots(count: _slides.length, index: _index),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isLast ? _finish : _next,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _isLast ? 'Get started' : 'Next',
                          key: ValueKey<bool>(_isLast),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideData {
  const _SlideData({
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String title;
  final String body;
  final Widget illustration;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.data});

  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            // Scales the illustration down on small screens instead of overflowing.
            child: FittedBox(fit: BoxFit.scaleDown, child: data.illustration),
          ),
        ),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  data.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Slide ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

/// Soft circular glow behind each illustration.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            primary.withValues(alpha: 0.16),
            primary.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Slide 1: three zone cards at different crowd levels.
class _CrowdIllustration extends StatelessWidget {
  const _CrowdIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          const _Backdrop(),
          Positioned(
            top: 26,
            left: 0,
            width: 270,
            child: Transform.rotate(
              angle: -0.04,
              child: const MiniZoneCard(
                name: 'Main Cafeteria',
                detail: '34 of 40 · 6 min wait',
                level: CrowdLevel.crowded,
                leading: Icons.restaurant_rounded,
                fill: 0.85,
              ),
            ),
          ),
          Positioned(
            top: 108,
            right: 0,
            width: 270,
            child: Transform.rotate(
              angle: 0.04,
              child: const MiniZoneCard(
                name: 'Lift Lobby A',
                detail: '6 of 20 · under 1 min',
                level: CrowdLevel.quiet,
                leading: Icons.elevator_rounded,
                fill: 0.3,
              ),
            ),
          ),
          Positioned(
            top: 190,
            left: 12,
            width: 270,
            child: Transform.rotate(
              angle: -0.02,
              child: const MiniZoneCard(
                name: 'Counter 2',
                detail: '22 of 40 · 3 min wait',
                level: CrowdLevel.busy,
                leading: Icons.local_cafe_rounded,
                fill: 0.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 2: a ring showing the wait time and a row of people in the queue.
class _WaitIllustration extends StatelessWidget {
  const _WaitIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 320,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const _Backdrop(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 0.72),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return CapacityRing(
                    value: value,
                    color: AppColors.amber,
                    size: 180,
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '4',
                      style: TextStyle(
                        fontSize: 64,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'min wait',
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        Icons.person_rounded,
                        size: 30,
                        color: i < 4
                            ? const Color(0xFF8A5A00)
                            : scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '4 people ahead of you',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Slide 3: a bell and a sample notification card.
class _NotifyIllustration extends StatelessWidget {
  const _NotifyIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 320,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          const _Backdrop(),
          Positioned(
            top: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.sky, AppColors.blue],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 3),
                      ),
                      child: const Text(
                        '1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 34,
            child: Transform.scale(
              scale: 0.93,
              child: const Opacity(
                opacity: 0.55,
                child: _NotificationCard(
                  title: 'Counter 2 wait is now 2 min',
                  subtitle: '5 minutes ago',
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 62,
            child: _NotificationCard(
              title: 'Lift Lobby A is quiet now',
              subtitle: 'Wait under 1 min · just now',
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 288,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
