import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'match_follow_service.dart';
import 'copa_service.dart';
import 'nationality_flags.dart';
import 'penales_shootout_helper.dart';
import 'player_career_sheet.dart';
import 'image_decode_helper.dart';
import 'widgets/hoy_match_card.dart';
import 'app_icons.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

typedef OnTapPartido = void Function(
  BuildContext context,
  String local,
  String visitante,
  String resultado,
  bool jugado, {
  int? fixtureId,
  int? homeId,
  int? awayId,
  String? fechaPartido,
  bool isLive,
  String minuto,
  /// API-Sports `league.id` del listado (p. ej. 130 Copa Argentina).
  int? sourceLeagueId,
  /// Objeto completo del fixture del listado (fusionar estadio/árbitro si el GET por id viene vacío).
  Map<String, dynamic>? partidoLista,
});

class CopaScreen extends StatefulWidget {
  final int leagueId;
  final String nombreCopa;
  /// Si se omite, se usa [titleIcon] en el AppBar.
  final String emoji;
  final PhosphorIconData? titleIcon;
  final OnTapPartido onTapPartido;

  /// Cuando la pantalla está embebida en el home (no hay ruta encima), usar esto
  /// en lugar de [Navigator.pop] para no vaciar el stack del [MaterialApp].
  final VoidCallback? onBack;

  const CopaScreen({
    Key? key,
    required this.leagueId,
    required this.nombreCopa,
    this.emoji = '',
    this.titleIcon,
    required this.onTapPartido,
    this.onBack,
  }) : super(key: key);

  @override
  State<CopaScreen> createState() => _CopaScreenState();
}

class _CopaScreenState extends State<CopaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool get _esCopaArgentina =>
      widget.leagueId == CopaService.leagueCopaArgentina;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.index = 1; // arranca en FIXTURE
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF0D1B2A),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0D1B2A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          if (widget.onBack != null) {
            widget.onBack!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.titleIcon != null) ...[
            AppIcons.phosphor(widget.titleIcon!, size: 22, color: AppIcons.accent),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.nombreCopa,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
    body: Column(
      children: [
        Container(
          color: const Color(0xFF0D1B2A),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: const Color(0xFF00C853),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: [
              const Tab(text: 'HOY'),
              const Tab(text: 'FIXTURE'),
              Tab(text: _esCopaArgentina ? 'PRÓX. RONDA' : 'GRUPOS'),
              const Tab(text: 'GOLEADORES'),
              const Tab(text: 'PLANTELES'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TabHoy(leagueId: widget.leagueId, onTapPartido: widget.onTapPartido),
              _TabFixture(leagueId: widget.leagueId, onTapPartido: widget.onTapPartido),
              if (_esCopaArgentina)
                _TabProximaRonda(leagueId: widget.leagueId, onTapPartido: widget.onTapPartido)
              else
                _TabGrupos(leagueId: widget.leagueId),
              _TabGoleadores(leagueId: widget.leagueId),
              _TabPlanteles(leagueId: widget.leagueId),
            ],
          ),
        ),
      ],
    ),
  );
}
}

