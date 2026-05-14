import 'dart:async';

import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../match_follow_service.dart';
import '../player_career_sheet.dart';
import '../nationality_flags.dart';
import 'live_compare_bar.dart';
import 'live_fixture_bundle.dart';
import 'live_pitch_field.dart';
import 'live_section_mock.dart';

int _lineupTeamApiId(Map<String, dynamic> lu) {
  final t = lu['team'];
  if (t is! Map) return 0;
  final id = t['id'];
  if (id is int) return id;
  if (id is num) return id.toInt();
  return int.tryParse('$id') ?? 0;
}

String _lineupDisplayName(Map<String, dynamic> lu, String fallback) {
  final t = lu['team'];
  if (t is Map) {
    final n = t['name'];
    if (n is String && n.trim().isNotEmpty) return n.trim();
  }
  return fallback;
}

/// Tarjeta completa de un partido en vivo (datos enriquecidos + auto-refresh local).
class LiveMatchRichCard extends StatefulWidget {
  const LiveMatchRichCard({
    super.key,
    required this.partidoLista,
    required this.onTap,
    this.pollSeconds = 30,
    /// Datos locales de ejemplo: no llama a la API ni hace polling.
    this.previewMode = false,
  });

  final Map<String, dynamic> partidoLista;
  final VoidCallback onTap;
  final int pollSeconds;
  final bool previewMode;

  @override
  State<LiveMatchRichCard> createState() => _LiveMatchRichCardState();
}

