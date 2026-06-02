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

  /// Debe coincidir con el entitlement en RevenueCat (p. ej. `Premium`).
  static const String entitlementId = 'Premium';
  static const String productMonthly = 'matchgol_monthly';
  static const String productAnnual = 'matchgol_annual';
  static const String offeringId = 'default_matchgol';

  static const String _rcApiKeyAndroid = 'goog_QRuxqIqpLsLTHWZKcoPKvcYfijG';
  /// Definir en build iOS: `--dart-define=REVENUECAT_API_KEY_IOS=appl_...`
  static const String _rcApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: 'appl_XXXXXXXXX',
  );

  /// Valores crudos de `--dart-define-from-file` (deben ser [const] con nombre literal).
  static const String designerUnlockAllRaw = String.fromEnvironment(
    'DESIGNER_UNLOCK_ALL',
    defaultValue: '',
  );
  static const String forceFreeUiRaw = String.fromEnvironment(
    'FORCE_FREE_UI',
    defaultValue: '',
  );

  /// `"true"` / `"1"` / `"yes"` desde [dart_defines.json] (no usar [bool.fromEnvironment]).
  static bool _parseEnvBool(String raw) {
    final f = raw.trim().toLowerCase();
    return f == 'true' || f == '1' || f == 'yes';
  }

  static bool get unlockAllForPreview => _parseEnvBool(designerUnlockAllRaw);

  /// Solo desarrollo: ignora suscripción RC y muestra candados (probar modo FREE).
  static bool get forceFreeUi => _parseEnvBool(forceFreeUiRaw);

  /// App liberada: nunca abrir paywall.
  static bool get shouldBypassPaywall => true;

  /// App liberada: todo el contenido se comporta como premium.
  static bool effectivePremium(bool fromCache) {
    return true;
  }

  /// Solo entitlements en `active` (nunca inferir desde `all`).
  static EntitlementInfo? _entitlementInfo(CustomerInfo info) {
    for (final e in info.entitlements.active.entries) {
      if (e.key.toLowerCase() == entitlementId.toLowerCase()) return e.value;
    }
    return null;
  }

  /// `true` tras `Purchases.configure()` exitoso en `init()`.
  static bool isConfigured = false;
  static bool _customerInfoListenerAttached = false;

  static bool _apiKeyValid(String key) =>
      key.isNotEmpty && !key.contains('XXXXXXXXX');

  /// Llamar desde `main()` antes de `runApp()`.
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

    if (!_apiKeyValid(apiKey)) {
      debugPrint(
        'RevenueCat: API key no configurada (iOS: REVENUECAT_API_KEY_IOS en build).',
      );
      if (Platform.isIOS) return;
    }

    await Purchases.configure(PurchasesConfiguration(apiKey));
    isConfigured = true;
    debugPrint('RevenueCat: Purchases.configure() OK (${Platform.isIOS ? 'iOS' : 'Android'})');

    // TODO: quitar — debug temporal trial / premium
    if (!_customerInfoListenerAttached) {
      _customerInfoListenerAttached = true;
      Purchases.addCustomerInfoUpdateListener((info) {
        print('RevenueCat OK: ${info.entitlements.active}');
      });
    }
  }

  /// Reintenta `configure` si el paywall se abre sin SDK listo (p. ej. build sin define).
  static Future<bool> ensureConfigured() async {
    if (isConfigured) return true;
    await init();
    return isConfigured;
  }

  /// Trial activo o suscripción pagada cuentan como premium (solo mapa `active`).
  static bool hasPremiumEntitlement(CustomerInfo info) {
    if (info.entitlements.active.isEmpty) return false;
    final ent = _entitlementInfo(info);
    return ent != null && ent.isActive;
  }

  /// Refresca caché de RevenueCat tras compra/restaurar.
  static Future<CustomerInfo> fetchCustomerInfoFresh() async {
    try {
      await Purchases.invalidateCustomerInfoCache();
    } catch (e) {
      debugPrint('RevenueCat invalidate cache: $e');
    }
    return Purchases.getCustomerInfo();
  }

  static Future<bool> isPremium() async {
    return true;
  }

  static Future<PremiumSubscriptionStatus> getSubscriptionStatus() async {
    return const PremiumSubscriptionStatus(
      isPremium: true,
      isInTrial: false,
      expirationDate: null,
      productIdentifier: 'free_access',
      willRenew: false,
    );
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
      if (hasPremiumEntitlement(info)) return true;
      final fresh = await fetchCustomerInfoFresh();
      return hasPremiumEntitlement(fresh);
    } catch (e) {
      debugPrint('RevenueCat restaurar error: $e');
      rethrow;
    }
  }
}
