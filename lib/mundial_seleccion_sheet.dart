import 'package:flutter/material.dart';

import 'api_service.dart';
import 'mundial_service.dart';
import 'nationality_flags.dart';
import 'player_career_sheet.dart';

String _cleanName(String name) {
  return String.fromCharCodes(name.runes.where((r) => r <= 0xFFFF)).trim();
}

Map<String, dynamic> _playerMapFromRow(Map<String, dynamic> row) {
  final raw = row['player'];
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

int _playerIdFromMap(Map<String, dynamic> pl) {
  return (pl['id'] as num?)?.toInt() ?? int.tryParse('${pl['id']}') ?? 0;
}

int _intFromStat(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
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
          final plantelRaw = <Map<String, dynamic>>[];
          final pr = data['plantel'];
          if (pr is List) {
            for (final e in pr) {
              if (e is Map<String, dynamic>) {
                plantelRaw.add(e);
              } else if (e is Map) {
                plantelRaw.add(Map<String, dynamic>.from(e));
              }
            }
          }
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
            final sa = MundialService.statisticsMundialLiga1(a, priorizarSeleccionId: teamId);
            final sb = MundialService.statisticsMundialLiga1(b, priorizarSeleccionId: teamId);
            final ga = MundialService.childMap(sa?['games']);
            final gb = MundialService.childMap(sb?['games']);
            final oa = _ordenPosicion(ga['position'] as String?);
            final ob = _ordenPosicion(gb['position'] as String?);
            if (oa != ob) return oa.compareTo(ob);
            final na = (ga['number'] as num?)?.toInt() ?? 999;
            final nb = (gb['number'] as num?)?.toInt() ?? 999;
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
                'PJ y goles con la selección en esta competición · expulsiones · club actual (fuera de la selección)',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              if (plantelRaw.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sin plantel en la API para esta selección (revisá conexión o probá más tarde).',
                    style: TextStyle(color: Colors.white38),
                  ),
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

Widget _chipPlantelStat(String label, String valor, {Color accent = const Color(0xFF00C853)}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: 0.35)),
    ),
    child: Text(
      '$label $valor',
      style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

/// Club actual del jugador fuera de la selección (API + cache). Reutilizable en formaciones del partido.
Widget mundialClubActualLine(int playerId, int nationalTeamId) {
  if (playerId <= 0) {
    return const SizedBox.shrink();
  }
  return FutureBuilder<Map<String, dynamic>?>(
    future: ApiService.getClubActualExcluyendoEquipoCached(playerId, nationalTeamId),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Club: cargando…',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
          ),
        );
      }
      final c = snap.data;
      final nombre = c?['nombre'] as String? ?? '';
      if (nombre.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Club: no disponible en API',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 11),
          ),
        );
      }
      final logo = c?['logo'] as String? ?? '';
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (logo.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(logo, width: 22, height: 22, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF90CAF9))),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF90CAF9)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Club', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
                  Text(
                    nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

Widget _filaJugadorPlantel(
  BuildContext context, {
  required Map<String, dynamic> row,
  required int nationalTeamId,
}) {
  final pl = _playerMapFromRow(row);
  final nombre = _cleanName(pl['name'] as String? ?? '');
  final foto = pl['photo'] as String? ?? '';
  final pid = _playerIdFromMap(pl);
  final nacionalidad = (pl['nationality'] as String?)?.trim() ?? '';
  final flagJug = flagEmojiFromCountryName(nacionalidad);
  final st = MundialService.statisticsMundialLiga1(row, priorizarSeleccionId: nationalTeamId);
  final games = MundialService.childMap(st?['games']);
  final goals = MundialService.childMap(st?['goals']);
  final cards = MundialService.childMap(st?['cards']);
  final dorsal = _intFromStat(games['number']) != 0
      ? _intFromStat(games['number'])
      : _intFromStat(pl['number']);
  final pjA = _intFromStat(games['appearences']);
  final pjB = _intFromStat(games['appearances']);
  final pj = pjA != 0 ? pjA : pjB;
  final rating = double.tryParse(games['rating']?.toString() ?? '') ?? 0.0;
  final g = _intFromStat(goals['total']);
  final rojas = _intFromStat(cards['red']);
  final yred = _intFromStat(cards['yellowred']);
  final expulsiones = rojas + yred;

  final pos = (games['position'] as String? ?? pl['position']?.toString() ?? '').trim();

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
          crossAxisAlignment: CrossAxisAlignment.start,
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
            if (flagJug.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(flagJug, style: const TextStyle(fontSize: 18, height: 1)),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (pos.isNotEmpty)
                    Text(
                      pos,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'En este Mundial: $pj PJ · $g goles · $expulsiones expulsiones',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chipPlantelStat('PJ selección', '$pj'),
                      _chipPlantelStat('Goles', '$g', accent: const Color(0xFFFFD700)),
                      _chipPlantelStat('Expulsiones', '$expulsiones', accent: const Color(0xFFFF5252)),
                      if (rating > 0)
                        _chipPlantelStat('Rating', rating.toStringAsFixed(1), accent: Colors.white70),
                    ],
                  ),
                  mundialClubActualLine(pid, nationalTeamId),
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
  final pl = _playerMapFromRow(playerRow);
  final pid = _playerIdFromMap(pl);
  if (pid <= 0) return;

  final st = MundialService.statisticsMundialLiga1(playerRow, priorizarSeleccionId: nationalTeamId);
  final games = MundialService.childMap(st?['games']);
  final goals = MundialService.childMap(st?['goals']);
  final cards = MundialService.childMap(st?['cards']);
  final nombre = _cleanName(pl['name'] as String? ?? '');
  final foto = pl['photo'] as String? ?? '';
  final pos = games['position'] as String? ?? '';
  final dorsal = _intFromStat(games['number']);
  final pjA = _intFromStat(games['appearences']);
  final pjB = _intFromStat(games['appearances']);
  final pj = pjA != 0 ? pjA : pjB;
  final rating = double.tryParse(games['rating']?.toString() ?? '') ?? 0.0;
  final g = _intFromStat(goals['total']);
  final asist = _intFromStat(goals['assists']);
  final amar = _intFromStat(cards['yellow']);
  final rojas = _intFromStat(cards['red']);
  final yred = _intFromStat(cards['yellowred']);

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
              future: ApiService.getClubActualExcluyendoEquipoCached(pid, nationalTeamId),
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
                    final club = await ApiService.getClubActualExcluyendoEquipoCached(pid, nationalTeamId);
                    final clubId = (club?['id'] as num?)?.toInt() ?? int.tryParse('${club?['id']}') ?? 0;
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