class _LiveMatchRichCardState extends State<LiveMatchRichCard> with TickerProviderStateMixin {
  LiveFixtureBundle? _bundle;
  bool _loading = true;
  String? _err;
  Timer? _poll;
  int _lastGolesH = -1;
  int _lastGolesA = -1;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  int? get _fid => fixtureIdFromPartido(widget.partidoLista);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    if (widget.previewMode) {
      _bundle = LiveSectionMock.bundleEjemplo();
      _loading = false;
      _lastGolesH = 2;
      _lastGolesA = 1;
      return;
    }
    _load();
    _poll = Timer.periodic(Duration(seconds: widget.pollSeconds), (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(covariant LiveMatchRichCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.previewMode) return;
    if (fixtureIdFromPartido(oldWidget.partidoLista) != _fid) {
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (widget.previewMode) return;
    final id = _fid;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final b = await LiveFixtureBundle.fetch(id);
      if (!mounted) return;
      final merged = mergedPartidoSnapshot(widget.partidoLista, b.detalle);
      final gh = (merged['goals']?['home'] as num?)?.toInt() ?? int.tryParse('${merged['goals']?['home']}') ?? 0;
      final ga = (merged['goals']?['away'] as num?)?.toInt() ?? int.tryParse('${merged['goals']?['away']}') ?? 0;
      final changed = _lastGolesH >= 0 && (gh != _lastGolesH || ga != _lastGolesA);
      setState(() {
        _bundle = b;
        _loading = false;
        _err = null;
        _lastGolesH = gh;
        _lastGolesA = ga;
      });
      if (changed) {
        _pulseCtrl.forward(from: 0);
        _pulseCtrl.repeat(reverse: true);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) _pulseCtrl.stop();
          if (mounted) _pulseCtrl.reset();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = 'Error al cargar datos';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _fid;
    final merged = _bundle != null ? mergedPartidoSnapshot(widget.partidoLista, _bundle!.detalle) : widget.partidoLista;
    final teams = merged['teams'] as Map<String, dynamic>? ?? {};
    final goals = merged['goals'] as Map<String, dynamic>? ?? {};
    final fixture = merged['fixture'] as Map<String, dynamic>? ?? {};
    final status = fixture['status'] as Map<String, dynamic>? ?? {};
    final local = teams['home']?['name'] as String? ?? '';
    final visitante = teams['away']?['name'] as String? ?? '';
    final logoL = teams['home']?['logo'] as String? ?? '';
    final logoV = teams['away']?['logo'] as String? ?? '';
    final gh = (goals['home'] as num?)?.toInt() ?? int.tryParse('${goals['home']}') ?? 0;
    final ga = (goals['away'] as num?)?.toInt() ?? int.tryParse('${goals['away']}') ?? 0;
    final elapsed = (status['elapsed'] as num?)?.toInt() ?? int.tryParse('${status['elapsed']}') ?? 0;
    final short = status['short'] as String? ?? '';
    final arbitroFull = fixture['referee'] as String? ?? '';
    final arbitro = arbitroFull.isNotEmpty ? arbitroFull.split(',').first.trim() : '';
    final venue = fixture['venue'] as Map<String, dynamic>?;
    final estadio = venue?['name'] as String? ?? '';
    final ciudad = venue?['city'] as String? ?? '';

    final colorH = teamPrimaryColor(teams['home'] as Map<String, dynamic>?) ?? const Color(0xFF00C853);
    final colorA = teamPrimaryColor(teams['away'] as Map<String, dynamic>?) ?? const Color(0xFF1E88E5);

    final statMaps = LiveFixtureBundle.statMapsFromResponse(_bundle?.statisticsRaw);
    final sh = statMaps['home']!;
    final sa = statMaps['away']!;

    final events = _bundle?.events ?? const <Map<String, dynamic>>[];
    final lineups = _bundle?.lineups ?? const <Map<String, dynamic>>[];
    final ratings = ratingsPorJugadorId(_bundle?.players ?? const []);

    final scoreMap = merged['score'] as Map<String, dynamic>?;
    final per = golesPorPeriodoDesdeScore(scoreMap);

    final prog = progresoPartido(short, elapsed);
    final estadoTxt = estadoPartidoCortoEs(short);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0A1624),
            const Color(0xFF152535),
            colorH.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorH.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerBar(short, elapsed, estadoTxt, prog, colorH, fixtureId: id, previewMode: widget.previewMode),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _teamBlock(logoL, local, colorH, alignEnd: false)),
                    Expanded(
                      flex: 2,
                      child: _scoreBlock(gh, ga, colorH, colorA),
                    ),
                    Expanded(child: _teamBlock(logoV, visitante, colorA, alignEnd: true)),
                  ],
                ),
              ),
              if (estadio.isNotEmpty || arbitro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      if (estadio.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stadium, size: 14, color: Colors.white.withValues(alpha: 0.45)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                ciudad.isNotEmpty ? '$estadio · $ciudad' : estadio,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      if (arbitro.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sports, size: 14, color: Colors.white.withValues(alpha: 0.45)),
                            const SizedBox(width: 6),
                            Flexible(child: Text('Árbitro: $arbitro', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              if (_loading && _bundle == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF00C853), strokeWidth: 2)),
                )
              else ...[
                if (_err != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                _sectionTitle('Marcador por tiempo'),
                _scorePeriodRow('1.er tiempo', per['1tL'], per['1tV'], always: true),
                _scorePeriodRow('2.do tiempo', per['2tL'], per['2tV'], always: true),
                if ((per['etL'] ?? 0) + (per['etV'] ?? 0) > 0 || short == 'ET' || short == 'BT' || short == 'PEN')
                  _scorePeriodRow('Prórroga', per['etL'], per['etV'], always: short == 'ET' || short == 'BT' || short == 'PEN'),
                if ((per['penL'] ?? 0) + (per['penV'] ?? 0) > 0 || short == 'PEN')
                  _scorePeriodRow('Penales', per['penL'], per['penV'], always: short == 'PEN'),
                const SizedBox(height: 6),
                _sectionTitle('Últimos eventos'),
                _eventsList(events, teams),
                const SizedBox(height: 6),
                _sectionTitle('Estadísticas en vivo'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(
                    children: [
                      LiveCompareBar(label: 'Posesión', homeValue: sh['Ball Possession'], awayValue: sa['Ball Possession'], homeColor: colorH, awayColor: colorA, isPercent: true),
                      LiveCompareBar(label: 'Tiros al arco', homeValue: sh['Shots on Goal'], awayValue: sa['Shots on Goal'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Tiros afuera', homeValue: sh['Shots off Goal'], awayValue: sa['Shots off Goal'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Tiros totales', homeValue: sh['Total Shots'], awayValue: sa['Total Shots'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Tiros bloqueados', homeValue: sh['Blocked Shots'], awayValue: sa['Blocked Shots'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Córners', homeValue: sh['Corner Kicks'], awayValue: sa['Corner Kicks'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Faltas', homeValue: sh['Fouls'], awayValue: sa['Fouls'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Fuera de juego', homeValue: sh['Offsides'], awayValue: sa['Offsides'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Tarjetas amarillas', homeValue: sh['Yellow Cards'], awayValue: sa['Yellow Cards'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Tarjetas rojas', homeValue: sh['Red Cards'], awayValue: sa['Red Cards'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(label: 'Pases totales', homeValue: sh['Total passes'], awayValue: sa['Total passes'], homeColor: colorH, awayColor: colorA),
                      LiveCompareBar(
                        label: 'Precisión pases',
                        homeValue: sh['Passes %'] ?? sh['Passes accurate'],
                        awayValue: sa['Passes %'] ?? sa['Passes accurate'],
                        homeColor: colorH,
                        awayColor: colorA,
                        isPercent: false,
                      ),
                      LiveCompareBar(label: 'Paradas (arquero)', homeValue: sh['Goalkeeper Saves'], awayValue: sa['Goalkeeper Saves'], homeColor: colorH, awayColor: colorA),
                    ],
                  ),
                ),
                if (_bundle != null && !(_bundle!.statisticsRaw?['response'] is List && (_bundle!.statisticsRaw!['response'] as List).length >= 2))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'Estadísticas en vivo: la API aún no las publica para este partido.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (lineups.length >= 2) ...[
                  const SizedBox(height: 4),
                  _sectionTitle('Formación y plantel'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LivePitchField(
                            lineupTeam: lineups[0],
                            accent: colorH,
                            title: _lineupDisplayName(lineups[0], local),
                            teamId: _lineupTeamApiId(lineups[0]),
                            ratingsByPlayerId: ratings,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LivePitchField(
                            lineupTeam: lineups[1],
                            accent: colorA,
                            title: _lineupDisplayName(lineups[1], visitante),
                            teamId: _lineupTeamApiId(lineups[1]),
                            ratingsByPlayerId: ratings,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _lineupsBench(context, lineups[0], colorH, ratings),
                  _lineupsBench(context, lineups[1], colorA, ratings),
                ],
              ],
              if (_bundle?.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Text(
                    widget.previewMode
                        ? 'Vista previa con datos de ejemplo · no es un partido real'
                        : 'Datos partido #${id ?? '—'} · ${_fmtReloj(_bundle!.fetchedAt!)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtReloj(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'hace ${d.inSeconds}s';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _headerBar(String short, int elapsed, String estadoTxt, double prog, Color accent, {int? fixtureId, bool previewMode = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: short == 'HT' ? Colors.orange : const Color(0xFF00C853),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: (short == 'HT' ? Colors.orange : const Color(0xFF00C853)).withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                short == 'HT' ? 'ENTRETIEMPO' : (elapsed > 0 ? "$elapsed'" : estadoTxt.toUpperCase()),
                style: TextStyle(
                  color: short == 'HT' ? Colors.orange : const Color(0xFF00C853),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(estadoTxt.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, fontWeight: FontWeight.w600)),
              if (fixtureId != null && fixtureId > 0 && !previewMode) MatchFollowToggle(fixtureId: fixtureId),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prog.clamp(0.02, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(accent.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamBlock(String logo, String name, Color c, {required bool alignEnd}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (logo.isNotEmpty)
          DecodedNetworkImage(logo, width: 56, height: 56, errorBuilder: (_, _, _) => Icon(Icons.shield, color: c.withValues(alpha: 0.5), size: 48))
        else
          Icon(Icons.shield, color: c.withValues(alpha: 0.5), size: 48),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, height: 1.15),
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _scoreBlock(int gh, int ga, Color cH, Color cA) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseCtrl.isAnimating ? _pulse.value : 1.0,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF050d18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$gh', style: TextStyle(color: cH, fontWeight: FontWeight.w900, fontSize: 36, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('-', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 28, fontWeight: FontWeight.w300)),
            ),
            Text('$ga', style: TextStyle(color: cA, fontWeight: FontWeight.w900, fontSize: 36, height: 1)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.4),
      ),
    );
  }

  Widget _scorePeriodRow(String label, int? h, int? v, {bool always = false}) {
    if (!always && h == null && v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12))),
          Text('${h ?? '—'}  -  ${v ?? '—'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _eventsList(List<Map<String, dynamic>> eventos, Map<String, dynamic> teams) {
    if (eventos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Sin eventos todavía', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
      );
    }
    final homeId = teams['home']?['id'];
    final hid = homeId is int ? homeId : (homeId is num ? homeId.toInt() : int.tryParse('$homeId'));

    final sorted = List<Map<String, dynamic>>.from(eventos);
    sorted.sort((a, b) {
      int t(Map<String, dynamic> e) {
        final el = e['time']?['elapsed'];
        final ex = e['time']?['extra'];
        final e1 = el is int ? el : (el is num ? el.toInt() : int.tryParse('$el') ?? 0);
        final e2 = ex is int ? ex : (ex is num ? ex.toInt() : int.tryParse('$ex') ?? 0);
        return e1 * 100 + e2;
      }

      return t(b).compareTo(t(a));
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: sorted.map((e) {
          final tipo = e['type'] as String? ?? '';
          final detalle = e['detail'] as String? ?? '';
          final min = e['time']?['elapsed']?.toString() ?? '';
          final extra = e['time']?['extra'];
          final minStr = extra != null ? '$min+$extra\'' : '$min\'';
          final jugador = e['player']?['name'] as String? ?? '';
          final asist = e['assist']?['name'] as String? ?? '';
          final tid = e['team']?['id'];
          final eid = tid is int ? tid : (tid is num ? tid.toInt() : int.tryParse('$tid'));
          final esLocal = eid != null && hid != null && eid == hid;

          String icon = '•';
          Color col = Colors.white54;
          String texto = jugador;
          if (tipo == 'Goal') {
            icon = '⚽';
            col = const Color(0xFF00C853);
            if (detalle == 'Own Goal') {
              texto = 'Gol en contra: $jugador';
            } else if (detalle == 'Penalty') {
              texto = 'Penal: $jugador';
            } else {
              texto = 'Gol: $jugador';
            }
          } else if (tipo == 'Card') {
            icon = detalle == 'Yellow Card' ? '🟨' : '🟥';
            col = detalle == 'Yellow Card' ? const Color(0xFFFFD54F) : const Color(0xFFFF5252);
            texto = detalle == 'Yellow Card' ? 'Amarilla: $jugador' : 'Roja: $jugador';
          } else if (tipo == 'subst') {
            icon = '🔄';
            col = Colors.lightBlueAccent;
            texto = 'Cambio: sale $jugador · entra $asist';
          } else if (tipo == 'Var') {
            icon = '📺';
            col = Colors.blue.shade200;
            texto = 'VAR: $detalle';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: col.withValues(alpha: 0.7), width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esLocal) ...[
                  Text(icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(minStr, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(texto, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2)),
                        if (tipo == 'Goal' && asist.isNotEmpty && detalle != 'Own Goal')
                          Text('Asistencia: $asist', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                      ],
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(texto, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2), textAlign: TextAlign.right),
                        if (tipo == 'Goal' && asist.isNotEmpty && detalle != 'Own Goal')
                          Text('Asistencia: $asist', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11), textAlign: TextAlign.right),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(minStr, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(icon, style: const TextStyle(fontSize: 16)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _lineupsBench(BuildContext context, Map<String, dynamic> team, Color accent, Map<int, double> ratings) {
    final nombre = team['team']?['name'] as String? ?? '';
    final form = team['formation'] as String? ?? '';
    final xi = List<Map<String, dynamic>>.from(team['startXI'] ?? []);
    final bench = List<Map<String, dynamic>>.from(team['substitutes'] ?? []);
    final clubId = (team['team']?['id'] as num?)?.toInt() ?? 0;

    Widget rowPlayer(Map<String, dynamic> plMap, {bool strikethrough = false}) {
      final pl = plMap['player'] as Map<String, dynamic>? ?? {};
      final dorsal = (pl['number'] as num?)?.toInt() ?? int.tryParse('${pl['number']}') ?? 0;
      final name = liveCleanPlayerName(pl['name'] as String? ?? '');
      final pid = (pl['id'] as num?)?.toInt() ?? int.tryParse('${pl['id']}') ?? 0;
      final nat = (pl['nationality'] as String?)?.trim() ?? '';
      final flag = flagEmojiFromCountryName(nat);
      final rt = ratings[pid];
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: clubId > 0 && pid > 0 ? () => showPlayerCareerSheet(context, playerId: pid, clubTeamId: clubId, playerName: name) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Container(
                  width: 24,
                  alignment: Alignment.center,
                  child: Text('$dorsal', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                if (flag.isNotEmpty) Text(flag, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: strikethrough ? Colors.white38 : Colors.white,
                      fontSize: 12,
                      decoration: strikethrough ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (rt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rt >= 7.5 ? Colors.green.withValues(alpha: 0.25) : rt >= 6.5 ? Colors.orange.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(rt.toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(nombre.toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11))),
                if (form.isNotEmpty) Text(form, style: TextStyle(color: accent.withValues(alpha: 0.65), fontSize: 11)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Titulares', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
            ...xi.map((s) => rowPlayer(s)),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Suplentes', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
              ...bench.map((s) => rowPlayer(s)),
            ],
          ],
        ),
      ),
    );
  }
}
