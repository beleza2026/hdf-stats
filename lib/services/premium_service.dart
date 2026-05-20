import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Estado de suscripción RevenueCat (entitlement `premium`).
class PremiumSubscriptionStatus {
  const PremiumSubscriptionStatus({
    required this.isPremium,
    this.isInTrial = false,
    this.expirationDate,
    this.productIdentifier,
    this.willRenew = true,
  });

  final bool isPremium;
  final bool isInTrial;
  final DateTime? expirationDate;
  final String? productIdentifier;
  final bool willRenew;

  String get planLabel {
    final id = productIdentifier ?? '';
    if (id.contains('annual') || id.contains('year')) return 'Anual';
    if (id.contains('month')) return 'Mensual';
    return 'Premium';
  }

  String formatExpirationEs() {
    final d = expirationDate;
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }
}

class PremiumService {
  PremiumService._();

  static const String entitlementId = 'premium';
  static const String productMonthly = 'matchgol_monthly';
  static const String productAnnual = 'matchgol_annual';
  static const String offeringId = 'default_matchgol';

  static const String _rcApiKeyAndroid = 'goog_QRuxqIqpLsLTHWZKcoPKvcYfijG';
  /// Definir en build iOS: `--dart-define=REVENUECAT_API_KEY_IOS=appl_...`
  static const String _rcApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: 'appl_XXXXXXXXX',
  );

  static bool get unlockAllForPreview {
    const flag = String.fromEnvironment('DESIGNER_UNLOCK_ALL', defaultValue: '');
    final f = flag.trim().toLowerCase();
    return f == 'true' || f == '1' || f == 'yes';
  }

  /// `true` tras `Purchases.configure()` exitoso en `init()`.
  static bool isConfigured = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    isConfigured = false;
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

    String apiKey;
    if (Platform.isIOS) {
      apiKey = _rcApiKeyIos;
    } else if (Platform.isAndroid) {
      apiKey = _rcApiKeyAndroid;
    } else {
      return;
    }

    if (apiKey.isEmpty || apiKey.contains('XXXXXXXXX')) {
      debugPrint('RevenueCat: API key iOS no configurada (REVENUECAT_API_KEY_IOS).');
      if (Platform.isIOS) return;
    }

    await Purchases.configure(PurchasesConfiguration(apiKey));
    isConfigured = true;
    debugPrint('RevenueCat: Purchases.configure() OK (${Platform.isIOS ? 'iOS' : 'Android'})');
  }

  static Future<bool> isPremium() async {
    if (unlockAllForPreview) return true;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('RevenueCat isPremium error: $e');
      return false;
    }
  }

  static Future<PremiumSubscriptionStatus> getSubscriptionStatus() async {
    if (unlockAllForPreview) {
      return const PremiumSubscriptionStatus(
        isPremium: true,
        isInTrial: false,
        expirationDate: null,
        productIdentifier: 'designer_unlock',
        willRenew: true,
      );
    }
    try {
      final info = await Purchases.getCustomerInfo();
      final ent = info.entitlements.active[entitlementId];
      if (ent == null) {
        return const PremiumSubscriptionStatus(isPremium: false);
      }
      final inTrial = ent.periodType == PeriodType.trial ||
          ent.periodType == PeriodType.intro;
      return PremiumSubscriptionStatus(
        isPremium: true,
        isInTrial: inTrial,
        expirationDate: _parseExpiration(ent.expirationDate),
        productIdentifier: ent.productIdentifier,
        willRenew: ent.willRenew,
      );
    } catch (e) {
      debugPrint('RevenueCat status error: $e');
      return const PremiumSubscriptionStatus(isPremium: false);
    }
  }

  static Future<Offering?> fetchOffering() async {
    final offerings = await Purchases.getOfferings();
    return offerings.getOffering(offeringId) ?? offerings.current;
  }

  static Package? packageForProduct(Offering offering, String productId) {
    for (final p in offering.availablePackages) {
      if (p.storeProduct.identifier == productId || p.identifier == productId) {
        return p;
      }
    }
    if (productId == productMonthly) return offering.monthly;
    if (productId == productAnnual) return offering.annual;
    return null;
  }

  static DateTime? _parseExpiration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<bool> restaurarCompras() async {
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('RevenueCat restaurar error: $e');
      rethrow;
    }
  }
}
