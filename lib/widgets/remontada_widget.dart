import 'package:flutter/material.dart';

import '../services/remontada_service.dart';

/// Card de remontada (un equipo). El título de sección va en el padre, p. ej. `_detalleSeccion('REMONTADAS')`.
class RemontadaWidget extends StatelessWidget {
  const RemontadaWidget({
    super.key,
    required this.teamId,
    required this.season,
  });

  final int teamId;
  final int season;

  static const Color _card = Color(0xFF1B2A3B);
  static const Color _green = Color(0xFF00C853);

  @override
  Widget build(BuildContext context) {
    if (teamId <= 0 || season <= 0) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<RemontadaStats>(
      future: RemontadaService().getRemontadaStats(teamId, season),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(color: _green, strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            color: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              child: Text(
                'No se pudo cargar la estadística de remontada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              ),
            ),
          );
        }

        final s = snapshot.data ?? RemontadaStats.empty();
        final insuf = s.totalPartidosAbajo < RemontadaStats.minPartidosRecibePrimerGol;
        final pctWin = (s.porcentajeRemontada / 100).clamp(0.0, 1.0);

        return Card(
          color: _card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: _green.withValues(alpha: 0.22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_green.withValues(alpha: 0.9), _green.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tras recibir el primer gol del rival (${season - 1}-$season, hasta 45 FT)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (insuf) ...[
                      Text(
                        'Datos insuficientes',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Se necesitan al menos ${RemontadaStats.minPartidosRecibePrimerGol} partidos en los que recibió el primer gol (${s.totalPartidosAbajo} en esta muestra).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 11, height: 1.3),
                      ),
                    ] else ...[
                      Text(
                        '${s.porcentajeRemontada.toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'terminó ganando el partido',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: pctWin,
                          minHeight: 10,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(_green.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${s.totalPartidosAbajo} partidos en los que encajó el 1.er gol',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 10),
                      ),
                      if (s.minutoPromedioRemontada > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Gol que empata / da vuelta (promedio): min ${s.minutoPromedioRemontada.toStringAsFixed(0)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _remontadaChip('🏠 Local', '${s.porcentajeLocalRemontada.toStringAsFixed(0)}%'),
                          _remontadaChip('✈️ Visitante', '${s.porcentajeVisitanteRemontada.toStringAsFixed(0)}%'),
                          _remontadaChip('➖ Empató', '${s.porcentajeEmpate.toStringAsFixed(0)}%'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _remontadaChip(String label, String value) {
  return Expanded(
    child: Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Color(0xFF00C853), fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
