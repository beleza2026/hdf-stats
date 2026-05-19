import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../image_decode_helper.dart';
import '../services/hinchas_service.dart';
import 'tabla_hinchas_screen.dart';

/// Acciones de MI CUENTA (equipo favorito + tabla de hinchas).
class MiCuentaScreen {
  /// Abre el selector de equipo (misma grilla que el onboarding).
  static Future<bool?> openTeamPicker(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _TeamPickerScreen()),
    );
  }

  static void openTablaHinchas(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TablaHinchasScreen()),
    );
  }
}

class _TeamPickerScreen extends StatefulWidget {
  const _TeamPickerScreen();

  @override
  State<_TeamPickerScreen> createState() => _TeamPickerScreenState();
}

class _TeamPickerScreenState extends State<_TeamPickerScreen> {
  List<Map<String, dynamic>> _equipos = [];
  bool _cargando = true;
  int? _seleccionado;
  String? _nombreSeleccionado;
  String? _escudoSeleccionado;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final equipos = await ApiService.getEquiposLiga();
    final prefs = await SharedPreferences.getInstance();
    final actual = prefs.getInt('equipo_favorito_id');
    if (mounted) {
      setState(() {
        _equipos = equipos;
        _cargando = false;
        if (actual != null && actual != -1) {
          _seleccionado = actual;
          _nombreSeleccionado = prefs.getString('equipo_favorito_nombre');
          for (final e in equipos) {
            if (e['id'] == actual) {
              _escudoSeleccionado = e['escudo'] as String?;
              break;
            }
          }
        }
      });
    }
  }

  Future<void> _guardar() async {
    if (_seleccionado == null || _guardando) return;
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final anteriorId = prefs.getInt('equipo_favorito_id');

      await HinchasService.setFavoriteTeam(
        teamId: _seleccionado!,
        teamName: _nombreSeleccionado ?? '',
        teamLogo: _escudoSeleccionado ?? '',
      );

      if (!kIsWeb) {
        final messaging = FirebaseMessaging.instance;
        if (anteriorId != null && anteriorId != -1 && anteriorId != _seleccionado) {
          await messaging.unsubscribeFromTopic('equipo_$anteriorId');
        }
        await messaging.subscribeToTopic('equipo_${_seleccionado!}');
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E650)),
        title: const Text('Tu equipo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Elegí tu equipo de Liga Profesional',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sumás +1 hincha en la tabla global y personalizás la app.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_cargando)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF00E650))))
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _equipos.length,
                    itemBuilder: (context, i) {
                      final eq = _equipos[i];
                      final selec = _seleccionado == eq['id'];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _seleccionado = eq['id'] as int;
                          _nombreSeleccionado = eq['nombre'] as String?;
                          _escudoSeleccionado = eq['escudo'] as String?;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: selec ? const Color(0xFF00E650).withValues(alpha: 0.12) : const Color(0xFF1B2A3B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selec ? const Color(0xFF00E650) : Colors.white12,
                              width: selec ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              DecodedNetworkImage(
                                eq['escudo'] as String,
                                width: 40,
                                height: 40,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.shield, color: Colors.white38, size: 40),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  eq['nombre'] as String,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selec ? const Color(0xFF00E650) : Colors.white70,
                                    fontSize: 9,
                                    fontWeight: selec ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _seleccionado != null && !_guardando ? _guardar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E650),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
