import 'package:flutter/material.dart';

import '../services/posesion_mundial_service.dart';
import '../widgets/posesion_card.dart';

/// Tab POSESIÓN — promedio de posesión por selección (Mundial 2026).
class PosesionMundialScreen extends StatefulWidget {
  const PosesionMundialScreen({super.key});

  @override
  State<PosesionMundialScreen> createState() => _PosesionMundialScreenState();
}

class _PosesionMundialScreenState extends State<PosesionMundialScreen> {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00C853);

  late Future<List<PosesionMundialEquipo>> _future;

  @override
  void initState() {
    super.initState();
    _cargar(refrescar: true);
  }

  void _cargar({bool refrescar = false}) {
    setState(() {
      _future = PosesionMundialService.getRanking(forceRefresh: refrescar);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _green,
        onRefresh: () async {
          PosesionMundialService.clearCache();
          _cargar(refrescar: true);
          await _future;
        },
        child: FutureBuilder<List<PosesionMundialEquipo>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: _green),
                        SizedBox(height: 14),
                        Text(
                          'Calculando posesión promedio…',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'No se pudo cargar la tabla.\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => _cargar(refrescar: true),
                      child: const Text('Reintentar', style: TextStyle(color: _green)),
                    ),
                  ),
                ],
              );
            }

            final filas = snap.data ?? [];
            if (filas.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  _HeaderPosesion(),
                  SizedBox(height: 24),
                  Text(
                    'Aún no hay datos de posesión en partidos finalizados del Mundial.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                ],
              );
            }

            final maxPos = filas.first.promedioPosesion;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                const _HeaderPosesion(),
                const SizedBox(height: 8),
                ...filas.asMap().entries.map((e) {
                  final rel = maxPos > 0 ? e.value.promedioPosesion / maxPos : 0.0;
                  return PosesionCard(
                    posicion: e.key + 1,
                    equipo: e.value,
                    barraRelativa: rel,
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderPosesion extends StatelessWidget {
  const _HeaderPosesion();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'POSESIÓN PROMEDIO 🌍',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF00E650),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Promedio de posesión por selección en el Mundial 2026',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}
