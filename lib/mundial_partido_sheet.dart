import 'package:flutter/material.dart';

import 'api_service.dart';
import 'mundial_seleccion_sheet.dart';
import 'mundial_service.dart';
import 'nationality_flags.dart';
import 'player_career_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Detalle / insert de partido Mundial (prematch + jugado en vivo / finalizado)
// ─────────────────────────────────────────────────────────────────────────────

String _cleanName(String name) {
  return String.fromCharCodes(name.runes.where((r) => r <= 0xFFFF)).trim();
}

int? _intFromDyn(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

(String nombre, String? pais) _splitArbitro(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == 'No disponible') return ('', null);
  final i = t.lastIndexOf(',');
  if (i <= 0 || i >= t.length - 1) return (t, null);
  return (t.substring(0, i).trim(), t.substring(i + 1).trim());
}

/// weekday 1 = lunes … 7 = domingo
const _diasLunADom = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

bool _statusEsModoJugado(String short) {
  return const {
    'FT',
    'AET',
    'PEN',
    '1H',
    '2H',
    'HT',
    'ET',
    'P',
  }.contains(short);
}

Widget _encabezadoEquipoSeleccion(
  BuildContext context, {
  required int teamId,
  required String teamName,
  required String teamLogo,
  required String country,
  required TextAlign textAlign,
}) {
  final flag = flagEmojiFromCountryName(country);
  final col = Column(
    crossAxisAlignment:
        textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      if (teamLogo.isNotEmpty)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            teamLogo,
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40),
          ),
        ),
      if (flag.isNotEmpty) Text(flag, style: const TextStyle(fontSize: 20)),
      Text(
        teamName,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        textAlign: textAlign,
      ),
      if (teamId > 0)
        Text(
          'Toca · ficha selección',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 9),
          textAlign: textAlign,
        ),
    ],
  );

  if (teamId <= 0) {
    return col;
  }
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showMundialSeleccionSheet(
        context,
        teamId: teamId,
        teamName: teamName,
        teamLogo: teamLogo,
        country: country.isNotEmpty ? country : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: col,
      ),
    ),
  );
}

void showMundialPartidoSheet(BuildContext context, Map<String, dynamic> partido) {
  final fixture = partido['fixture'] as Map<String, dynamic>? ?? {};
  final teams = partido['teams'] as Map<String, dynamic>? ?? {};
  final goals = partido['goals'] as Map<String, dynamic>? ?? {};

  final fixtureId = fixture['id'] as int?;
  final home = teams['home'] as Map<String, dynamic>? ?? {};
  final away = teams['away'] as Map<String, dynamic>? ?? {};
  final local = home['name'] as String? ?? '';
  final visitante = away['name'] as String? ?? '';
  final homeId = home['id'] as int? ?? 0;
  final awayId = away['id'] as int? ?? 0;
  final homeCountry = home['country'] as String? ?? '';
  final awayCountry = away['country'] as String? ?? '';
  final status = fixture['status']?['short'] as String? ?? '';
  final elapsed = fixture['status']?['elapsed'];
  final isLive = const {'1H', '2H', 'HT', 'ET', 'P'}.contains(status);
  final jugado = _statusEsModoJugado(status);

  final gh = goals['home'];
  final ga = goals['away'];
  final resultado = (jugado || gh != null || ga != null)
      ? '${gh ?? 0} - ${ga ?? 0}'
      : '-';

  if (fixtureId == null) return;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1B2A3B),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.45,
      expand: false,
      builder: (ctx2, scrollController) => FutureBuilder<List<dynamic>>(
        future: jugado
            ? Future.wait<dynamic>([
                ApiService.getEstadisticasPartido(fixtureId),
                ApiService.getEventosPartido(fixtureId),
                ApiService.getLineupsPartido(fixtureId),
                ApiService.getDetallePartido(fixtureId),
                ApiService.getPlayersPartido(fixtureId.toString()),
              ])
            : Future.wait<dynamic>([
                ApiService.getLineupsPartido(fixtureId),
                ApiService.getDetallePartido(fixtureId),
                MundialService.getPreviewEquipoMundial(homeId),
                MundialService.getPreviewEquipoMundial(awayId),
              ]),
        builder: (context, snap) {
          if (jugado) {
            return _buildListaJugado(
              context: context,
              scrollController: scrollController,
              snap: snap,
              partido: partido,
              local: local,
              visitante: visitante,
              resultado: resultado,
              fixtureId: fixtureId,
              isLive: isLive,
              minuto: elapsed != null ? "$elapsed'" : '',
            );
          }
          return _buildListaPrematch(
            context: context,
            scrollController: scrollController,
            snap: snap,
            partido: partido,
            local: local,
            visitante: visitante,
            homeCountry: homeCountry,
            awayCountry: awayCountry,
          );
        },
      ),
    ),
  );
}

