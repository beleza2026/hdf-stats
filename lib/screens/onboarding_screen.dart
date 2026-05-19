import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clave en [SharedPreferences]: el intro de 3 slides ya se mostró.
const String kOnboardingIntroSeenKey = 'onboarding_intro_seen';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  /// Llamado tras "EMPEZAR" (prefs ya guardadas). Debe llevar al home / siguiente paso.
  final void Function(BuildContext context) onComplete;

  static Future<bool> wasIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kOnboardingIntroSeenKey) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingIntroSeenKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00E650);

  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _empezar() async {
    await OnboardingScreen.markIntroSeen();
    if (!mounted) return;
    widget.onComplete(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _OnboardingSlide(
                    child: _MatchiSlideContent(),
                  ),
                  _OnboardingSlide(
                    child: _IconSlideContent(
                      icon: Icons.bar_chart,
                      title: 'Estadísticas Reales',
                      subtitle:
                          'Liga Profesional, Copa Libertadores, Sudamericana y Mundial 2026',
                    ),
                  ),
                  _OnboardingSlide(
                    child: _IconSlideContent(
                      icon: Icons.emoji_events,
                      title: 'Índice HDF™ + VOTA',
                      subtitle: 'Predecí resultados y competí con otros hinchas',
                    ),
                  ),
                ],
              ),
            ),
            _PageDots(current: _page, count: 3, color: _green),
            const SizedBox(height: 24),
            if (_page == 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _empezar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'EMPEZAR',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 88),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: child,
    );
  }
}

class _MatchiSlideContent extends StatelessWidget {
  const _MatchiSlideContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/matchi.png',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.sports_soccer, color: Color(0xFF00E650), size: 120),
        ),
        const SizedBox(height: 32),
        const Text(
          '¡Hola! Soy Matchi 👋',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tu compañero de estadísticas de fútbol',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 16, height: 1.4),
        ),
      ],
    );
  }
}

class _IconSlideContent extends StatelessWidget {
  const _IconSlideContent({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 100, color: const Color(0xFF00E650)),
        const SizedBox(height: 40),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 16, height: 1.4),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.current, required this.count, required this.color});

  final int current;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
