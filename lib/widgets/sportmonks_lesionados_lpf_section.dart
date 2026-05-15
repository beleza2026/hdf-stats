import 'package:flutter/material.dart';

import '../services/sportmonks_service.dart';

/// Tarjeta compacta en el hub Liga Argentina: resumen + ir al listado completo.
class SportmonksLesionadosLpfHubCard extends StatefulWidget {
  const SportmonksLesionadosLpfHubCard({super.key, required this.onVerTodos});

  final VoidCallback onVerTodos;

  @override
  State<SportmonksLesionadosLpfHubCard> createState() => _SportmonksLesionadosLpfHubCardState();
}

class _SportmonksLesionadosLpfHubCardState extends State<SportmonksLesionadosLpfHubCard> {
  late Future<SportmonksLpfInjuriesSnapshot> _future =
      SportmonksService().getLigaProfesionalArgentinaInjuries();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportmonksLpfInjuriesSnapshot>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final data = snap.data;
        final err = data?.errorMessage;
        final n = data?.rows.length ?? 0;
        final season = data?.resolvedSeasonId;

        String subtitle;
        if (loading) {
          subtitle = 'Consultando Sportmonks…';
        } else if (err != null && err.isNotEmpty) {
          subtitle = err;
        } else if (n == 0) {
          subtitle = 'Sin lesionados activos listados (o sin cobertura para esta temporada).';
        } else {
          subtitle =
              '$n jugador${n == 1 ? '' : 'es'} con baja por lesión · datos Sportmonks${season != null ? ' · temporada #$season' : ''}';
        }

        return GestureDetector(
          onTap: widget.onVerTodos,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A3B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🏥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'LESIONADOS · Sportmonks',
                        style: TextStyle(
                          color: Color(0xFFFF5252),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (!loading)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.refresh, color: Colors.white38, size: 20),
                        tooltip: 'Actualizar',
                        onPressed: () {
                          setState(() {
                            _future = SportmonksService().getLigaProfesionalArgentinaInjuries(forceRefresh: true);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: err != null && err.isNotEmpty ? Colors.white70 : Colors.white38,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                if (!loading && err == null && n > 0) ...[
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Ver listado completo', style: TextStyle(color: Color(0xFF00C853), fontSize: 10)),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: Color(0xFF00C853), size: 18),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pantalla completa: listado de lesionados LPF (Sportmonks).
class SportmonksLesionadosLpfFullPage extends StatefulWidget {
  const SportmonksLesionadosLpfFullPage({super.key});

  @override
  State<SportmonksLesionadosLpfFullPage> createState() => _SportmonksLesionadosLpfFullPageState();
}

class _SportmonksLesionadosLpfFullPageState extends State<SportmonksLesionadosLpfFullPage> {
  late Future<SportmonksLpfInjuriesSnapshot> _future =
      SportmonksService().getLigaProfesionalArgentinaInjuries();

  Future<void> _reload({bool force = true}) async {
    setState(() {
      _future = SportmonksService().getLigaProfesionalArgentinaInjuries(forceRefresh: force);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFFFF5252),
      onRefresh: () => _reload(force: true),
      child: FutureBuilder<SportmonksLpfInjuriesSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator(color: Color(0xFFFF5252))),
              ],
            );
          }
          final data = snap.data!;
          final err = data.errorMessage;
          if (err != null && err.isNotEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 40),
                Text(err, style: const TextStyle(color: Colors.white70, height: 1.4)),
              ],
            );
          }
          final rows = data.rows;
          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: const [
                SizedBox(height: 60),
                Text(
                  'Sin lesionados activos en Sportmonks para esta temporada, o el plan no incluye sidelined.',
                  style: TextStyle(color: Colors.white38, height: 1.35),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                'Solo lesiones (se excluyen suspensiones por palabras clave). Temporada Sportmonks: ${data.resolvedSeasonId ?? '—'}.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 12),
              ...rows.map(_rowCard),
            ],
          );
        },
      ),
    );
  }

  Widget _rowCard(SportmonksInjuryRow r) {
    final detail = <String>[
      if (r.category != null && r.category!.trim().isNotEmpty) r.category!.trim(),
      if (r.typeLabel != null && r.typeLabel!.trim().isNotEmpty && r.typeLabel != r.category) r.typeLabel!.trim(),
    ].join(' · ');
    final fechas = <String>[
      if (r.startDate != null && r.startDate!.trim().isNotEmpty) 'desde ${r.startDate!.trim()}',
      if (r.endDate != null && r.endDate!.trim().isNotEmpty) 'hasta ${r.endDate!.trim()}',
    ].join(' ');
    final gm = r.gamesMissed != null && r.gamesMissed! > 0 ? '${r.gamesMissed} PJ fuera' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.playerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Text(r.teamName, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: Color(0xFFFFAB00), fontSize: 10)),
          ],
          if (fechas.isNotEmpty || gm.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text([fechas, gm].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}
