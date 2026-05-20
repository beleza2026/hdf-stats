import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../paywall_screen.dart';
import '../services/premium_service.dart';

bool _designerUnlockAll() => PremiumService.unlockAllForPreview;

/// Bloquea [child] si el usuario no tiene premium; ofrece abrir [PaywallScreen].
class PremiumGate extends StatelessWidget {
  const PremiumGate({
    super.key,
    required this.esPremium,
    required this.child,
    this.title = 'Contenido Premium',
    this.subtitle = 'Activá Premium para ver esta sección.',
    this.compact = false,
    this.onPremiumChanged,
  });

  final bool esPremium;
  final Widget child;
  final String title;
  final String subtitle;
  final bool compact;
  final Future<void> Function()? onPremiumChanged;

  @override
  Widget build(BuildContext context) {
    if (esPremium || _designerUnlockAll()) return child;
    return _LockedPremiumPanel(
      title: title,
      subtitle: subtitle,
      compact: compact,
      onPremiumChanged: onPremiumChanged,
    );
  }
}

class _LockedPremiumPanel extends StatelessWidget {
  const _LockedPremiumPanel({
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.onPremiumChanged,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final Future<void> Function()? onPremiumChanged;

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
            const Text('🔒', style: TextStyle(fontSize: 40)),
            SizedBox(height: compact ? 8 : 12),
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
                  final ok = await PaywallScreen.open(context);
                  if (ok == true) await onPremiumChanged?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E650),
                  foregroundColor: Colors.black,
                ),
                child: const Text('EMPEZAR PRUEBA GRATIS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
