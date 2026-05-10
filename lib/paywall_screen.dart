import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'device_trial_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  /// Abre el paywall a pantalla completa; devuelve `true` si hubo compra/restauración exitosa.
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
  Package? _mensual;
  Package? _anual;
  bool _loading = true;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _cargarOfertas();
  }

  Future<void> _cargarOfertas() async {
    try {
      final offerings = await Purchases.getOfferings();
      final oferta = offerings.getOffering('default_matchgol');
      if (oferta != null) {
        setState(() {
          _mensual = oferta.monthly;
          _anual = oferta.annual;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _comprar(Package package) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Iniciá sesión para suscribirte.')),
        );
      }
      return;
    }

    final gate = await DeviceTrialService.verifyTrialAllowedForUser(user);
    if (!gate.allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(gate.blockMessage ?? 'Prueba no disponible en este dispositivo.')),
        );
      }
      return;
    }

    setState(() => _purchasing = true);
    try {
      final result = await Purchases.purchasePackage(package);
      await DeviceTrialService.registerTrialIfApplicable(
        user: user,
        customerInfo: result.customerInfo,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compra cancelada')),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restaurar() async {
    setState(() => _purchasing = true);
    try {
      final info = await Purchases.restorePurchases();
      final activo = info.entitlements.active.containsKey('Premium');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(activo ? '✅ Premium restaurado' : 'No se encontró suscripción activa')),
        );
        if (activo) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al restaurar')),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 60),
                  const SizedBox(height: 16),
                  const Text('MatchGol Premium',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('El fútbol argentino con datos reales',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 32),

                  // Features
                  _feature('📊 Índice HDF™ — rating exclusivo por jugador'),
                  _feature('⚖️ Tabla Moral — la tabla que importa'),
                  _feature('🏆 Cruces hipotéticos según reglamento'),
                  _feature('🚨 Monitor de Bajas — lesiones y sanciones'),
                  _feature('⭐ Fantasy Draft IA — Fantasy Score HDF™'),
                  _feature('🔔 Alertas de partido en tiempo real'),
                  const SizedBox(height: 32),

                  // Trial badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: const Text('7 días gratis — cancelá cuando quieras',
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 24),

                  // Plan mensual
                  if (_mensual != null)
                    _planButton(
                      label: 'MENSUAL',
                      precio: _mensual!.storeProduct.priceString,
                      subtitulo: 'Primeros 500 suscriptores',
                      onTap: () => _comprar(_mensual!),
                      destacado: false,
                    ),
                  const SizedBox(height: 12),

                  // Plan anual
                  if (_anual != null)
                    _planButton(
                      label: 'ANUAL',
                      precio: _anual!.storeProduct.priceString,
                      subtitulo: '¡Ahorrás 2 meses!',
                      onTap: () => _comprar(_anual!),
                      destacado: true,
                    ),

                  const SizedBox(height: 32),

                  // Restaurar
                  TextButton(
                    onPressed: _purchasing ? null : _restaurar,
                    child: const Text('Restaurar compra',
                        style: TextStyle(color: Colors.white54, decoration: TextDecoration.underline)),
                  ),

                  const SizedBox(height: 8),
                  const Text('Al suscribirte aceptás los Términos de Servicio y la Política de Privacidad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11)),

                  if (_purchasing)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(color: Colors.amber),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _feature(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _planButton({
    required String label,
    required String precio,
    required String subtitulo,
    required VoidCallback onTap,
    required bool destacado,
  }) {
    return GestureDetector(
      onTap: _purchasing ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: destacado ? Colors.amber : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: destacado ? Colors.amber : Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      color: destacado ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              Text(subtitulo,
                  style: TextStyle(color: destacado ? Colors.black54 : Colors.white54, fontSize: 12)),
            ]),
            Text(precio,
                style: TextStyle(
                    color: destacado ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
    );
  }
}