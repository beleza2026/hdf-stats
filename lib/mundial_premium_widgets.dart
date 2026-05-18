import 'package:flutter/material.dart';

import 'image_decode_helper.dart';
import 'mundial_service.dart';

/// Línea de tiempo de eventos (goles, tarjetas, cambios).
Widget mundialTimelineEventos(List<Map<String, dynamic>> eventos) {
  if (eventos.isEmpty) return const SizedBox.shrink();

  final items = <Map<String, dynamic>>[];
  for (final e in eventos) {
    final time = e['time'] as Map<String, dynamic>? ?? {};
    final min = (time['elapsed'] as num?)?.toInt() ?? 0;
    final extra = (time['extra'] as num?)?.toInt();
    final tipo = e['type'] as String? ?? '';
    final det = e['detail'] as String? ?? '';
    final team = e['team']?['name'] as String? ?? '';
    final player = e['player']?['name'] as String? ?? '';
    items.add({
      'min': min,
      'extra': extra,
      'tipo': tipo,
      'det': det,
      'team': team,
      'player': player,
    });
  }
  items.sort((a, b) => (a['min'] as int).compareTo(b['min'] as int));

  IconData iconFor(String tipo, String det) {
    final d = det.toLowerCase();
    if (tipo == 'Goal') return Icons.sports_soccer;
    if (d.contains('red')) return Icons.square;
    if (d.contains('yellow')) return Icons.square;
    if (tipo == 'subst') return Icons.swap_horiz;
    return Icons.circle;
  }

  Color colorFor(String tipo, String det) {
    final d = det.toLowerCase();
    if (tipo == 'Goal') return const Color(0xFF00C853);
    if (d.contains('red')) return Colors.redAccent;
    if (d.contains('yellow')) return Colors.amber;
    return Colors.white54;
  }

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2A3B),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LÍNEA DE TIEMPO',
          style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 10),
        ...items.take(24).map((it) {
          final min = it['min'] as int;
          final extra = it['extra'] as int?;
          final minTxt = extra != null && extra > 0 ? "$min+$extra'" : "$min'";
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(minTxt, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Icon(iconFor(it['tipo'] as String, it['det'] as String),
                    size: 16, color: colorFor(it['tipo'] as String, it['det'] as String)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${it['player']} · ${it['det']}${(it['team'] as String).isNotEmpty ? ' (${it['team']})' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

/// Barra de dominio / momento del partido.
Widget mundialBarraMomento({
  required double posesionLocal,
  required double posesionVisit,
  required int golesLocal,
  required int golesVisit,
  required String local,
  required String visitante,
}) {
  final total = posesionLocal + posesionVisit;
  final pL = total > 0 ? posesionLocal / total : 0.5;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(local, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const Text('MOMENTO DEL PARTIDO', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold)),
          Text(visitante, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            Expanded(flex: (pL * 100).round().clamp(1, 99), child: Container(height: 8, color: const Color(0xFF00C853))),
            Expanded(flex: ((1 - pL) * 100).round().clamp(1, 99), child: Container(height: 8, color: const Color(0xFF1E88E5))),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Posesión ${posesionLocal.round()}% · ${posesionVisit.round()}%  ·  Marcador $golesLocal-$golesVisit',
        style: const TextStyle(color: Colors.white38, fontSize: 10),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

/// Resumen post-partido en 3 bullets.
Widget mundialResumen30Segundos({
  required String local,
  required String visitante,
  required String moralDesc,
  required int tirosLocal,
  required int tirosVisit,
  required int cornersLocal,
  required int cornersVisit,
}) {
  final dominio = tirosLocal + cornersLocal > tirosVisit + cornersVisit ? local : visitante;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF00C853).withValues(alpha: 0.12),
          const Color(0xFF1E88E5).withValues(alpha: 0.08),
        ],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCA28).withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFFFCA28), size: 16),
            SizedBox(width: 6),
            Text('RESUMEN HDF · 30 SEG', style: TextStyle(color: Color(0xFFFFCA28), fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        Text('• $moralDesc', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text('• Dominio en volumen: $dominio (tiros $tirosLocal-$tirosVisit, córners $cornersLocal-$cornersVisit)',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const Text('• Datos en vivo desde API-Football · Mundial 2026', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    ),
  );
}

List<Map<String, dynamic>> _jugadoresLineup(Map<String, dynamic> lineup) {
  final out = <Map<String, dynamic>>[];
  for (final key in ['startXI', 'substitutes']) {
    final list = lineup[key] as List?;
    if (list == null) continue;
    for (final raw in list) {
      final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final pl = m['player'] is Map ? Map<String, dynamic>.from(m['player'] as Map) : m;
      final pos = (pl['pos'] ?? pl['position'] ?? m['pos'] ?? 'M').toString().toUpperCase();
      out.add({
        'id': (pl['id'] as num?)?.toInt() ?? 0,
        'name': pl['name'] as String? ?? '',
        'pos': pos.isNotEmpty ? pos[0] : 'M',
      });
    }
  }
  return out;
}

Map<String, dynamic>? _pickPos(List<Map<String, dynamic>> list, String pos) {
  for (final j in list) {
    if ((j['pos'] as String?) == pos) return j;
  }
  return list.isNotEmpty ? list.first : null;
}

/// Duelos destacados entre titulares (heurística por posición).
Widget mundialDuelosClaveCard({
  required List<Map<String, dynamic>> lineups,
  required String local,
  required String visitante,
  Map<int, Map<String, dynamic>>? plantelHome,
  Map<int, Map<String, dynamic>>? plantelAway,
}) {
  if (lineups.length < 2) return const SizedBox.shrink();
  final h = _jugadoresLineup(lineups[0]);
  final a = _jugadoresLineup(lineups[1]);
  if (h.isEmpty || a.isEmpty) return const SizedBox.shrink();

  final duels = <({String l, String r, String label})>[
    (
      l: _pickPos(h, 'F')?['name'] as String? ?? h.first['name'] as String,
      r: _pickPos(a, 'D')?['name'] as String? ?? a.first['name'] as String,
      label: 'Ataque vs defensa',
    ),
    (
      l: _pickPos(h, 'M')?['name'] as String? ?? h[h.length ~/ 2]['name'] as String,
      r: _pickPos(a, 'M')?['name'] as String? ?? a[a.length ~/ 2]['name'] as String,
      label: 'Mediocampo',
    ),
    (
      l: _pickPos(h, 'G')?['name'] as String? ?? 'Arquero',
      r: _pickPos(a, 'F')?['name'] as String? ?? 'Delantero',
      label: 'Arquero vs referente',
    ),
  ];

  String mundialLine(int id, Map<int, Map<String, dynamic>>? idx) {
    if (idx == null || id <= 0) return '';
    final row = idx[id];
    if (row == null) return '';
    final m = MundialService.resumenMundialPlantel(row);
    return 'Mundial · PJ ${m.pj} · G ${m.goles}';
  }

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DUELOS CLAVE', style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        ...duels.map((d) {
          final idL = _pickPos(h, 'F')?['id'] as int? ?? 0;
          final idR = _pickPos(a, 'D')?['id'] as int? ?? 0;
          final subL = mundialLine(idL, plantelHome);
          final subR = mundialLine(idR, plantelAway);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: Text(d.l, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    const Text('vs', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    Expanded(
                      child: Text(d.r, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (subL.isNotEmpty || subR.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('$subL · $subR', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ),
              ],
            ),
          );
        }),
        Text('$local vs $visitante', style: const TextStyle(color: Colors.white24, fontSize: 9)),
      ],
    ),
  );
}

/// Gráfico de barras: plantel por liga de club.
Widget mundialPlantelCapasCard(Map<String, dynamic> capas) {
  final ligas = List<Map<String, dynamic>>.from(capas['porLiga'] as List? ?? []);
  if (ligas.isEmpty) return const SizedBox.shrink();
  final max = ligas.fold<int>(0, (m, e) {
    final c = (e['cant'] as num?)?.toInt() ?? 0;
    return c > m ? c : m;
  });
  final edad = capas['edadPromedio'] as int? ?? 0;
  final pj = capas['conPJEnMundial'] as int? ?? 0;

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2A3B),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PLANTEL EN CAPAS', style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        Text('Edad prom. $edad años · $pj con PJ en este Mundial', style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 12),
        ...ligas.take(6).map((e) {
          final cant = (e['cant'] as num?)?.toInt() ?? 0;
          final liga = e['liga'] as String? ?? '';
          final flex = max > 0 ? ((cant / max) * 100).round().clamp(4, 100) : 4;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(liga, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: flex / 100,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF00C853),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('$cant', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

/// Lista de candidatos al título (tab EXTRA · récords).
Widget mundialCandidatosTituloLista(Map<String, dynamic> proyeccion) {
  final ranking = List<Map<String, dynamic>>.from(proyeccion['ranking'] as List? ?? []);
  final hay = proyeccion['hayDatos'] == true && ranking.isNotEmpty;
  final preliminar = proyeccion['esPreliminar'] == true;

  if (!hay) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        MundialService.esAntesDelInicioMundial2026Utc()
            ? 'El ranking HDF se activa con partidos y estadísticas del Mundial 2026.'
            : 'Sin candidatos calculables aún. Cuando haya partidos finalizados, verás el top aquí.',
        style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFFFFCA28).withValues(alpha: 0.1),
          const Color(0xFF00C853).withValues(alpha: 0.05),
        ],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCA28).withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.emoji_events, color: Color(0xFFFFCA28), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'CANDIDATOS AL TÍTULO',
                style: TextStyle(color: Color(0xFFFFCA28), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          preliminar
              ? 'Preliminar por tabla de grupos (aún sin partidos FT con stats).'
              : 'Índice HDF: puntos, goles, posesión, tiros y córners (${proyeccion['partidosConStats'] ?? 0} partidos con stats).',
          style: const TextStyle(color: Colors.white38, fontSize: 9, height: 1.3),
        ),
        const SizedBox(height: 12),
        ...ranking.take(8).toList().asMap().entries.map((entry) {
          final r = entry.value;
          final pos = entry.key + 1;
          final logo = r['logo'] as String? ?? '';
          final medal = pos == 1 ? '🥇' : pos == 2 ? '🥈' : pos == 3 ? '🥉' : '$pos.';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: pos <= 3 ? const Color(0xFF0D1B2A) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: pos == 1 ? Border.all(color: const Color(0xFFFFCA28).withValues(alpha: 0.5)) : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text(medal, style: const TextStyle(fontSize: 12))),
                if (logo.isNotEmpty)
                  DecodedNetworkImage(logo, width: 24, height: 24, errorBuilder: (_, __, ___) => const SizedBox(width: 24))
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['nombre'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        '${r['pts']} pts · GF ${r['gf']}-${r['ga']}${!preliminar ? ' · Pos ${r['posProm']}%' : ''}',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${r['indice']}', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${r['pctTitulo']}%', style: const TextStyle(color: Color(0xFFFFCA28), fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

/// Favoritos al título según índice HDF (forma en el torneo actual).
Widget mundialFavoritosTituloCard(
  Map<String, dynamic> proyeccion, {
  required String local,
  required String visitante,
}) {
  final ranking = List<Map<String, dynamic>>.from(proyeccion['ranking'] as List? ?? []);
  final loc = proyeccion['local'] as Map<String, dynamic>?;
  final vis = proyeccion['visitante'] as Map<String, dynamic>?;
  final hay = proyeccion['hayDatos'] == true && ranking.isNotEmpty;

  if (!hay) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        MundialService.esAntesDelInicioMundial2026Utc()
            ? 'El índice HDF se activa cuando haya partidos del Mundial con tabla y estadísticas.'
            : 'Aún no hay suficientes partidos jugados para calcular favoritos al título.',
        style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
      ),
    );
  }

  Widget chipEquipoPartido(Map<String, dynamic>? e, String label, Color accent) {
    if (e == null) {
      return Expanded(
        child: Text('$label: sin datos en tabla', style: const TextStyle(color: Colors.white38, fontSize: 10)),
      );
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${e['nombre']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('#${e['puesto']} · Índice ${e['indice']}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            Text('${e['pctTitulo']}% poder · ${e['pts']} pts', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w600)),
            Text('Pos ${e['posProm']}% · Tiros ${e['tirosProm']} · Cor ${e['cornersProm']}', style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFFFFCA28).withValues(alpha: 0.08),
          const Color(0xFF00C853).withValues(alpha: 0.06),
        ],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCA28).withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.emoji_events, color: Color(0xFFFFCA28), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'FAVORITOS AL TÍTULO · ÍNDICE HDF',
                style: TextStyle(color: Color(0xFFFFCA28), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Pts, goles, posesión, tiros al arco y córners en partidos del torneo (${proyeccion['partidosConStats'] ?? 0} con stats).',
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chipEquipoPartido(loc, local.toUpperCase(), const Color(0xFF00C853)),
            const SizedBox(width: 8),
            chipEquipoPartido(vis, visitante.toUpperCase(), const Color(0xFF1E88E5)),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Top del torneo', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...ranking.take(6).toList().asMap().entries.map((entry) {
          final r = entry.value;
          final pos = entry.key + 1;
          final logo = r['logo'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('$pos', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                if (logo.isNotEmpty)
                  DecodedNetworkImage(logo, width: 20, height: 20, errorBuilder: (_, __, ___) => const SizedBox(width: 20))
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r['nombre'] as String? ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
                Text('${r['indice']}', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 6),
                Text('${r['pctTitulo']}%', style: const TextStyle(color: Color(0xFFFFCA28), fontSize: 10)),
              ],
            ),
          );
        }),
      ],
    ),
  );
}