Widget _seccion(String titulo) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(
      titulo,
      style: const TextStyle(
        color: Color(0xFF00C853),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    ),
  );
}

Widget _statRow(String stat, String localVal, String visitVal) {
  final vLocal = double.tryParse(localVal.replaceAll('%', '').replaceAll('-', '0')) ?? 0;
  final vVisit = double.tryParse(visitVal.replaceAll('%', '').replaceAll('-', '0')) ?? 0;
  final total = vLocal + vVisit;
  final pLocal = total > 0 ? vLocal / total : 0.5;
  final pVisit = total > 0 ? vVisit / total : 0.5;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(localVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(stat, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(visitVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              Expanded(flex: (pLocal * 100).round(), child: Container(height: 6, color: const Color(0xFF00C853))),
              Expanded(flex: (pVisit * 100).round(), child: Container(height: 6, color: const Color(0xFF1E88E5))),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _formacionLineal(
  BuildContext context,
  List<Map<String, dynamic>> lineups,
  String local,
  String visitante,
) {
  Widget equipoWidget(Map<String, dynamic> team, String nombre, Color color) {
    final clubFormId = _intFromDyn(team['team']?['id']);
    final formacion = team['formation'] as String? ?? '';
    final titulares = List<Map<String, dynamic>>.from(team['startXI'] ?? []);
    final suplentes = List<Map<String, dynamic>>.from(team['substitutes'] ?? []);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                nombre.toUpperCase(),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              if (formacion.isNotEmpty) ...[
                const Spacer(),
                Text(formacion, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...titulares.map((p) {
            final pl = p['player'] as Map<String, dynamic>? ?? {};
            final pid = _intFromDyn(pl['id']) ?? 0;
            final num = pl['number'] as int? ?? 0;
            final pnombre = _cleanName(pl['name'] as String? ?? '');
            final pos = pl['pos'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Center(child: Text('$num', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: pid > 0 && clubFormId != null
                          ? () => showPlayerCareerSheet(context, playerId: pid, clubTeamId: clubFormId, playerName: pnombre)
                          : null,
                      child: Text(pnombre, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                  Text(pos, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            );
          }),
          if (suplentes.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: suplentes.map((s) {
                final pl = s['player'] as Map<String, dynamic>? ?? {};
                final sid = _intFromDyn(pl['id']) ?? 0;
                final num = pl['number'] as int? ?? 0;
                final name = _cleanName(pl['name'] as String? ?? '').split(' ').last;
                return GestureDetector(
                  onTap: sid > 0 && clubFormId != null
                      ? () => showPlayerCareerSheet(context, playerId: sid, clubTeamId: clubFormId, playerName: name)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                    child: Text('$num $name', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  return Column(
    children: [
      equipoWidget(lineups[0], local, const Color(0xFF00C853)),
      const SizedBox(height: 8),
      equipoWidget(lineups[1], visitante, const Color(0xFF1E88E5)),
    ],
  );
}

Widget _previewTorneoEquipo(String equipo, Map<String, dynamic> preview) {
  final topRating = List<Map<String, dynamic>>.from(preview['rating'] ?? []);
  final topGoles = List<Map<String, dynamic>>.from(preview['goles'] ?? []);
  final mejor = topRating.isNotEmpty ? topRating.first : null;
  final goleador = topGoles.isNotEmpty ? topGoles.first : null;
  if (mejor == null && goleador == null) return const SizedBox.shrink();

  Widget fila(String etiqueta, Map<String, dynamic>? p, {bool goles = false}) {
    if (p == null) return const SizedBox.shrink();
    final foto = p['foto'] as String? ?? '';
    final nombre = _cleanName(p['nombre'] as String? ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(etiqueta, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.white12,
            backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
            child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 12) : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          if (goles)
            Text('⚽ ${p['goles']}', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold))
          else
            Text('★ ${(p['rating'] as double).toStringAsFixed(1)}',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2A3B),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(equipo.toUpperCase(),
            style: const TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        fila('Mejor rating (Mundial)', mejor, goles: false),
        fila('Goleador (Mundial)', goleador, goles: true),
      ],
    ),
  );
}

Widget _prematchInfoCard(
  String estadio,
  String ciudad,
  String arbitroRaw,
  DateTime? matchDateTime,
) {
  final horario = matchDateTime != null
      ? '${matchDateTime.hour.toString().padLeft(2, '0')}:${matchDateTime.minute.toString().padLeft(2, '0')}'
      : '';
  final (arbitroNombre, arbitroPais) = _splitArbitro(arbitroRaw);
  final flagArb = flagEmojiFromCountryName(arbitroPais);

  String? diaLinea;
  if (matchDateTime != null) {
    final wd = _diasLunADom[(matchDateTime.weekday - 1).clamp(0, 6)];
    diaLinea =
        '$wd ${matchDateTime.day.toString().padLeft(2, '0')}/${matchDateTime.month.toString().padLeft(2, '0')}/${matchDateTime.year}';
  }

  return FutureBuilder<Map<String, dynamic>>(
    future: estadio.isNotEmpty ? ApiService.getClimaEstadio(estadio, matchTime: matchDateTime) : Future.value({}),
    builder: (ctx, cSnap) {
      final clima = cSnap.data ?? {};
      final temp = clima['temp'];
      final desc = clima['descripcion'] as String? ?? '';
      final viento = clima['viento'];
      final humedad = clima['humedad'];
      final esForecast = clima['esForecast'] as bool? ?? false;
      final tieneClima = temp != null && desc.isNotEmpty;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (diaLinea != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today, color: Color(0xFF00C853), size: 14),
                  const SizedBox(width: 6),
                  Text(diaLinea, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (horario.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF00C853), size: 14),
                  const SizedBox(width: 6),
                  Text('Horario: $horario hs', style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            if (estadio.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.stadium, color: Colors.white38, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$estadio${ciudad.isNotEmpty ? ", $ciudad" : ""}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (arbitroNombre.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sports, color: Colors.white38, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(arbitroNombre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        if (arbitroPais != null && arbitroPais.isNotEmpty)
                          Text(
                            '$flagArb ${arbitroPais.trim()}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (tieneClima) ...[
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${ApiService.climaEmoji(desc)}  ${temp}°C',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis)),
                  if (viento != null) Text('💨 ${(viento as double).round()}km/h', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(width: 6),
                  if (humedad != null) Text('💧$humedad%', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
              if (esForecast)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Pronóstico al horario del partido',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic)),
                ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _incidencia(String icono, String minuto, String tipo, String equipo, {bool esVar = false}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: esVar ? Colors.amber.withValues(alpha: 0.06) : const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: esVar ? Colors.amber.withValues(alpha: 0.25) : Colors.white10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icono, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        SizedBox(width: 36, child: Text(minuto, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tipo, style: const TextStyle(color: Colors.white, fontSize: 12)),
              if (equipo.isNotEmpty) Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildListaPrematch({
  required BuildContext context,
  required ScrollController scrollController,
  required AsyncSnapshot<List<dynamic>> snap,
  required Map<String, dynamic> partido,
  required String local,
  required String visitante,
  required String homeCountry,
  required String awayCountry,
}) {
  if (snap.connectionState == ConnectionState.waiting) {
    return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF00C853))));
  }

  final lineups = List<Map<String, dynamic>>.from(snap.data?[0] ?? []);
  final detalle = snap.data?[1] as Map<String, dynamic>?;
  final previewHome = snap.data?[2] as Map<String, dynamic>? ?? {};
  final previewAway = snap.data?[3] as Map<String, dynamic>? ?? {};

  final rawDate = detalle?['fixture']?['date'] as String? ?? partido['fixture']?['date'] as String?;
  final matchDateTime = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
  final arbitro = detalle?['fixture']?['referee']?.toString() ?? 'No disponible';
  final estadio = detalle?['fixture']?['venue']?['name'] as String? ?? '';
  final ciudad = detalle?['fixture']?['venue']?['city'] as String? ?? '';

  final teamsPartido = partido['teams'] as Map<String, dynamic>? ?? {};
  final th = teamsPartido['home'] as Map<String, dynamic>? ?? {};
  final ta = teamsPartido['away'] as Map<String, dynamic>? ?? {};
  final homeIdTap = th['id'] as int? ?? 0;
  final awayIdTap = ta['id'] as int? ?? 0;
  final homeLogoTap = th['logo'] as String? ?? '';
  final awayLogoTap = ta['logo'] as String? ?? '';

  return ListView(
    controller: scrollController,
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _encabezadoEquipoSeleccion(
                context,
                teamId: homeIdTap,
                teamName: local,
                teamLogo: homeLogoTap,
                country: homeCountry,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('VS', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _encabezadoEquipoSeleccion(
                context,
                teamId: awayIdTap,
                teamName: visitante,
                teamLogo: awayLogoTap,
                country: awayCountry,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _prematchInfoCard(estadio, ciudad, arbitro, matchDateTime),
      const SizedBox(height: 12),
      if (lineups.length >= 2) ...[
        _seccion('FORMACIONES'),
        _formacionLineal(context, lineups, local, visitante),
        const SizedBox(height: 8),
      ],
      _seccion('DESTACADOS EN EL MUNDIAL'),
      _previewTorneoEquipo(local, previewHome),
      const SizedBox(height: 6),
      _previewTorneoEquipo(visitante, previewAway),
      const SizedBox(height: 24),
    ],
  );
}

Widget _buildListaJugado({
  required BuildContext context,
  required ScrollController scrollController,
  required AsyncSnapshot<List<dynamic>> snap,
  required Map<String, dynamic> partido,
  required String local,
  required String visitante,
  required String resultado,
  required int fixtureId,
  required bool isLive,
  required String minuto,
}) {
  if (snap.connectionState == ConnectionState.waiting) {
    return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF00C853))));
  }

  final stats = snap.data?[0] as Map<String, dynamic>?;
  final eventos = List<Map<String, dynamic>>.from(snap.data?[1] ?? []);
  final lineups = List<Map<String, dynamic>>.from(snap.data?[2] ?? []);
  final detalle = snap.data?[3] as Map<String, dynamic>?;
  final jugadores = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);

  final teamsDet = detalle?['teams'] as Map<String, dynamic>? ??
      partido['teams'] as Map<String, dynamic>? ??
      {};
  final th = teamsDet['home'] as Map<String, dynamic>? ?? {};
  final ta = teamsDet['away'] as Map<String, dynamic>? ?? {};
  final homeIdTap = th['id'] as int? ?? 0;
  final awayIdTap = ta['id'] as int? ?? 0;
  final homeLogoTap = th['logo'] as String? ?? '';
  final awayLogoTap = ta['logo'] as String? ?? '';
  final homeCountryTap = th['country'] as String? ?? '';
  final awayCountryTap = ta['country'] as String? ?? '';

  final arbitro = detalle?['fixture']?['referee'] ?? 'No disponible';
  final estadio = detalle?['fixture']?['venue']?['name'] ?? '';
  final ciudad = detalle?['fixture']?['venue']?['city'] ?? '';

  String moralLocal = '-', moralVisitante = '-', moralDesc = 'Calculando...';
  if (stats != null && stats['response'] != null && (stats['response'] as List).length >= 2) {
    final statLocal = List<Map<String, dynamic>>.from(stats['response'][0]['statistics'] ?? []);
    final statVisit = List<Map<String, dynamic>>.from(stats['response'][1]['statistics'] ?? []);
    double posLocal = 0, posVisit = 0;
    int tirosLocal = 0, tirosVisit = 0, cornersLocal = 0, cornersVisit = 0;
    for (var s in statLocal) {
      if (s['type'] == 'Ball Possession') posLocal = double.tryParse(s['value']?.toString().replaceAll('%', '') ?? '0') ?? 0;
      if (s['type'] == 'Shots on Goal') tirosLocal = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
      if (s['type'] == 'Corner Kicks') cornersLocal = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
    }
    for (var s in statVisit) {
      if (s['type'] == 'Ball Possession') posVisit = double.tryParse(s['value']?.toString().replaceAll('%', '') ?? '0') ?? 0;
      if (s['type'] == 'Shots on Goal') tirosVisit = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
      if (s['type'] == 'Corner Kicks') cornersVisit = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
    }
    final partes = resultado.split('-');
    final int glLocal = int.tryParse(partes.isNotEmpty ? partes[0].trim() : '0') ?? 0;
    final int glVisit = int.tryParse(partes.length > 1 ? partes[1].trim() : '0') ?? 0;
    int moralL = glLocal, moralV = glVisit;
    final double difPos = posLocal - posVisit;
    final int difTiros = tirosLocal - tirosVisit;
    final int difCorners = cornersLocal - cornersVisit;
    double dominio = 0;
    if (difPos.abs() > 25) dominio += difPos > 0 ? 1.5 : -1.5;
    else if (difPos.abs() > 15) dominio += difPos > 0 ? 1.0 : -1.0;
    if (difTiros.abs() >= 3) dominio += difTiros > 0 ? 1.0 : -1.0;
    else if (difTiros.abs() >= 1) dominio += difTiros > 0 ? 0.5 : -0.5;
    if (difCorners.abs() >= 5) dominio += difCorners > 0 ? 0.5 : -0.5;
    final int diferencia = (glLocal - glVisit).abs();
    final int ajuste = dominio.round().clamp(-1, 1);
    moralL += ajuste;
    moralV -= ajuste;
    if (moralL < 0) moralL = 0;
    if (moralV < 0) moralV = 0;
    if (diferencia == 1) {
      if (glLocal > glVisit && moralL < moralV) moralL = moralV;
      if (glVisit > glLocal && moralV < moralL) moralV = moralL;
    }
    if (glLocal == glVisit) {
      if (moralL > moralV + 1) moralL = moralV + 1;
      if (moralV > moralL + 1) moralV = moralL + 1;
    }
    moralLocal = moralL.toString();
    moralVisitante = moralV.toString();
    moralDesc = moralL > moralV ? '$local merecio ganar' : moralV > moralL ? '$visitante merecio ganar' : 'El resultado fue justo';
  }

  return ListView(
    controller: scrollController,
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _encabezadoEquipoSeleccion(
                context,
                teamId: homeIdTap,
                teamName: local,
                teamLogo: homeLogoTap,
                country: homeCountryTap,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10)),
            child: Text(resultado, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 22)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _encabezadoEquipoSeleccion(
                context,
                teamId: awayIdTap,
                teamName: visitante,
                teamLogo: awayLogoTap,
                country: awayCountryTap,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ],
      ),
      if (isLive) ...[
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF00C853), borderRadius: BorderRadius.circular(6)),
            child: Text(minuto.isNotEmpty ? 'EN VIVO · $minuto' : 'EN VIVO',
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (stats != null) ...[
        _seccion('INFO DEL PARTIDO'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.sports, color: Color(0xFF00C853), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Arbitro: $arbitro', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.stadium, color: Color(0xFF00C853), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$estadio${ciudad.isNotEmpty ? " - $ciudad" : ""}', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _seccion('PODIO DEL PARTIDO'),
        if (jugadores.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Sin ratings de jugadores', style: TextStyle(color: Colors.white38)),
          )
        else
          Builder(
            builder: (context) {
              final top = jugadores.take(3).toList();
              final orden = [if (top.length > 1) top[1], top[0], if (top.length > 2) top[2]];
              const medallas = ['🥈', '🥇', '🥉'];
              const medallaColors = [Color(0xFFC0C0C0), Color(0xFFFFD700), Color(0xFFCD7F32)];
              const alturas = [90.0, 120.0, 70.0];
              const posLabels = ['2°', '1°', '3°'];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(orden.length, (vi) {
                    final j = orden[vi];
                    final rating = j['rating'] as double;
                    final foto = j['foto'] as String? ?? '';
                    final nombre = (j['nombre'] as String).split(' ').last;
                    final equipo = j['equipo'] as String;
                    final altura = alturas[vi];
                    final medallaColor = medallaColors[vi];
                    final posLabel = posLabels[vi];
                    final esPrimero = vi == 1;
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: medallaColor, width: esPrimero ? 3 : 2),
                                  boxShadow: [BoxShadow(color: medallaColor.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)],
                                ),
                                child: CircleAvatar(
                                  radius: esPrimero ? 34 : 26,
                                  backgroundColor: const Color(0xFF1B2A3B),
                                  backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                                  child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
                                ),
                              ),
                              Positioned(
                                bottom: -6,
                                right: -4,
                                child: Text(medallas[vi], style: TextStyle(fontSize: esPrimero ? 16 : 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(nombre,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 2),
                          Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 9), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: rating >= 7.5 ? Colors.green : rating >= 6.5 ? const Color(0xFFFF9800) : Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: altura,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: medallaColor.withValues(alpha: 0.12),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                              border: Border(
                                top: BorderSide(color: medallaColor.withValues(alpha: 0.6), width: 2),
                                left: BorderSide(color: medallaColor.withValues(alpha: 0.25), width: 1),
                                right: BorderSide(color: medallaColor.withValues(alpha: 0.25), width: 1),
                              ),
                            ),
                            child: Center(child: Text(posLabel, style: TextStyle(color: medallaColor, fontSize: 22, fontWeight: FontWeight.bold))),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        _seccion('ESTADISTICAS'),
        ...((stats['response'] as List).isNotEmpty
            ? (stats['response'][0]['statistics'] as List)
                .where((s) => ['Ball Possession', 'Shots on Goal', 'Corner Kicks', 'Fouls'].contains(s['type']))
                .map((s) {
                final i = (stats['response'][0]['statistics'] as List).indexOf(s);
                final valVisit = i < (stats['response'][1]['statistics'] as List).length
                    ? stats['response'][1]['statistics'][i]['value']?.toString() ?? '-'
                    : '-';
                String label = s['type'];
                if (label == 'Ball Possession') label = 'Posesion';
                if (label == 'Shots on Goal') label = 'Tiros al arco';
                if (label == 'Corner Kicks') label = 'Corners';
                if (label == 'Fouls') label = 'Faltas';
                return _statRow(label, s['value']?.toString() ?? '-', valVisit);
              })
            : <Widget>[]),
        if (isLive) ...[
          const SizedBox(height: 12),
          _seccion('🧠 ALERTA IA'),
          FutureBuilder<String>(
            future: ApiService.getAlertaIA(
              local: local,
              visitante: visitante,
              resultado: resultado,
              minuto: minuto,
              stats: stats,
              eventos: eventos,
            ),
            builder: (context, snapIA) {
              if (snapIA.connectionState == ConnectionState.waiting) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853))),
                      SizedBox(width: 10),
                      Text('Analizando el partido...', style: TextStyle(color: Color(0xFF00C853), fontSize: 13)),
                    ],
                  ),
                );
              }
              final texto = snapIA.data ?? 'Sin análisis disponible.';
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
                ),
                child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
              );
            },
          ),
        ],
        if (eventos.isNotEmpty) ...[
          _seccion('FIGURA DEL PARTIDO MATCHGOL'),
          Builder(
            builder: (context) {
              final Map<String, int> puntos = {};
              final Map<String, String> equiposMap = {};
              for (var e in eventos) {
                final jugador = e['player']?['name'] ?? '';
                final tipo = e['type'] ?? '';
                final detEv = e['detail'] ?? '';
                final equipo = e['team']?['name'] ?? '';
                if (jugador.isEmpty) continue;
                puntos[jugador] ??= 0;
                equiposMap[jugador] = equipo;
                if (tipo == 'Goal' && detEv != 'Own Goal') puntos[jugador] = puntos[jugador]! + 3;
                if (tipo == 'Goal' && detEv == 'Own Goal') puntos[jugador] = puntos[jugador]! - 2;
                if (tipo == 'subst') {
                  final sale = e['assist']?['name'] ?? '';
                  if (sale.isNotEmpty) {
                    puntos[sale] ??= 0;
                    equiposMap[sale] ??= equipo;
                  }
                }
                if (tipo == 'Card' && detEv == 'Yellow Card') puntos[jugador] = puntos[jugador]! - 1;
                if (tipo == 'Card' && detEv == 'Red Card') puntos[jugador] = puntos[jugador]! - 3;
              }
              if (puntos.isEmpty) return const SizedBox.shrink();
              final sorted = puntos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              final figura = jugadores.isNotEmpty ? MapEntry(jugadores.first['nombre'] as String, 0) : sorted.first;

              MapEntry<String, dynamic> peor;
              final conRating = jugadores.where((j) => j['tieneRating'] == true && (j['minutos'] as int? ?? 0) >= 30).toList();
              if (conRating.isNotEmpty) {
                conRating.sort((a, b) => (a['rating'] as double).compareTo(b['rating'] as double));
                final peorJugador = conRating.first;
                peor = MapEntry(peorJugador['nombre'] as String, peorJugador['rating']);
                equiposMap[peorJugador['nombre'] as String] ??= peorJugador['equipo'] as String? ?? '';
              } else {
                final conNegativos = sorted.where((e) => e.value < 0).toList();
                peor = conNegativos.isNotEmpty ? conNegativos.last : sorted.last;
              }
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('FIGURA DEL PARTIDO',
                                  style: TextStyle(color: Color(0xFF00C853), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                              Text(_cleanName(figura.key), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              Text(equiposMap[figura.key] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('😤', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PARA QUE TE TRAJE',
                                  style: TextStyle(color: Colors.red, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                              Text(peor.key, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              Text(equiposMap[peor.key] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
        _seccion('RESULTADO MORAL'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(local, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('$moralLocal - $moralVisitante', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 20)),
                  Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Text('🧠 $moralDesc', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
        ),
        Builder(
          builder: (context) {
            if (jugadores.isEmpty) return const SizedBox.shrink();
            final jgs = jugadores.where((j) => (j['minutos'] as int? ?? 0) >= 30).toList();
            if (jgs.isEmpty) return const SizedBox.shrink();
            Map<String, dynamic>? tPases, tFaltas, tDribles;
            double maxP = -1, maxF = -1, maxR = -1;
            for (final j in jgs) {
              final p = double.tryParse(j['pases']?.toString() ?? '0') ?? 0;
              final f = (j['faltas'] as int? ?? 0).toDouble();
              final d = (j['driblesExito'] as int? ?? 0).toDouble();
              if (p > maxP) {
                maxP = p;
                tPases = j;
              }
              if (f > maxF) {
                maxF = f;
                tFaltas = j;
              }
              if (d > maxR) {
                maxR = d;
                tDribles = j;
              }
            }
            Widget chipM(String emoji, String titulo, Map<String, dynamic>? j) {
              if (j == null) return const Expanded(child: SizedBox());
              final nombre = (j['nombre'] as String).split(' ').last;
              final foto = j['foto'] as String? ?? '';
              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 2),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF0D1B2A),
                      backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                      child: foto.isEmpty ? const Icon(Icons.person, size: 13, color: Colors.white38) : null,
                    ),
                    const SizedBox(height: 3),
                    Text(nombre,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis),
                    Text(titulo, style: const TextStyle(color: Colors.white38, fontSize: 9), textAlign: TextAlign.center),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  chipM('🎯', 'más pases precisos', tPases),
                  chipM('🦵', 'más faltas', tFaltas),
                  chipM('🪄', 'más regates', tDribles),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _seccion('INCIDENCIAS'),
        if (eventos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Sin incidencias disponibles', style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else
          ...eventos.where((e) => ['Goal', 'Card', 'subst', 'Var'].contains(e['type'])).map((e) {
            final tipo = e['type'];
            final min = "${e['time']['elapsed']}'";
            final equipo = e['team']['name'] ?? '';
            String icono = '⚽';
            String tipoText = 'Gol: ${e['player']['name'] ?? ''}';
            if (tipo == 'Card') {
              icono = e['detail'] == 'Yellow Card' ? '🟡' : '🔴';
              tipoText = '${e['detail'] == 'Yellow Card' ? 'Amarilla' : 'Roja'}: ${e['player']['name'] ?? ''}';
            } else if (tipo == 'subst') {
              icono = '🔄';
              tipoText = 'Entra: ${e['player']['name'] ?? ''} / Sale: ${e['assist']['name'] ?? ''}';
            } else if (tipo == 'Var') {
              icono = '📺';
              final detail = e['detail'] ?? '';
              String varDesc = 'VAR';
              if (detail == 'Goal cancelled') varDesc = 'VAR — Gol anulado';
              else if (detail == 'Penalty confirmed') varDesc = 'VAR — Penal confirmado';
              else if (detail == 'Penalty cancelled') varDesc = 'VAR — Penal anulado';
              else if (detail == 'Card upgrade') varDesc = 'VAR — Tarjeta revisada';
              else if (detail.isNotEmpty) varDesc = 'VAR — $detail';
              tipoText = varDesc;
            } else if (tipo == 'Goal') {
              final detail = e['detail'] ?? '';
              if (detail == 'Own Goal') {
                tipoText = 'Gol en contra: ${e['player']['name'] ?? ''}';
              } else if (detail == 'Penalty') {
                tipoText = 'Penal: ${e['player']['name'] ?? ''}';
              } else {
                tipoText = 'Gol: ${e['player']['name'] ?? ''}';
              }
            }
            return _incidencia(icono, min, tipoText, equipo, esVar: tipo == 'Var');
          }),
        const SizedBox(height: 16),
        if (lineups.length >= 2) ...[
          _seccion('FORMACIONES'),
          _formacionLineal(context, lineups, local, visitante),
        ] else ...[
          _seccion('FORMACIONES'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Sin formaciones disponibles', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ] else ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No hay estadisticas disponibles', style: TextStyle(color: Colors.white38), textAlign: TextAlign.center),
        ),
      ],
      const SizedBox(height: 20),
    ],
  );
}
