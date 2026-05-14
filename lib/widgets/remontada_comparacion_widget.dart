import 'package:flutter/material.dart';

import '../services/remontada_service.dart';

/// Comparación local vs visitante: % de victorias tras recibir el primer gol (temporada).
class RemontadaComparacionWidget extends StatelessWidget {
  const RemontadaComparacionWidget({
    super.key,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeName,
    required this.awayName,
    required this.season,
  });

  final int homeTeamId;
  final int awayTeamId;
  final String homeName;
  final String awayName;
  final int season;

  static const Color _card = Color(0xFF1B2A3B);
  static const Color _green = Color(0xFF00C853);
  static const Color _awayAccent = Color(0xFF42A5F5);

  String _abrev(String raw, {int max = 14}) {
    final t = raw.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    if (homeTeamId <= 0 || awayTeamId <= 0 || season <= 0 || homeTeamId == awayTeamId) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<RemontadaStats>>(
      future: Future.wait([
        RemontadaService().getRemontadaStats(homeTeamId, season),
        RemontadaService().getRemontadaStats(awayTeamId, season),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: _green, strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!.length < 2) {
          return Card(
            color: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Text(
                'No se pudieron cargar las remontadas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              ),
            ),
          );
        }

        final h = snapshot.data![0];
        final a = snapshot.data![1];
        final okH = h.totalPartidosAbajo >= RemontadaStats.minPartidosRecibePrimerGol;
        final okA = a.totalPartidosAbajo >= RemontadaStats.minPartidosRecibePrimerGol;
        final pctH = h.porcentajeRemontada;
        final pctA = a.porcentajeRemontada;

        String veredicto;
        Color veredictoColor;
        if (!okH && !okA) {
          veredicto = 'Faltan partidos con 1.er gol en contra para comparar (mín. ${RemontadaStats.minPartidosRecibePrimerGol} por equipo).';
          veredictoColor = Colors.white38;
        } else if (!okH) {
          veredicto = 'Local: datos insuficientes. Visitante: ${pctA.toStringAsFixed(0)}% victorias al ir abajo (${a.totalPartidosAbajo} PJ).';
          veredictoColor = Colors.white54;
        } else if (!okA) {
          veredicto = 'Visitante: datos insuficientes. Local: ${pctH.toStringAsFixed(0)}% victorias al ir abajo (${h.totalPartidosAbajo} PJ).';
          veredictoColor = Colors.white54;
        } else {
          final diff = pctH - pctA;
          if (diff.abs() < 4) {
            veredicto = 'Históricamente parejos al recibir el primer gol.';
            veredictoColor = Colors.white60;
          } else if (diff > 0) {
            veredicto = '🔥 ${_abrev(homeName)} levanta más según la muestra (${pctH.toStringAsFixed(0)}% vs ${pctA.toStringAsFixed(0)}%).';
            veredictoColor = _green;
          } else {
            veredicto = '🔥 ${_abrev(awayName)} levanta más según la muestra (${pctA.toStringAsFixed(0)}% vs ${pctH.toStringAsFixed(0)}%).';
            veredictoColor = _awayAccent;
          }
        }

        final sum = pctH + pctA;
        int flexLocal = 50;
        int flexVisit = 50;
        if (okH && okA && sum > 0.5) {
          final ratio = (pctH / sum).clamp(0.08, 0.92);
          flexLocal = (ratio * 100).round().clamp(8, 92);
          flexVisit = 100 - flexLocal;
        } else if (okH && !okA) {
          flexLocal = 85;
          flexVisit = 15;
        } else if (!okH && okA) {
          flexLocal = 15;
          flexVisit = 85;
        }

        return Card(
          color: _card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: _green.withValues(alpha: 0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_green.withValues(alpha: 0.85), _awayAccent.withValues(alpha: 0.85)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Quién suele levantar más si recibe el 1.er gol?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _abrev(homeName),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                          ),
                        ),
                        Text(
                          'VS',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: Text(
                            _abrev(awayName),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            Expanded(
                              flex: flexLocal,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_green.withValues(alpha: 0.35), _green.withValues(alpha: 0.12)],
                                  ),
                                ),
                                child: Text(
                                  okH ? '${pctH.toStringAsFixed(0)}%' : '—',
                                  style: TextStyle(
                                    color: okH ? Colors.white : Colors.white38,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: flexVisit,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerRight,
                                    end: Alignment.centerLeft,
                                    colors: [_awayAccent.withValues(alpha: 0.35), _awayAccent.withValues(alpha: 0.1)],
                                  ),
                                ),
                                child: Text(
                                  okA ? '${pctA.toStringAsFixed(0)}%' : '—',
                                  style: TextStyle(
                                    color: okA ? Colors.white : Colors.white38,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Barra según % victorias al recibir el 1.er gol. Muestra: hasta 45 FT recientes (${season - 1}-$season).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 10, height: 1.2),
                    ),
                    const SizedBox(height: 14),
                    _barraEquipo(
                      label: '🏠 ${_abrev(homeName)}',
                      pct: okH ? pctH : null,
                      n: h.totalPartidosAbajo,
                      color: _green,
                    ),
                    const SizedBox(height: 8),
                    _barraEquipo(
                      label: '✈️ ${_abrev(awayName)}',
                      pct: okA ? pctA : null,
                      n: a.totalPartidosAbajo,
                      color: _awayAccent,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Text(
                        veredicto,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: veredictoColor, fontSize: 12, height: 1.35, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _barraEquipo({
    required String label,
    required double? pct,
    required int n,
    required Color color,
  }) {
    final v = pct != null ? (pct / 100).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
            ),
            Text(
              pct != null ? '${pct.toStringAsFixed(0)}% victorias' : 'Sin datos',
              style: TextStyle(color: color.withValues(alpha: 0.95), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct != null ? v : 0,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.85)),
          ),
        ),
        Text(
          '$n partidos recibiendo el 1.er gol (muestra)',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 9),
        ),
      ],
    );
  }
}
