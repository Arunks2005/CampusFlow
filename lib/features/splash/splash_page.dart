import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../core/app_prefs.dart';
import '../../core/auth_navigator.dart';
import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../../widgets/app_logo.dart';
import '../auth/set_new_password_page.dart';
import '../onboarding/onboarding_page.dart';
import '../placeholder/placeholder_pages.dart';
import '../welcome/welcome_page.dart';

/// Page 1: animated splash that also decides where to go next.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _pulse;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _logoScale = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.4, curve: Curves.easeOut),
    );

    _textFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.45, 0.9, curve: Curves.easeOut),
    );

    _routeNext();
  }

  /// Shows the splash for at least 2.4 seconds, then chooses the right page.
  Future<void> _routeNext() async {
    final results = await Future.wait<bool>([
      Future<bool>.delayed(const Duration(milliseconds: 2400), () => true),
      AppPrefs.isOnboardingSeen(),
      AppPrefs.isGuest(),
    ]);

    if (!mounted) return;

    final onboardingSeen = results[1];
    final isGuest = results[2];
    final loggedIn = AuthService.currentSession != null;

    final Widget next;

    if (AuthNavigator.takePendingRecovery()) {
      next = const SetNewPasswordPage();
    } else if (loggedIn) {
      next = const HomePlaceholderPage();
    } else if (!onboardingSeen) {
      next = const OnboardingPage();
    } else if (isGuest) {
      next = const HomePlaceholderPage();
    } else {
      next = const WelcomePage();
    }

    Navigator.of(context).pushReplacement(fadeRoute(next));
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: AppGradients.hero),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (!reduceMotion)
                        for (final shift in const [0.0, 0.5])
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) {
                              final t = (_pulse.value + shift) % 1.0;

                              return Transform.scale(
                                scale: 0.55 + t * 0.9,
                                child: Container(
                                  width: 150,
                                  height: 150,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: (1 - t) * 0.35,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: const AppLogo(size: 104),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _textFade,
                  child: Column(
                    children: [
                      const Text(
                        'CampusFlow',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'See the crowd before you go',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 4),
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Getting things ready',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}