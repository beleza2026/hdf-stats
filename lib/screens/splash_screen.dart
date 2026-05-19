import 'package:flutter/material.dart';

/// Splash al abrir la app (~2.5 s) antes de onboarding o home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final Future<void> Function(BuildContext context) onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00E650);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 2500), _finish);
  }

  Future<void> _finish() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    await widget.onFinished(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Image.asset(
                'assets/images/matchi.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.sports_soccer, color: _green, size: 120),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'MATCHGOL STATS',
              style: TextStyle(
                color: _green,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
