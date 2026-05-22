import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../device_trial_service.dart';
import '../services/premium_service.dart';

/// Paywall MatchGol Premium (RevenueCat).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  /// Abre el paywall salvo [PremiumService.shouldBypassPaywall] (DESIGNER_UNLOCK_ALL).
  static Future<bool?> open(BuildContext context) {
    if (PremiumService.shouldBypassPaywall) {
      debugPrint(
        'PaywallScreen.open: omitido — DESIGNER_UNLOCK_ALL (sin RevenueCat ni offerings)',
      );
      return Future<bool?>.value(true);
    }
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

  final TextEditingController _codigoCortesiaController = TextEditingController();
  String? _codigoCortesiaMensaje;
  bool _codigoCortesiaCargando = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _codigoCortesiaController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    debugPrint(
      'Paywall opened - RevenueCat initialized: ${PremiumService.isConfigured}',
    );
    if (!PremiumService.isConfigured) {
      final ok = await PremiumService.ensureConfigured();
      debugPrint('Paywall ensureConfigured: $ok');
      if (mounted) setState(() {});
    }
    unawaited(_logOfferingsDebug());
    unawaited(_cargarOfertas());
  }

  Future<void> _logOfferingsDebug() async {
    if (!PremiumService.isConfigured) {
      debugPrint('Offerings: RevenueCat no configurado (REVENUECAT_API_KEY_IOS)');
      return;
    }
    try {
      final offerings = await Purchases.getOfferings().timeout(
        const Duration(seconds: 15),
      );
      debugPrint('Offerings: ${offerings.current?.identifier ?? 'null'}');
    } catch (e) {
      debugPrint('Offerings log error: $e');
    }
  }

  Future<void> _cargarOfertas() async {
    if (!mounted) return;
    setState(() {
      _loadingOfferings = true;
      _loadError = null;
    });
    try {
      if (!PremiumService.isConfigured) {
        if (mounted) {
          setState(() {
            _loadingOfferings = false;
            _loadError = 'Servicio temporalmente no disponible';
          });
        }
        return;
      }
      final offering = await PremiumService.fetchOffering().timeout(
        const Duration(seconds: 20),
      );
      debugPrint('Paywall prefetch offering: ${offering?.identifier}');
      if (!mounted) return;
      if (offering == null) {
        setState(() {
          _loadingOfferings = false;
          _loadError = 'Servicio temporalmente no disponible';
        });
        return;
      }
      _aplicarOffering(offering);
      setState(() => _loadingOfferings = false);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _loadingOfferings = false;
          _loadError = 'Servicio temporalmente no disponible';
        });
      }
    } catch (e) {
      debugPrint('Paywall offerings prefetch: $e');
      if (mounted) {
        setState(() {
          _loadingOfferings = false;
          _loadError = 'Servicio temporalmente no disponible';
        });
      }
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

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('No se pudo abrir el enlace');
    }
  }

  Widget _legalLinksRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => _abrirUrl(
            'https://willowy-moonbeam-415d5b.netlify.app',
          ),
          child: const Text(
            'Política de Privacidad',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        const Text('·', style: TextStyle(color: Colors.white54)),
        TextButton(
          onPressed: () => _abrirUrl(
            'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
          ),
          child: const Text(
            'Términos de Uso',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
      ],
    );
  }

  Future<void> _aplicarCodigoCortesia() async {
    final codigo = _codigoCortesiaController.text.trim().toUpperCase();
    if (codigo.isEmpty) return;
    setState(() {
      _codigoCortesiaCargando = true;
      _codigoCortesiaMensaje = null;
    });
    try {
      final docRef = await FirebaseFirestore.instance
          .collection('codigos_cortesia')
          .doc(codigo)
          .get();
      if (!docRef.exists) {
        setState(() {
          _codigoCortesiaMensaje = '❌ Código inválido o inactivo.';
          _codigoCortesiaCargando = false;
        });
        return;
      }
      final data = docRef.data()!;
      if (data['activo'] != true) {
        setState(() {
          _codigoCortesiaMensaje = '❌ Código inválido o inactivo.';
          _codigoCortesiaCargando = false;
        });
        return;
      }
      final usosActuales = (data['usos_actuales'] as num?)?.toInt() ?? 0;
      final usosMaximos = (data['usos_maximos'] as num?)?.toInt() ?? 0;
      if (usosActuales >= usosMaximos) {
        setState(() {
          _codigoCortesiaMensaje = '❌ Código agotado.';
          _codigoCortesiaCargando = false;
        });
        return;
      }
      await FirebaseFirestore.instance
          .collection('codigos_cortesia')
          .doc(codigo)
          .update({'usos_actuales': FieldValue.increment(1)});
      final meses = (data['meses_gratis'] as num?)?.toInt() ?? 1;
      setState(() {
        _codigoCortesiaMensaje =
            '✅ ¡Código válido! Tenés $meses mes${meses > 1 ? 'es' : ''} gratis de HDF Stats Premium.';
        _codigoCortesiaCargando = false;
      });
    } catch (e) {
      setState(() {
        _codigoCortesiaMensaje = '❌ Error al validar el código. Intentá de nuevo.';
        _codigoCortesiaCargando = false;
      });
    }
  }

  /// Código de cortesía / promo — solo Android (Play promo codes).
  Widget _codigoCortesiaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CÓDIGO DE CORTESÍA',
          style: TextStyle(
            color: Color(0xFF00E650),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ingresá tu código para acceder a HDF Stats Premium gratis.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codigoCortesiaController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Ej: SORTEO-ABRIL',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF0D1B2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF00E650)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _codigoCortesiaCargando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E650),
                    ),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E650),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isLoading ? null : _aplicarCodigoCortesia,
                    child: const Text(
                      'APLICAR',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
          ],
        ),
        if (_codigoCortesiaMensaje != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _codigoCortesiaMensaje!.startsWith('✅')
                  ? const Color(0xFF00E650).withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _codigoCortesiaMensaje!.startsWith('✅')
                    ? const Color(0xFF00E650).withValues(alpha: 0.4)
                    : Colors.red.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              _codigoCortesiaMensaje!,
              style: TextStyle(
                color: _codigoCortesiaMensaje!.startsWith('✅')
                    ? const Color(0xFF00E650)
                    : Colors.red,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// CTA principal — siempre visible y con `onPressed` explícito (nunca null).
  Future<void> _onTrialButtonPressed() async {
    if (_isLoading) return;

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    try {
      if (!PremiumService.isConfigured) {
        final ok = await PremiumService.ensureConfigured();
        if (!ok) {
          _snack('Servicio temporalmente no disponible');
          return;
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final gate = await DeviceTrialService.verifyTrialAllowedForUser(user)
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () => DeviceTrialGateResult.allowed(),
        );
        if (!gate.allowed) {
          _snack(
            gate.blockMessage ?? 'Prueba no disponible en este dispositivo.',
          );
          return;
        }
      }

      final offerings = await Purchases.getOfferings().timeout(
        const Duration(seconds: 20),
      );
      debugPrint('Offerings: ${offerings.current?.identifier}');

      final offering =
          offerings.getOffering(PremiumService.offeringId) ?? offerings.current;

      if (offering == null) {
        _snack('Servicio no disponible, intentá de nuevo');
        return;
      }

      _aplicarOffering(offering);
      if (mounted) setState(() {});

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

      var info = result.customerInfo;
      var activo = PremiumService.hasPremiumEntitlement(info);
      if (!activo) {
        info = await PremiumService.fetchCustomerInfoFresh();
        activo = PremiumService.hasPremiumEntitlement(info);
      }
      debugPrint('Paywall post-purchase premium=$activo trialKeys=${info.entitlements.active.keys}');

      if (!mounted) return;
      if (activo) {
        Navigator.pop(context, true);
      } else {
        _snack('Compra registrada. Tocá Restaurar compra si el contenido no aparece.');
      }
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
    } on TimeoutException {
      _snack('Servicio no disponible, intentá de nuevo');
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
    HapticFeedback.selectionClick();
    setState(() => _isLoading = true);
    try {
      if (!PremiumService.isConfigured) {
        final ok = await PremiumService.ensureConfigured();
        if (!ok) {
          _snack('Servicio temporalmente no disponible');
          return;
        }
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

  Widget _trialCtaButton() {
    return AbsorbPointer(
      absorbing: false,
      child: Semantics(
        button: true,
        enabled: true,
        label: 'Empezar prueba gratis, 14 días gratis',
        child: Material(
          color: _green,
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          child: InkWell(
            onTap: () {
              if (_isLoading) return;
              unawaited(_onTrialButtonPressed());
            },
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _gold,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'EMPEZAR PRUEBA GRATIS',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '14 días gratis',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: _isLoading
                    ? null
                    : () => Navigator.pop(context, false),
              ),
            ),
            Expanded(child: _scrollContent()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _trialCtaButton(),
            const SizedBox(height: 8),
            _legalLinksRow(),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                if (_isLoading) return;
                unawaited(_restaurar());
              },
              child: const Text(
                'Restaurar compra',
                style: TextStyle(
                  color: Colors.white38,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Text(
              'Se cobra automáticamente. Cancelá cuando quieras.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        children: [
          if (_loadingOfferings)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Cargando planes…',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
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
          Image.asset('assets/images/matchi.png', height: 100, fit: BoxFit.contain),
          const SizedBox(height: 10),
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
          const SizedBox(height: 16),
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
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _planCard(
            index: 0,
            titulo: 'MENSUAL',
            precio: _precioMensualDisplay(),
            subtitulo: 'Probá 14 días gratis',
            destacado: false,
          ),
          const SizedBox(height: 10),
          _planCard(
            index: 1,
            titulo: '⭐ ANUAL  — AHORRÁ 16%',
            precio: _precioAnualDisplay(),
            subtitulo: '${_precioAnualPorMes()}\nProbá 14 días gratis',
            destacado: true,
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 18),
            _codigoCortesiaSection(),
          ],
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading
            ? null
            : () => setState(() => _planSeleccionado = index),
        borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }
}