// ─── HELPER CARD PARTIDO (layout vertical HOY) ───────────────
Widget buildCardPartido(Map<String, dynamic> partido, BuildContext context, OnTapPartido onTap, int leagueId) {
  final teams = partido['teams'] as Map<String, dynamic>?;
  final fixture = partido['fixture'] as Map<String, dynamic>?;
  final goals = partido['goals'] as Map<String, dynamic>?;
  if (teams == null || fixture == null) return const SizedBox.shrink();

  final home = teams['home']?['name']?.toString() ?? '';
  final away = teams['away']?['name']?.toString() ?? '';
  final homeId = teams['home']?['id'] as int?;
  final awayId = teams['away']?['id'] as int?;
  final fixtureId = fixture['id'] as int?;
  final fechaPartido = fixture['date'] as String?;
  final status = fixture['status']?['short']?.toString() ?? '';
  final hScore = goals?['home']?.toString() ?? '-';
  final aScore = goals?['away']?.toString() ?? '-';
  final marcadorConPen = '$hScore - $aScore${PenalesShootoutHelper.sufijoMarcadorParentesis(partido) ?? ''}';
  final isLive = status == '1H' || status == '2H' || status == 'HT' || status == 'ET' || status.contains("'");
  final isFinished = status == 'FT' || status == 'AET' || status == 'PEN';

  return HoyMatchCard(
    partido: partido,
    trailing: !kIsWeb && fixtureId != null ? MatchFollowToggle(fixtureId: fixtureId) : null,
    onTap: () => onTap(
      context,
      home,
      away,
      marcadorConPen,
      isFinished,
      fixtureId: fixtureId,
      homeId: homeId,
      awayId: awayId,
      fechaPartido: fechaPartido,
      isLive: isLive,
      minuto: isLive ? (fixture['status']?['elapsed']?.toString() ?? status) : '',
      sourceLeagueId: leagueId,
      partidoLista: partido,
    ),
  );
}

// ─── TAB HOY ────────────────────────────────────────────────
class _TabHoy extends StatelessWidget {
  final int leagueId;
  final OnTapPartido onTapPartido;
  const _TabHoy({required this.leagueId, required this.onTapPartido});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CopaService.getPartidosHoy(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final partidos = snapshot.data ?? [];
        if (partidos.isEmpty) {
          final msg = leagueId == CopaService.leagueCopaArgentina
              ? 'No hay partidos de Copa Argentina en los próximos 7 días'
              : 'No hay partidos en los próximos 7 días';
          return Center(
            child: Text(msg, style: const TextStyle(color: Colors.white54)),
          );
        }
        final porDia = ApiService.agruparPartidosPorDiaLocal(partidos);
        final children = <Widget>[];
        for (final entry in porDia.entries) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                ApiService.etiquetaDiaAgenda(entry.key),
                style: const TextStyle(
                  color: Color(0xFF00E650),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          );
          for (final p in entry.value) {
            children.add(buildCardPartido(p, context, onTapPartido, leagueId));
          }
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: children,
        );
      },
    );
  }
}

// ─── TAB FIXTURE ────────────────────────────────────────────
class _TabFixture extends StatefulWidget {
  final int leagueId;
  final OnTapPartido onTapPartido;
  const _TabFixture({required this.leagueId, required this.onTapPartido});

  @override
  State<_TabFixture> createState() => _TabFixtureState();
}

class _TabFixtureState extends State<_TabFixture> {
  String? _roundSeleccionado;

