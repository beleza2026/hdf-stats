import 'package:flutter/material.dart';

import 'api_service.dart';
import 'mundial_service.dart';
import 'nationality_flags.dart';
import 'player_career_sheet.dart';

String _cleanName(String name) {
  return String.fromCharCodes(name.runes.where((r) => r <= 0xFFFF)).trim();
}

Map<String, dynamic>? _statsMundialEnFila(Map<String, dynamic> row) {
  final list = row['statistics'] as List?;
  if (list == null) return null;
  for (final s in list) {
    if (s is Map<String, dynamic> && s['league']?['id'] == 1) return s;
  }
  if (list.isNotEmpty && list.first is Map<String, dynamic>) {
    return list.first as Map<String, dynamic>;
  }
  return null;
}

int _ordenPosicion(String? pos) {
  final p = (pos ?? 'M').toString().toUpperCase();
  if (p == 'G') return 0;
  if (p == 'D') return 1;
  if (p == 'M') return 2;
  if (p == 'F') return 3;
  return 4;
}

void showMundialSeleccionSheet(
  BuildContext context, {
  required int teamId,
  required String teamName,
  required String teamLogo,
  String? country,
}) {
  if (teamId <= 0) return;

  Future<Map<String, dynamic>> cargar() async {
    final r = await Future.wait<dynamic>([
      MundialService.getTeamInfo(teamId),
      MundialService.getTrophiesTeam(teamId),
      MundialService.getPlantelMundialCompleto(teamId),
      MundialService.getResumenHistoricoMundial(teamId),
    ]);
    return {
      'info': r[0],
      'trofeos': r[1],
      'plantel': r[2],
      'historico': r[3],
    };
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2A3B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx2, scrollController) => FutureBuilder<Map<String, dynamic>>(
        future: cargar(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
          }
          final data = snap.data ?? {};
          final info = data['info'] as Map<String, dynamic>?;
          final trofeos = List<Map<String, dynamic>>.from(data['trofeos'] as List? ?? []);
          final plantelRaw = List<Map<String, dynamic>>.from(data['plantel'] as List? ?? []);
          final hist = data['historico'] as Map<String, dynamic>? ?? {};

          final nombre = (info?['name'] as String?)?.trim().isNotEmpty == true
              ? info!['name'] as String
              : teamName;
          final logo = (info?['logo'] as String?)?.trim().isNotEmpty == true
              ? info!['logo'] as String
              : teamLogo;
          final pais = (info?['country'] as String?)?.trim().isNotEmpty == true
              ? info!['country'] as String
              : (country ?? '');
          final flag = flagEmojiFromCountryName(pais);

          final titulos = MundialService.titulosMundialDesdeTrofeos(trofeos);
          final nTitulos = titulos.length;

          plantelRaw.sort((a, b) {
            final sa = _statsMundialEnFila(a);
            final sb = _statsMundialEnFila(b);
            final oa = _ordenPosicion(sa?['games']?['position'] as String?);
            final ob = _ordenPosicion(sb?['games']?['position'] as String?);
            if (oa != ob) return oa.compareTo(ob);
            final na = (sa?['games']?['number'] as num?)?.toInt() ?? 999;
            final nb = (sb?['games']?['number'] as num?)?.toInt() ?? 999;
            return na.compareTo(nb);
          });

          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (logo.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(logo, width: 72, height: 72, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.flag, size: 56, color: Colors.white24)),
                    )
                  else
                    const Icon(Icons.flag, size: 56, color: Colors.white24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (flag.isNotEmpty) Text(flag, style: const TextStyle(fontSize: 22)),
                        Text(nombre,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        if (pais.isNotEmpty)
                          Text(pais, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _seccionTitulo('MUNDIAL — TÍTULOS Y PALMARÉS'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nTitulos > 0 ? '🏆 $nTitulos ${nTitulos == 1 ? 'título' : 'títulos'} de Copa del Mundo' : 'Sin títulos mundiales en trofeos API',
                      style: const TextStyle(color: Color(0xFF00C853), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    if (titulos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Años: ${titulos.join(', ')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Text('Mejor puesto (trofeos): ${hist['mejorPuestoTexto']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _seccionTitulo('DATOS HISTÓRICOS EN COPAS DEL MUNDO'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _filaHist('Partidos jugados (aprox., varias ediciones)', '${hist['partidosJugados'] ?? 0}'),
                    _filaHist('Finales disputadas (detectadas por ronda)', '${hist['finalesJugadas'] ?? 0}'),
                    const Divider(color: Colors.white10, height: 20),
                    const Text('Goleador histórico (suma tops API por edición)',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    _filaGoleador(
                      hist['goleadorHistoricoNombre'] as String? ?? '',
                      hist['goleadorHistoricoGoles'] as int? ?? 0,
                      hist['goleadorHistoricoFoto'] as String? ?? '',
                    ),
                    const SizedBox(height: 12),
                    const Text('Más presencias (suma tops API por edición)',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    _filaGoleador(
                      hist['masPresenciasNombre'] as String? ?? '',
                      hist['masPresenciasPartidos'] as int? ?? 0,
                      hist['masPresenciasFoto'] as String? ?? '',
                      esGoles: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _seccionTitulo('PLANTEL — MUNDIAL 2026'),
              const Text(
                'Número · foto · goles · rojas · rating (datos de la competición en la API)',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              if (plantelRaw.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Sin plantel con estadísticas aún.', style: TextStyle(color: Colors.white38)),
                )
              else
                ...plantelRaw.map((row) => _filaJugadorPlantel(
                      context,
                      row: row,
                      nationalTeamId: teamId,
                    )),
            ],
          );
        },
      ),
    ),
  );
}

Widget _seccionTitulo(String t) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(
        color: Color(0xFF00C853),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );
}

Widget _filaHist(String label, String valor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    ),
  );
}

Widget _filaGoleador(String nombre, int valor, String foto, {bool esGoles = true}) {
  if (nombre.isEmpty && valor == 0) {
    return const Text('—', style: TextStyle(color: Colors.white38));
  }
  return Row(
    children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white12,
        backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
        child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(_cleanName(nombre), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      Text(
        esGoles ? '⚽ $valor' : '👟 $valor PJ',
        style: const TextStyle(color: Color(0xFF00C853), fontSize: 14, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

Widget _filaJugadorPlantel(
  BuildContext context, {
  required Map<String, dynamic> row,
  required int nationalTeamId,
}) {
  final pl = row['player'] as Map<String, dynamic>? ?? {};
  final nombre = _cleanName(pl['name'] as String? ?? '');
  final foto = pl['photo'] as String? ?? '';
  final pid = pl['id'] as int? ?? 0;
  final st = _statsMundialEnFila(row);
  final games = st?['games'] as Map<String, dynamic>? ?? {};
  final goals = st?['goals'] as Map<String, dynamic>? ?? {};
  final cards = st?['cards'] as Map<String, dynamic>? ?? {};
  final dorsal = (games['number'] as num?)?.toInt() ?? 0;
  final pj = (games['appearences'] as num?)?.toInt() ?? (games['appearances'] as num?)?.toInt() ?? 0;
  final rating = double.tryParse(games['rating']?.toString() ?? '') ?? 0.0;
  final g = (goals['total'] as num?)?.toInt() ?? 0;
  final rojas = (cards['red'] as num?)?.toInt() ?? 0;
  final yred = (cards['yellowred'] as num?)?.toInt() ?? 0;
  final expulsiones = rojas + yred;

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: pid > 0
          ? () => showMundialSeleccionPlayerSheet(context, playerRow: row, nationalTeamId: nationalTeamId)
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                dorsal > 0 ? '$dorsal' : '—',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white12,
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              child: foto.isEmpty ? const Icon(Icons.person, size: 18, color: Colors.white38) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    'PJ $pj · ⚽ $g · 🟥 $expulsiones${rating > 0 ? ' · ★ ${rating.toStringAsFixed(1)}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    ),
  );
}

void showMundialSeleccionPlayerSheet(
  BuildContext context, {
  required Map<String, dynamic> playerRow,
  required int nationalTeamId,
}) {
  final pl = playerRow['player'] as Map<String, dynamic>? ?? {};
  final pid = pl['id'] as int? ?? 0;
  if (pid <= 0) return;

  final st = _statsMundialEnFila(playerRow);
  final games = st?['games'] as Map<String, dynamic>? ?? {};
  final goals = st?['goals'] as Map<String, dynamic>? ?? {};
  final cards = st?['cards'] as Map<String, dynamic>? ?? {};
  final nombre = _cleanName(pl['name'] as String? ?? '');
  final foto = pl['photo'] as String? ?? '';
  final pos = games['position'] as String? ?? '';
  final dorsal = (games['number'] as num?)?.toInt() ?? 0;
  final rating = double.tryParse(games['rating']?.toString() ?? '') ?? 0.0;
  final pj = (games['appearences'] as num?)?.toInt() ?? (games['appearances'] as num?)?.toInt() ?? 0;
  final g = (goals['total'] as num?)?.toInt() ?? 0;
  final asist = (goals['assists'] as num?)?.toInt() ?? 0;
  final amar = (cards['yellow'] as num?)?.toInt() ?? 0;
  final rojas = (cards['red'] as num?)?.toInt() ?? 0;
  final yred = (cards['yellowred'] as num?)?.toInt() ?? 0;

  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2A3B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        expand: false,
        builder: (ctx2, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white12,
                  backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                  child: foto.isEmpty ? const Icon(Icons.person, size: 40, color: Colors.white38) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (pos.isNotEmpty) Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chipStat('Dorsal', dorsal > 0 ? '#$dorsal' : '—'),
                          _chipStat('Rating', rating > 0 ? rating.toStringAsFixed(1) : '—'),
                          _chipStat('PJ Mundial', '$pj'),
                          _chipStat('Goles', '$g'),
                          _chipStat('Asist.', '$asist'),
                          _chipStat('Amarillas', '$amar'),
                          _chipStat('Rojas', '${rojas + yred}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text('CLUB ACTUAL (fuera de la selección)',
                style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 10),
            FutureBuilder<Map<String, dynamic>?>(
              future: ApiService.getClubActualExcluyendoEquipo(pid, nationalTeamId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)))),
                  );
                }
                final c = snap.data;
                if (c == null || (c['nombre'] as String? ?? '').isEmpty) {
                  return const Text('No disponible en API', style: TextStyle(color: Colors.white38, fontSize: 13));
                }
                final logo = c['logo'] as String? ?? '';
                return Row(
                  children: [
                    if (logo.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(logo, width: 44, height: 44, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, color: Colors.white24)),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['nombre'] as String, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          Text('Temp. ${c['temporada']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (nationalTeamId > 0)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final club = await ApiService.getClubActualExcluyendoEquipo(pid, nationalTeamId);
                    final clubId = club?['id'] as int? ?? 0;
                    if (!context.mounted || clubId <= 0) return;
                    await showPlayerCareerSheet(
                      context,
                      playerId: pid,
                      clubTeamId: clubId,
                      playerName: nombre,
                    );
                  },
                  icon: const Icon(Icons.person_search, color: Color(0xFF00C853), size: 18),
                  label: const Text('Ver carrera / trayectoria', style: TextStyle(color: Color(0xFF00C853))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00C853)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _chipStat(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
