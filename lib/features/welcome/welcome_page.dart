import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../core/app_prefs.dart';
import '../../core/crowd_level.dart';
import '../../core/navigation.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/mini_zone_card.dart';
import '../auth/login_page.dart';
import '../auth/sign_up_page.dart';
import '../placeholder/placeholder_pages.dart';

/// Page 3: shown to anyone who is not signed in and not a guest.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _continueAsGuest(BuildContext context) async {
    await AppPrefs.setGuest(true);
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const HomePlaceholderPage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Hero(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 150),
                                child: Text(
                                  'Welcome to CampusFlow',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 250),
                                child: Text(
                                  'Check how busy your campus is, right now.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Spacer(),
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 350),
                                child: FilledButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      slideRoute(const LoginPage()),
                                    );
                                  },
                                  child: const Text('Log in'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 450),
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      slideRoute(const SignUpPage()),
                                    );
                                  },
                                  child: const Text('Create account'),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 550),
                                child: TextButton(
                                  onPressed: () => _continueAsGuest(context),
                                  child: const Text('Continue as guest'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.sync_rounded,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'An account syncs your favourites and '
                                          'alerts across devices.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color:
                                        theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dark gradient header with the logo and three floating sample cards.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(24, topInset + 20, 24, 32),
      decoration: const BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              AppLogo(size: 44),
              SizedBox(width: 12),
              Text(
                'CampusFlow',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 244,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 36,
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 100),
                    child: Transform.rotate(
                      angle: -0.03,
                      child: const MiniZoneCard(
                        name: 'Main Cafeteria',
                        detail: '34 of 40 · 6 min wait',
                        level: CrowdLevel.crowded,
                        leading: Icons.restaurant_rounded,
                        fill: 0.85,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 82,
                  left: 36,
                  right: 0,
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 250),
                    child: Transform.rotate(
                      angle: 0.03,
                      child: const MiniZoneCard(
                        name: 'Lift Lobby A',
                        detail: '6 of 20 · under 1 min',
                        level: CrowdLevel.quiet,
                        leading: Icons.elevator_rounded,
                        fill: 0.3,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 164,
                  left: 12,
                  right: 24,
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 400),
                    child: Transform.rotate(
                      angle: -0.015,
                      child: const MiniZoneCard(
                        name: 'Counter 2',
                        detail: '22 of 40 · 3 min wait',
                        level: CrowdLevel.busy,
                        leading: Icons.local_cafe_rounded,
                        fill: 0.55,
                      ),
                    ),
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