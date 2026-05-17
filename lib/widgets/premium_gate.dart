import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../paywall_screen.dart';

/// Bloquea [child] si el usuario no tiene premium; ofrece abrir [PaywallScreen].
class PremiumGate extends StatelessWidget {
  const PremiumGate({
    super.key,
    required this.esPremium,
    required this.child,
    this.title = 'Contenido Premium',
    this.subtitle = 'Activá Premium para ver esta sección.',
    this.compact = false,
  });

  final bool esPremium;
  final Widget child;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (esPremium) return child;
    return _LockedPremiumPanel(
      title: title,
      subtitle: subtitle,
      compact: compact,
    );
  }
}

class _LockedPremiumPanel extends StatelessWidget {
  const _LockedPremiumPanel({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 20.0 : 32.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: compact ? 40 : 52, color: const Color(0xFFFFCA28)),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 14 : 17,
              ),
            ),
            SizedBox(height: compact ? 6 : 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: compact ? 11 : 13, height: 1.35),
            ),
            SizedBox(height: compact ? 14 : 22),
            if (!kIsWeb)
              FilledButton(
                onPressed: () async {
                  await PaywallScreen.open(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.black,
                ),
                child: const Text('ACTIVAR PREMIUM', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
