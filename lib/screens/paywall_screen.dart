import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../device_trial_service.dart';
import '../services/premium_service.dart';

/// Paywall MatchGol Premium (RevenueCat).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  static Future<bool?> open(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PaywallScreen(),
      ),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00E650);
  static const _gold = Color(0xFFFFC107);

  static const _benefits = [
    'Tabla Moral HDF™',
    'Índice HDF™ por jugador',
    'Monitor de Bajas',
    'Cruces / Round of 16',
    'Estadística de Remontada',
    'Árbitros con tendencias',
    'VOTA - Predicciones',
    'Alertas de partidos',
    'Sin publicidad',
  ];

  Package? _mensual;
  Package? _anual;
  bool _loadingOfferings = true;
  bool _isLoading = false;
  String? _loadError;
  /// 0 = mensual, 1 = anual (recomendado).
  int _planSeleccionado = 1;

  @override
  void initState() {
    super.initState();
    debugPrint(
      'Paywall opened - RevenueCat initialized: ${PremiumService.isConfigured}',
    );
    _cargarOfertas();
    _logOfferingsDebug();
  }

  Future<void> _logOfferingsDebug() async {
    if (!PremiumService.isConfigured) {
      debugPrint('Offerings: RevenueCat no configurado (revisá REVENUECAT_API_KEY_IOS)');
      return;
    }
    try {
      final offerings = await Purchases.getOfferings();
      debugPrint('Offerings: ${offerings.current?.identifier ?? 'null'}');
      debugPrint(
        'Offerings current packages: ${offerings.current?.availablePackages.length ?? 0}',
      );
    } catch (e) {
      debugPrint('Offerings log error: $e');
    }
  }

  Future<void> _cargarOfertas() async {
    setState(() {
      _loadingOfferings = true;
      _loadError = null;
    });
    try {
      if (!PremiumService.isConfigured) {
        setState(() {
          _loadingOfferings = false;
          _loadError = 'Servicio temporalmente no disponible';
        });
        return;
      }
      final offering = await PremiumService.fetchOffering();
      debugPrint('Paywall prefetch offering: ${offering?.identifier}');
      if (offering == null) {
        setState(() {
          _loadingOfferings = false;
          _loadError = 'Servicio temporalmente no disponible';
        });
        return;
      }
      _aplicarOffering(offering);
      setState(() => _loadingOfferings = false);
    } catch (e) {
      debugPrint('Paywall offerings prefetch: $e');
      setState(() {
        _loadingOfferings = false;
        _loadError = 'Servicio temporalmente no disponible';
      });
    }
  }

  void _aplicarOffering(Offering offering) {
    _mensual = PremiumService.packageForProduct(
      offering,
      PremiumService.productMonthly,
    );
    _anual = PremiumService.packageForProduct(
      offering,
      PremiumService.productAnnual,
    );
    if (_mensual == null && _anual != null) _planSeleccionado = 1;
    if (_anual == null && _mensual != null) _planSeleccionado = 0;
  }

  Package? get _paqueteSeleccionado =>
      _planSeleccionado == 0 ? _mensual : _anual;

  Package? _packageDesdeOffering(Offering offering) {
    final cached = _paqueteSeleccionado;
    if (cached != null) return cached;
    final mensual = PremiumService.packageForProduct(
      offering,
      PremiumService.productMonthly,
    );
    final anual = PremiumService.packageForProduct(
      offering,
      PremiumService.productAnnual,
    );
    if (_planSeleccionado == 0) {
      return mensual ?? anual ?? _primerPaquete(offering);
    }
    return anual ?? mensual ?? _primerPaquete(offering);
  }

  Package? _primerPaquete(Offering offering) {
    if (offering.availablePackages.isNotEmpty) {
      return offering.availablePackages.first;
    }
    return offering.annual ?? offering.monthly;
  }

  String _precioMensualDisplay() {
    if (_mensual != null) return '${_mensual!.storeProduct.priceString} / mes';
    return 'USD 1.99 / mes';
  }

  String _precioAnualDisplay() {
    if (_anual != null) return '${_anual!.storeProduct.priceString} / año';
    return 'USD 19.99 / año';
  }

  String _precioAnualPorMes() {
    final p = _anual?.storeProduct.price;
    if (p != null && p > 0) {
      final perMonth = p / 12;
      final sym = _anual!.storeProduct.currencyCode == 'USD' ? 'USD ' : '';
      return '= $sym${perMonth.toStringAsFixed(2)} / mes';
    }
    return '= USD 1.67 / mes';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// CTA principal — nunca `onPressed: null`; refresca offerings al tocar.
  Future<void> _onTrialButtonPressed() async {
    if (_isLoading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final gate = await DeviceTrialService.verifyTrialAllowedForUser(user);
      if (!gate.allowed) {
        _snack(
          gate.blockMessage ?? 'Prueba no disponible en este dispositivo.',
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (!PremiumService.isConfigured) {
        _snack('Servicio temporalmente no disponible');
        return;
      }

      final offerings = await Purchases.getOfferings();
      debugPrint('Offerings: ${offerings.current?.identifier}');

      final offering =
          offerings.getOffering(PremiumService.offeringId) ?? offerings.current;

      if (offering == null) {
        _snack('Servicio no disponible, intentá de nuevo');
        return;
      }

      _aplicarOffering(offering);
      final package = _packageDesdeOffering(offering);
      if (package == null) {
        _snack('Servicio temporalmente no disponible');
        return;
      }

      debugPrint('Paywall purchase package: ${package.identifier}');
      final result = await Purchases.purchase(PurchaseParams.package(package));

      if (user != null) {
        await DeviceTrialService.registerTrialIfApplicable(
          user: user,
          customerInfo: result.customerInfo,
        );
      }
      final activo = result.customerInfo.entitlements.active
          .containsKey(PremiumService.entitlementId);
      if (activo && mounted) Navigator.pop(context, true);
    } on PlatformException catch (e) {
      debugPrint('Paywall purchase PlatformException: $e');
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return;
      }
      if (code == PurchasesErrorCode.productAlreadyPurchasedError ||
          code == PurchasesErrorCode.receiptAlreadyInUseError) {
        await _restaurar(silentCancel: true);
        return;
      }
      _snack(_mensajeError(e));
    } catch (e) {
      debugPrint('Paywall purchase error: $e');
      _snack(_mensajeError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mensajeError(Object e) {
    if (e is PlatformException && e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    final s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('internet') || s.contains('offline')) {
      return 'Sin conexión. Intentá de nuevo';
    }
    if (s.contains('not allowed') || s.contains('payments')) {
      return 'Compras no habilitadas en este dispositivo';
    }
    return 'No se pudo completar. Intentá de nuevo';
  }

  Future<void> _restaurar({bool silentCancel = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      if (!PremiumService.isConfigured) {
        _snack('Servicio temporalmente no disponible');
        return;
      }
      final ok = await PremiumService.restaurarCompras();
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        _snack('No se encontró suscripción activa');
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError && silentCancel) {
        return;
      }
      _snack(_mensajeError(e));
    } catch (e) {
      _snack(_mensajeError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () {
                      if (_isLoading) return;
                      Navigator.pop(context, false);
                    },
                  ),
                ),
                Expanded(
                  child: _loadingOfferings
                      ? const Center(
                          child: CircularProgressIndicator(color: _gold),
                        )
                      : _content(),
                ),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: _gold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          if (_loadError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Image.asset('assets/images/matchi.png', height: 120, fit: BoxFit.contain),
          const SizedBox(height: 12),
          const Text(
            'MATCHGOL PREMIUM ⭐',
            style: TextStyle(
              color: _green,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Accedé a todas las estadísticas',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ..._benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✅ ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _planCard(
            index: 0,
            titulo: 'MENSUAL',
            precio: _precioMensualDisplay(),
            subtitulo: 'Probá 7 días gratis',
            destacado: false,
          ),
          const SizedBox(height: 10),
          _planCard(
            index: 1,
            titulo: '⭐ ANUAL  — AHORRÁ 16%',
            precio: _precioAnualDisplay(),
            subtitulo: '${_precioAnualPorMes()}\nProbá 7 días gratis',
            destacado: true,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _onTrialButtonPressed,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _gold,
                      ),
                    )
                  : const Text(
                      '7 días gratis',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _restaurar,
            child: const Text(
              'Restaurar compra',
              style: TextStyle(color: Colors.white38, decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se cobra automáticamente. Cancelá cuando quieras.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _planCard({
    required int index,
    required String titulo,
    required String precio,
    required String subtitulo,
    required bool destacado,
  }) {
    final selected = _planSeleccionado == index;
    final borderColor = selected && destacado
        ? _green
        : selected
            ? _green.withValues(alpha: 0.6)
            : Colors.white24;

    return GestureDetector(
      onTap: () {
        if (_isLoading) return;
        setState(() => _planSeleccionado = index);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                color: destacado ? _green : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              precio,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