  @override
  void didUpdateWidget(covariant _TabFixture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _roundSeleccionado = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CopaService.getFixture(widget.leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final partidos = snapshot.data ?? [];
        if (partidos.isEmpty) {
          return const Center(child: Text('Sin datos de fixture', style: TextStyle(color: Colors.white54)));
        }

        final Map<String, List<Map<String, dynamic>>> porRonda = {};
        for (final p in partidos) {
          final ronda = p['league']?['round'] as String? ?? 'Sin ronda';
          porRonda.putIfAbsent(ronda, () => []).add(p);
        }
        DateTime _firstKickoff(List<Map<String, dynamic>> list) {
          var best = DateTime(2100);
          for (final p in list) {
            final d = DateTime.tryParse(
                    p['fixture']?['date']?.toString() ?? '') ??
                DateTime(2100);
            if (d.isBefore(best)) best = d;
          }
          return best;
        }
        final rondas = porRonda.keys.toList()
          ..sort((a, b) =>
              _firstKickoff(porRonda[a]!).compareTo(_firstKickoff(porRonda[b]!)));
        _roundSeleccionado ??= rondas.first;

        return Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: rondas.length,
                itemBuilder: (context, i) {
                  final r = rondas[i];
                  final sel = r == _roundSeleccionado;
                  return GestureDetector(
                    onTap: () => setState(() => _roundSeleccionado = r),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF00C853) : const Color(0xFF1B2A3B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(r,
                            style: TextStyle(
                                color: sel ? Colors.black : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: (porRonda[_roundSeleccionado] ?? [])
                    .map((p) => buildCardPartido(p, context, widget.onTapPartido, widget.leagueId))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── TAB PRÓXIMA RONDA (Copa Argentina y copas sin fase de grupos) ──
class _TabProximaRonda extends StatelessWidget {
  final int leagueId;
  final OnTapPartido onTapPartido;
  const _TabProximaRonda({required this.leagueId, required this.onTapPartido});

  static String? _statusShort(Map<String, dynamic>? p) {
    final st = p?['fixture']?['status'];
    if (st is! Map) return null;
    final raw = st['short'];
    if (raw is String) return raw;
    if (raw != null) return raw.toString();
    return null;
  }

  /// Próximos o en curso (la API a veces deja partidos vivos fuera de NS).
  static bool _esPendienteOEnVivo(String? status) {
    if (status == null || status.isEmpty) return false;
    return status == 'NS' ||
        status == 'TBD' ||
        status == 'PST' ||
        status == '1H' ||
        status == 'HT' ||
        status == '2H' ||
        status == 'LIVE' ||
        status == 'ET' ||
        status == 'BT' ||
        status == 'INT' ||
        status == 'P';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CopaService.getFixture(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudo cargar el fixture.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          );
        }
        final partidos = snapshot.data ?? [];
        if (partidos.isEmpty) {
          return const Center(child: Text('Sin datos de fixture', style: TextStyle(color: Colors.white54)));
        }
        final upcoming = partidos.where((p) {
          final s = _statusShort(p);
          return _esPendienteOEnVivo(s);
        }).toList();
        upcoming.sort((a, b) {
          final da = DateTime.tryParse(a['fixture']?['date']?.toString() ?? '') ??
              DateTime(2100);
          final db = DateTime.tryParse(b['fixture']?['date']?.toString() ?? '') ??
              DateTime(2100);
          return da.compareTo(db);
        });
        if (upcoming.isEmpty) {
          return const Center(
            child: Text('No hay próxima ronda programada (o ya están todos jugados)',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
          );
        }

        final children = <Widget>[];
        String? rondaActual;
        for (final p in upcoming) {
          final ronda = p['league']?['round'] as String? ?? 'Ronda';
          if (ronda != rondaActual) {
            rondaActual = ronda;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Icon(Icons.flag_outlined, color: Color(0xFF00C853), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ronda,
                      style: const TextStyle(
                          color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ]),
            ));
          }
          children.add(buildCardPartido(p, context, onTapPartido, leagueId));
        }

        return ListView(padding: const EdgeInsets.only(bottom: 16), children: children);
      },
    );
  }
}

// ─── TAB GRUPOS ─────────────────────────────────────────────
class _TabGrupos extends StatelessWidget {
  final int leagueId;
  const _TabGrupos({required this.leagueId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CopaService.getGrupos(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final grupos = snapshot.data ?? [];
        if (grupos.isEmpty) {
          return const Center(child: Text('Sin datos de grupos', style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: grupos.length,
          itemBuilder: (context, i) {
            final grupo = grupos[i]['grupo'] as List;
            if (grupo.isEmpty) return const SizedBox.shrink();
            final grupoNombre = grupo[0]['group'] as String? ?? 'Grupo';
            return _cardGrupo(grupoNombre, grupo);
          },
        );
      },
    );
  }

  Widget _cardGrupo(String nombre, List grupo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(nombre, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: const [
              Expanded(child: Text('Equipo', style: TextStyle(color: Colors.white38, fontSize: 11))),
              SizedBox(width: 24, child: Text('PJ', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('G', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('E', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('P', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 30, child: Text('Pts', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ]),
          ),
          const Divider(color: Colors.white12),
          ...grupo.asMap().entries.map((entry) {
            final pos = entry.key;
            final t = entry.value;
            final team = t['team'];
            final all = t['all'];
            final pts = t['points'] as int? ?? 0;
            final clasificado = pos < 2;
            return Container(
              color: clasificado ? const Color(0xFF00C853).withValues(alpha: 0.05) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Container(
                  width: 20, height: 20,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: clasificado ? const Color(0xFF00C853).withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(child: Text('${pos + 1}',
                      style: TextStyle(color: clasificado ? const Color(0xFF00C853) : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                ),
                Expanded(child: Text(team['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 24, child: Text('${all['played']}', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
                SizedBox(width: 24, child: Text('${all['win']}', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
                SizedBox(width: 24, child: Text('${all['draw']}', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
                SizedBox(width: 24, child: Text('${all['lose']}', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
                SizedBox(width: 30, child: Text('$pts', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ]),
            );
          }).toList(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── TAB GOLEADORES ─────────────────────────────────────────
class _TabGoleadores extends StatelessWidget {
  final int leagueId;
  const _TabGoleadores({required this.leagueId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CopaService.getGoleadores(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final players = snapshot.data ?? [];
        if (players.isEmpty) {
          return const Center(child: Text('Sin datos de goleadores', style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: players.length,
          itemBuilder: (context, i) => _cardGoleador(players[i], leagueId, i + 1),
        );
      },
    );
  }

  Widget _cardGoleador(Map<String, dynamic> data, int leagueId, int pos) {
    final player = data['player'] as Map<String, dynamic>?;
    if (player == null) return const SizedBox.shrink();
    final stats = CopaService.statsForLeague(data, leagueId);
    if (stats == null) return const SizedBox.shrink();
    final goals = (stats['goals']?['total'] as num?)?.toInt() ?? 0;
    final assists = (stats['goals']?['assists'] as num?)?.toInt() ?? 0;
    final team = stats['team']?['name'] as String? ?? '';
    final nombre = player['name'] as String? ?? '';
    final foto = player['photo'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
        border: pos <= 3 ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3), width: 1) : null,
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$pos',
            style: TextStyle(color: pos <= 3 ? const Color(0xFF00C853) : Colors.white38, fontWeight: FontWeight.bold, fontSize: 14))),
        CircleAvatar(
          radius: 18,
          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
          backgroundColor: Colors.white12,
          child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 18) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
          Text(team, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Column(children: [
          Text('$goals', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const Text('goles', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
        const SizedBox(width: 16),
        Column(children: [
          Text('$assists', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 18)),
          const Text('asis', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }
}

// ─── TAB PLANTELES ──────────────────────────────────────────
class _TabPlanteles extends StatefulWidget {
  final int leagueId;
  const _TabPlanteles({required this.leagueId});

  @override
  State<_TabPlanteles> createState() => _TabPlantelesState();
}

class _TabPlantelesState extends State<_TabPlanteles> {
  Map<String, dynamic>? _equipoSeleccionado;
  List<Map<String, dynamic>> _equipos = [];
  bool _cargandoEquipos = true;
  List<Map<String, dynamic>> _jugadores = [];
  bool _cargandoJugadores = false;
  int _paginaActual = 1;
  bool _hayMasPaginas = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargarEquipos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_cargandoJugadores && _hayMasPaginas) {
      _cargarMasJugadores();
    }
  }

  Future<void> _cargarEquipos() async {
    final equipos = await CopaService.getEquiposArgentinos(widget.leagueId);
    setState(() { _equipos = equipos; _cargandoEquipos = false; });
  }

  Future<void> _seleccionarEquipo(Map<String, dynamic> team) async {
    setState(() { _equipoSeleccionado = team; _jugadores = []; _paginaActual = 1; _hayMasPaginas = true; });
    await _cargarMasJugadores();
  }

  Future<void> _cargarMasJugadores() async {
    if (_cargandoJugadores || !_hayMasPaginas) return;
    setState(() => _cargandoJugadores = true);
    final teamId = _equipoSeleccionado!['id'] as int;
    final nuevos = await CopaService.getPlantelStats(widget.leagueId, teamId, pagina: _paginaActual);
    setState(() {
      _jugadores.addAll(nuevos);
      _cargandoJugadores = false;
      if (nuevos.length < 20) { _hayMasPaginas = false; } else { _paginaActual++; }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoEquipos) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    }
    if (_equipos.isEmpty) {
      return const Center(child: Text('Sin equipos argentinos', style: TextStyle(color: Colors.white54)));
    }

    if (_equipoSeleccionado == null) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _equipos.length,
        itemBuilder: (context, i) {
          final team = _equipos[i]['team'];
          final logo = team['logo'] as String? ?? '';
          final nombre = team['name'] as String? ?? '';
          return GestureDetector(
            onTap: () => _seleccionarEquipo(team),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                logo.isNotEmpty
                    ? DecodedNetworkImage(logo, width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, color: Colors.white38))
                    : const Icon(Icons.sports_soccer, color: Colors.white38),
                const SizedBox(width: 12),
                Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ]),
            ),
          );
        },
      );
    }

    final teamNombre = _equipoSeleccionado!['name'] as String? ?? '';
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF0D1B2A),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _equipoSeleccionado = null),
            child: const Icon(Icons.arrow_back, color: Colors.white54, size: 20),
          ),
          const SizedBox(width: 12),
          Text(teamNombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF0D1B2A),
        child: Row(children: const [
          SizedBox(width: 50),
          Expanded(child: Text('Jugador', style: TextStyle(color: Colors.white38, fontSize: 11))),
          SizedBox(width: 32, child: Text('PJ', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
          SizedBox(width: 32, child: Text('G', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
          SizedBox(width: 32, child: Text('A', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
          SizedBox(width: 40, child: Text('Min', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _jugadores.length + (_cargandoJugadores ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == _jugadores.length) {
              return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF00C853))));
            }
            return _cardJugador(_jugadores[i]);
          },
        ),
      ),
    ]);
  }

  Widget _cardJugador(Map<String, dynamic> data) {
    final player = data['player'];
    final statsList = data['statistics'] as List? ?? [];
    final stats = CopaService.statsForLeague(data, widget.leagueId) ??
        (statsList.isNotEmpty ? Map<String, dynamic>.from(statsList.first as Map) : <String, dynamic>{});
    final playerId = player['id'] as int?;
    final clubTeamId = stats['team']?['id'] as int?;
    final nombre = player['name'] as String? ?? '';
    final foto = player['photo'] as String? ?? '';
    final nacionalidad = (player['nationality'] as String?)?.trim() ?? '';
    final flagNat = flagEmojiFromCountryName(nacionalidad);
    final pos = stats['games']?['position'] as String? ?? '';
    final partidos = stats['games']?['appearences'] as int? ?? 0;
    final goles = stats['goals']?['total'] as int? ?? 0;
    final asistencias = stats['goals']?['assists'] as int? ?? 0;
    final rating = double.tryParse(stats['games']?['rating']?.toString() ?? '') ?? 0.0;

    String posAbrev = '';
    Color posColor = Colors.white38;
    if (pos == 'Goalkeeper') { posAbrev = 'GK'; posColor = Colors.amber; }
    else if (pos == 'Defender') { posAbrev = 'DEF'; posColor = Colors.blue; }
    else if (pos == 'Midfielder') { posAbrev = 'MED'; posColor = Colors.green; }
    else if (pos == 'Attacker') { posAbrev = 'DEL'; posColor = Colors.red; }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
          backgroundColor: Colors.white12,
          child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 18) : null,
        ),
        if (flagNat.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(flagNat, style: const TextStyle(fontSize: 16, height: 1)),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: playerId != null && playerId > 0 && clubTeamId != null
                ? () => showPlayerCareerSheet(context,
                    playerId: playerId, clubTeamId: clubTeamId, playerName: nombre)
                : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis),
              if (posAbrev.isNotEmpty) Text(posAbrev, style: TextStyle(color: posColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        SizedBox(width: 32, child: Text('$partidos', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 32, child: Text('$goles', style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 32, child: Text('$asistencias', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 40, child: Text(rating > 0 ? rating.toStringAsFixed(1) : '-', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
      ]),
    );
  }
}
