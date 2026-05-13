import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paywall_screen.dart';
import 'mundial_partido_sheet.dart';
import 'mundial_service.dart';
import 'mundial_simulador_screen.dart';
import 'penales_shootout_helper.dart';
import 'image_decode_helper.dart';
import 'nationality_flags.dart';

/// Nombres que devuelve la API a veces no coinciden con el mapa de países; normalizamos para la bandera.
String _mundialNombreParaBandera(String teamName) {
  final t = teamName.trim();
  if (t.isEmpty) return t;
  final k = t.toLowerCase();
  const aliases = <String, String>{
    'ir iran': 'Iran',
    'iran': 'Iran',
    'korea republic': 'South Korea',
    'korea, south': 'South Korea',
    'republic of korea': 'South Korea',
    'usa': 'United States',
    'u.s.a.': 'United States',
    'côte d\'ivoire': 'Ivory Coast',
    "cote d'ivoire": 'Ivory Coast',
    'cote divoire': 'Ivory Coast',
    'czechia': 'Czech Republic',
    'bosnia-herzegovina': 'Bosnia and Herzegovina',
    'bosnia and herzegovina': 'Bosnia and Herzegovina',
    'north macedonia': 'North Macedonia',
    'macedonia fyr': 'North Macedonia',
    'northern ireland': 'Northern Ireland',
    'south africa': 'South Africa',
    'south korea': 'South Korea',
    'saudi arabia': 'Saudi Arabia',
    'united arab emirates': 'United Arab Emirates',
    'trinidad and tobago': 'Trinidad and Tobago',
    'cape verde': 'Cape Verde',
    'cabo verde': 'Cape Verde',
    'dr congo': 'Congo DR',
    'democratic republic of congo': 'Congo DR',
    'holland': 'Netherlands',
    'great britain': 'England',
  };
  if (aliases.containsKey(k)) return aliases[k]!;
  return t;
}

/// Texto para filas de fixture: menos de 10 caracteres sin tocar; si no, reglas + recorte.
String _mundialNombreEquipoCorta(String raw) {
  final name = raw.trim();
  if (name.length <= 10) return name;
  final lower = name.toLowerCase();
  if (lower.contains('bosnia')) return 'Bosnia & Hz.';
  if (lower.contains('czech')) return 'Czech Rep.';
  if (lower.contains('united states') || lower == 'usa') return 'USA';
  if (lower.contains('south korea') || lower.contains('korea republic')) return 'S. Korea';
  if (lower.contains('north macedonia') || (lower.contains('macedonia') && lower.contains('north'))) return 'N. Maced.';
  if (lower.contains('saudi arabia')) return 'Saudi Arab.';
  if (lower.contains('united arab emirates')) return 'UAE';
  if (lower.contains('northern ireland')) return 'N. Irel.';
  if (lower.contains('south africa')) return 'S. Africa';
  if (lower.contains('new zealand')) return 'N. Zeal.';
  if (lower.contains('trinidad')) return 'Trin. & T.';
  if (lower.contains('papua')) return 'PNG';
  if (lower.contains('dominican republic')) return 'Dom. Rep.';
  if (lower.contains('netherlands')) return 'Netherl.';
  if (lower.contains('switzerland')) return 'Switzerl.';
  if (lower.contains('portugal')) return 'Portugal';
  if (lower.contains('argentina')) return 'Argentina';
  if (lower.contains('australia')) return 'Australia';
  if (lower.contains('côte') || lower.contains('cote d') || lower.contains('ivory')) return 'C. d\'Ivoire';
  final cut = name.substring(0, 8).trimRight();
  return cut.isEmpty ? name : '$cut…';
}

/// Solo emoji de bandera o monograma: **nunca** cargamos PNG del CDN en el fixture (evita marcas de agua).
Widget _mundialEscudoLista({double side = 26, String? teamHint}) {
  final hint = teamHint?.trim() ?? '';
  if (hint.isNotEmpty) {
    final normalized = _mundialNombreParaBandera(hint);
    var flag = flagEmojiFromCountryName(normalized);
    if (flag.isEmpty && normalized != hint) {
      flag = flagEmojiFromCountryName(hint);
    }
    if (flag.isNotEmpty) {
      return Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2838),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(flag, style: TextStyle(fontSize: side * 0.48)),
      );
    }
    final letters = hint.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ]'), '');
    final mono = letters.length >= 2
        ? letters.substring(0, 2).toUpperCase()
        : letters.isEmpty
            ? '?'
            : letters.toUpperCase();
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF243447),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        mono,
        style: TextStyle(
          fontSize: side * 0.32,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.85),
          height: 1,
        ),
      ),
    );
  }
  return Icon(Icons.sports_soccer, size: side - 2, color: Colors.white24);
}

// ─────────────────────────────────────────────────────────────────────────────
// MUNDIAL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class MundialScreen extends StatefulWidget {
  final VoidCallback onIrInicio;
  final bool esPremium;

  const MundialScreen({
    super.key,
    required this.onIrInicio,
    required this.esPremium,
  });

  @override
  State<MundialScreen> createState() => _MundialScreenState();
}

class _MundialScreenState extends State<MundialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
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
          icon: const Icon(Icons.home_rounded, color: Color(0xFF00C853)),
          onPressed: widget.onIrInicio,
        ),
        title: Row(
          children: [
            const Text('🌍', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            const Text('MUNDIAL 2026',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.5)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF00C853),
          labelColor: const Color(0xFF00C853),
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          tabs: [
            const Tab(text: 'HOY'),
            const Tab(text: 'FIXTURE'),
            const Tab(text: 'GRUPOS'),
            const Tab(text: 'GOLEADORES'),
            const Tab(text: 'CRUCES'),
            const Tab(text: 'SIMULADOR'),
            Tab(text: widget.esPremium ? 'MEJORES ⭐' : 'MEJORES 🔒'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TabHoy(),
          _TabFixture(),
          _TabGrupos(),
          _TabGoleadores(),
          _TabCruces(),
          const MundialSimuladorScreen(),
          _TabMejores(esPremium: widget.esPremium),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB HOY
// ─────────────────────────────────────────────────────────────────────────────
class _TabHoy extends StatefulWidget {
  @override
  State<_TabHoy> createState() => _TabHoyState();
}

class _TabHoyState extends State<_TabHoy> {
  List<Map<String, dynamic>> _partidos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await MundialService.getPartidosHoy();
    if (mounted) setState(() { _partidos = data; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    if (_partidos.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🌍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('No hay partidos hoy',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: const Color(0xFF00C853),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _partidos.length,
        itemBuilder: (context, i) => _cardPartido(context, _partidos[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB FIXTURE
// ─────────────────────────────────────────────────────────────────────────────
class _TabFixture extends StatefulWidget {
  @override
  State<_TabFixture> createState() => _TabFixtureState();
}

class _TabFixtureState extends State<_TabFixture> {
  List<Map<String, dynamic>> _partidos = [];
  bool _cargando = true;
  String _rondaSeleccionada = '';
  Map<String, List<Map<String, dynamic>>> _porRonda = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await MundialService.getFixture();
    final Map<String, List<Map<String, dynamic>>> porRonda = {};
    for (final p in data) {
      final ronda = p['league']?['round'] as String? ?? 'Otro';
      porRonda.putIfAbsent(ronda, () => []).add(p);
    }
    if (mounted) {
      setState(() {
        _partidos = data;
        _porRonda = porRonda;
        _rondaSeleccionada = porRonda.keys.isNotEmpty ? porRonda.keys.first : '';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    return Column(children: [
      // Selector de ronda
      SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: _porRonda.keys.length,
          itemBuilder: (context, i) {
            final ronda = _porRonda.keys.elementAt(i);
            final sel = ronda == _rondaSeleccionada;
            return GestureDetector(
              onTap: () => setState(() => _rondaSeleccionada = ronda),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF00C853) : const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(ronda,
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
          children: (_porRonda[_rondaSeleccionada] ?? [])
              .map((p) => _cardPartido(context, p))
              .toList(),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB GRUPOS
// ─────────────────────────────────────────────────────────────────────────────
class _TabGrupos extends StatefulWidget {
  @override
  State<_TabGrupos> createState() => _TabGruposState();
}

class _TabGruposState extends State<_TabGrupos> {
  List<List<Map<String, dynamic>>> _grupos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await MundialService.getGrupos();
    if (mounted) setState(() { _grupos = data; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    if (_grupos.isEmpty) {
      return const Center(child: Text('Sin datos de grupos', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _grupos.length,
      itemBuilder: (context, i) {
        final grupo = _grupos[i];
        if (grupo.isEmpty) return const SizedBox();
        final nombreGrupo = grupo[0]['group'] as String? ?? 'Grupo ${i + 1}';
        return _cardGrupo(nombreGrupo, grupo);
      },
    );
  }

  Widget _cardGrupo(String nombre, List<Map<String, dynamic>> equipos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // Header grupo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF0D2137),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Text(nombre,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1)),
            const Spacer(),
            for (final col in ['PJ', 'G', 'E', 'P', 'GD', 'Pts'])
              SizedBox(
                width: col == 'GD' ? 36 : 28,
                child: Text(col,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    textAlign: TextAlign.center),
              ),
          ]),
        ),
        // Equipos
        ...equipos.asMap().entries.map((entry) {
          final idx = entry.key;
          final eq = entry.value;
          final team = eq['team'] ?? {};
          final all = eq['all'] ?? {};
          final pts = eq['points'] ?? 0;
          final gd = eq['goalsDiff'] ?? 0;
          final pj = all['played'] ?? 0;
          final g = all['win'] ?? 0;
          final e = all['draw'] ?? 0;
          final p = all['lose'] ?? 0;
          final logo = team['logo'] as String? ?? '';
          final nombre = team['name'] as String? ?? '';
          final clasifica = idx < 2;

          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: idx < equipos.length - 1
                    ? const BorderSide(color: Colors.white10, width: 0.5)
                    : BorderSide.none,
              ),
              color: clasifica
                  ? const Color(0xFF00C853).withValues(alpha: 0.06)
                  : Colors.transparent,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 16,
                child: Text('${idx + 1}',
                    style: TextStyle(
                        color: clasifica ? const Color(0xFF00C853) : Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              logo.isNotEmpty
                  ? DecodedNetworkImage(logo, width: 20, height: 20,
                      errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 20, color: Colors.white24))
                  : const Icon(Icons.sports_soccer, size: 20, color: Colors.white24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              for (final val in [pj, g, e, p])
                SizedBox(
                  width: 28,
                  child: Text('$val',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
              SizedBox(
                width: 36,
                child: Text(gd >= 0 ? '+$gd' : '$gd',
                    style: TextStyle(
                        color: gd > 0
                            ? const Color(0xFF00C853)
                            : gd < 0 ? Colors.red : Colors.white38,
                        fontSize: 12),
                    textAlign: TextAlign.center),
              ),
              SizedBox(
                width: 28,
                child: Text('$pts',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB GOLEADORES
// ─────────────────────────────────────────────────────────────────────────────
class _TabGoleadores extends StatefulWidget {
  @override
  State<_TabGoleadores> createState() => _TabGoleadoresState();
}

class _TabGoleadoresState extends State<_TabGoleadores> {
  List<Map<String, dynamic>> _jugadores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final mostrar = await MundialService.debeMostrarTablaGoleadoresMundial();
    if (!mounted) return;
    if (!mostrar) {
      setState(() {
        _jugadores = [];
        _cargando = false;
      });
      return;
    }
    setState(() {
      _cargando = true;
    });
    final data = await MundialService.getGoleadores();
    final filtrados = data.where((item) {
      final st = MundialService.statisticsMundialLiga1(item);
      if (st == null) return false;
      final league = st['league'];
      if (league is! Map || (league['id'] as num?)?.toInt() != 1) return false;
      final goals = MundialService.childMap(st['goals']);
      final g = (goals['total'] as num?)?.toInt() ?? int.tryParse('${goals['total']}') ?? 0;
      return g > 0;
    }).toList();
    if (!mounted) return;
    setState(() {
      _jugadores = filtrados;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));

    if (_jugadores.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF00C853),
        onRefresh: _cargar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  MundialService.esAntesDelInicioMundial2026Utc()
                      ? 'La tabla de goleadores se habilita cuando comience el Mundial (con partidos ya jugados en el torneo).'
                      : 'Aún no hay goleadores con goles registrados en el torneo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.35),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00C853),
      onRefresh: _cargar,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _jugadores.length,
        itemBuilder: (context, i) {
        final idx = i;
        final item = _jugadores[idx];
        final player = item['player'] is Map
            ? Map<String, dynamic>.from(item['player'] as Map)
            : <String, dynamic>{};
        final stats = MundialService.statisticsMundialLiga1(item) ?? {};
        final goalsMap = MundialService.childMap(stats['goals']);
        final goles = (goalsMap['total'] as num?)?.toInt() ?? int.tryParse('${goalsMap['total']}') ?? 0;
        final asists = (goalsMap['assists'] as num?)?.toInt() ?? int.tryParse('${goalsMap['assists']}') ?? 0;
        final foto = player['photo'] as String? ?? '';
        final nombre = player['name'] as String? ?? '';
        final teamMap = MundialService.childMap(stats['team']);
        final equipo = teamMap['name'] as String? ?? '';
        final logoEq = teamMap['logo'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: idx == 0
                ? const Color(0xFF00C853).withValues(alpha: 0.12)
                : const Color(0xFF1B2A3B),
            borderRadius: BorderRadius.circular(10),
            border: idx == 0
                ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4))
                : null,
          ),
          child: Row(children: [
            // Posición
            SizedBox(
              width: 24,
              child: Text('${idx + 1}',
                  style: TextStyle(
                      color: idx == 0 ? const Color(0xFF00C853) : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 8),
            // Foto
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white12,
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 18) : null,
            ),
            const SizedBox(width: 10),
            // Nombre + equipo
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Row(children: [
                  if (logoEq.isNotEmpty)
                    DecodedNetworkImage(logoEq, width: 14, height: 14,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  const SizedBox(width: 4),
                  Text(equipo,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ]),
            ),
            // Goles
            Column(children: [
              Text('$goles',
                  style: const TextStyle(
                      color: Color(0xFF00C853),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const Text('goles',
                  style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
            const SizedBox(width: 16),
            // Asistencias
            Column(children: [
              Text('$asists',
                  style: const TextStyle(
                      color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('asist.',
                  style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
          ]),
        );
      },
    ),
    );
  }
}

// ── Bracket 32avos Mundial 2026 (partidos FIFA 73–88). Terceros en cruces `t:`: mejor 3°
// provisional entre los grupos del pool (la matriz final depende de los 8 terceros que clasifiquen).
// Referencia: sorteo / procedimiento FIFA Mundial 2026 (fase eliminatoria inicial).
// ─────────────────────────────────────────────────────────────────────────────

class _MundialR32Def {
  const _MundialR32Def(this.match, this.desc, this.aSpec, this.bSpec);
  final int match;
  final String desc;
  final String aSpec; // w:X = 1°, r:X = 2°, t:LETTERS = mejor 3° del pool
  final String bSpec;
}

const _mundialR32Oficial = <_MundialR32Def>[
  _MundialR32Def(73, '2°A vs 2°B', 'r:A', 'r:B'),
  _MundialR32Def(74, '1°E vs 3° (A,B,C,D,F)', 'w:E', 't:ABCDF'),
  _MundialR32Def(75, '1°F vs 2°C', 'w:F', 'r:C'),
  _MundialR32Def(76, '1°C vs 2°F', 'w:C', 'r:F'),
  _MundialR32Def(77, '1°I vs 3° (C,D,F,G,H)', 'w:I', 't:CDFGH'),
  _MundialR32Def(78, '2°E vs 2°I', 'r:E', 'r:I'),
  _MundialR32Def(79, '1°A vs 3° (C,E,F,H,I)', 'w:A', 't:CEFHI'),
  _MundialR32Def(80, '1°L vs 3° (E,H,I,J,K)', 'w:L', 't:EHIJK'),
  _MundialR32Def(81, '1°D vs 3° (B,E,F,I,J)', 'w:D', 't:BEFIJ'),
  _MundialR32Def(82, '1°G vs 3° (A,E,H,I,J)', 'w:G', 't:AEHIJ'),
  _MundialR32Def(83, '2°K vs 2°L', 'r:K', 'r:L'),
  _MundialR32Def(84, '1°H vs 2°J', 'w:H', 'r:J'),
  _MundialR32Def(85, '1°B vs 3° (E,F,G,I,J)', 'w:B', 't:EFGIJ'),
  _MundialR32Def(86, '1°J vs 2°H', 'w:J', 'r:H'),
  _MundialR32Def(87, '1°K vs 3° (D,E,I,J,L)', 'w:K', 't:DEIJL'),
  _MundialR32Def(88, '2°D vs 2°G', 'r:D', 'r:G'),
];

int _mundialGolesFavorRow(Map<String, dynamic> eq) {
  final g = eq['goals'];
  if (g is Map && g['for'] != null) return (g['for'] as num?)?.toInt() ?? 0;
  final all = eq['all'];
  if (all is Map) {
    final gg = all['goals'];
    if (gg is Map && gg['for'] != null) return (gg['for'] as num?)?.toInt() ?? 0;
  }
  return 0;
}

Map<String, dynamic>? _mundialMejorTerceroPool(String letters, Map<String, Map<String, dynamic>> c) {
  Map<String, dynamic>? best;
  var bestPts = -1;
  var bestGd = -999999;
  var bestGf = -1;
  for (var i = 0; i < letters.length; i++) {
    final ch = letters[i].toUpperCase();
    if (ch.codeUnitAt(0) < 65 || ch.codeUnitAt(0) > 76) continue;
    final row = c['Group ${ch}_3'];
    if (row == null) continue;
    final pts = (row['points'] as num?)?.toInt() ?? 0;
    final gd = (row['goalsDiff'] as num?)?.toInt() ?? 0;
    final gf = _mundialGolesFavorRow(row);
    if (pts > bestPts ||
        (pts == bestPts && gd > bestGd) ||
        (pts == bestPts && gd == bestGd && gf > bestGf)) {
      best = row;
      bestPts = pts;
      bestGd = gd;
      bestGf = gf;
    }
  }
  return best;
}

Map<String, dynamic>? _mundialR32ResolveSide(String spec, Map<String, Map<String, dynamic>> c) {
  final i = spec.indexOf(':');
  if (i <= 0 || i >= spec.length - 1) return null;
  final kind = spec.substring(0, i);
  final arg = spec.substring(i + 1);
  switch (kind) {
    case 'w':
      if (arg.length != 1) return null;
      return c['Group ${arg}_1'];
    case 'r':
      if (arg.length != 1) return null;
      return c['Group ${arg}_2'];
    case 't':
      if (arg.isEmpty) return null;
      return _mundialMejorTerceroPool(arg, c);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB CRUCES (32avos — bracket FIFA 2026)
// ─────────────────────────────────────────────────────────────────────────────
class _TabCruces extends StatefulWidget {
  @override
  State<_TabCruces> createState() => _TabCrucesState();
}

class _TabCrucesState extends State<_TabCruces> {
  List<List<Map<String, dynamic>>> _grupos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await MundialService.getGrupos();
    if (mounted) setState(() { _grupos = data; _cargando = false; });
  }

  /// 1°, 2° y 3° por grupo (`Group A_1`, `Group A_2`, `Group A_3`).
  Map<String, Map<String, dynamic>> _getClasificadosMundial() {
    final result = <String, Map<String, dynamic>>{};
    for (final grupo in _grupos) {
      if (grupo.isEmpty) continue;
      final nombreGrupo = (grupo[0]['group'] as String? ?? '').trim();
      if (nombreGrupo.isEmpty) continue;
      final sorted = List<Map<String, dynamic>>.from(grupo)
        ..sort((a, b) {
          final ra = (a['rank'] as num?)?.toInt() ?? 99;
          final rb = (b['rank'] as num?)?.toInt() ?? 99;
          return ra.compareTo(rb);
        });
      if (sorted.isNotEmpty) result['${nombreGrupo}_1'] = sorted[0];
      if (sorted.length > 1) result['${nombreGrupo}_2'] = sorted[1];
      if (sorted.length > 2) result['${nombreGrupo}_3'] = sorted[2];
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));

    final clasificados = _getClasificadosMundial();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Color(0xFF00C853), size: 14),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '32avos según bracket FIFA (partidos 73–88). Donde hay "3°", mostramos el mejor tercero provisional del pool de grupos indicado; la llave final depende de los 8 terceros que clasifiquen.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('32AVOS DE FINAL',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
        ),
        ..._mundialR32Oficial.map((slot) {
          final eq1 = _mundialR32ResolveSide(slot.aSpec, clasificados);
          final eq2 = _mundialR32ResolveSide(slot.bSpec, clasificados);
          return _cardCruce('M${slot.match}', eq1, eq2, desc: slot.desc);
        }),
      ],
    );
  }

  Widget _cardCruce(String label, Map<String, dynamic>? eq1, Map<String, dynamic>? eq2, {String? desc}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (desc != null && desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    desc,
                    style: const TextStyle(color: Colors.white24, fontSize: 7, height: 1.2),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _equipoCruce(eq1, align: TextAlign.right)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('VS',
              style: const TextStyle(
                  color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Expanded(child: _equipoCruce(eq2, align: TextAlign.left)),
      ]),
    );
  }

  Widget _equipoCruce(Map<String, dynamic>? eq, {required TextAlign align}) {
    if (eq == null) {
      return Text('Por definir',
          style: const TextStyle(color: Colors.white24, fontSize: 12),
          textAlign: align);
    }
    final team = eq['team'] ?? {};
    final nombre = team['name'] as String? ?? '';
    final logo = team['logo'] as String? ?? '';
    final pts = eq['points'] ?? 0;

    final content = Row(
      mainAxisAlignment:
          align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: align == TextAlign.right
          ? [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nombre,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right),
                    Text('$pts pts',
                        style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              logo.isNotEmpty
                  ? DecodedNetworkImage(logo, width: 24, height: 24,
                      errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 20, color: Colors.white24))
                  : const Icon(Icons.sports_soccer, size: 20, color: Colors.white24),
            ]
          : [
              logo.isNotEmpty
                  ? DecodedNetworkImage(logo, width: 24, height: 24,
                      errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 20, color: Colors.white24))
                  : const Icon(Icons.sports_soccer, size: 20, color: Colors.white24),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nombre,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left),
                    Text('$pts pts',
                        style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ],
                ),
              ),
            ],
    );
    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD PARTIDO (compartida entre HOY y FIXTURE)
// Logos del CDN a veces traen marca de agua: en listas usamos bandera por país cuando hay mapeo.
// ─────────────────────────────────────────────────────────────────────────────

String _mundialDiaCortaEs(DateTime d) {
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${meses[d.month - 1]}';
}

DateTime? _mundialFixtureLocal(Map<String, dynamic> fixture) {
  final ds = fixture['date'] as String?;
  if (ds != null && ds.isNotEmpty) {
    final parsed = DateTime.tryParse(ds);
    if (parsed != null) return parsed.toLocal();
  }
  final ts = fixture['timestamp'];
  if (ts is int && ts > 0) {
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
  }
  if (ts is num && ts > 0) {
    return DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000, isUtc: true).toLocal();
  }
  return null;
}

Widget _cardPartido(BuildContext context, Map<String, dynamic> partido) {
  final fixtureRaw = partido['fixture'];
  final fixture = fixtureRaw is Map
      ? Map<String, dynamic>.from(fixtureRaw)
      : <String, dynamic>{};
  final teams = partido['teams'] ?? {};
  final goals = partido['goals'] ?? {};
  final league = partido['league'] ?? {};

  final home = teams['home'] ?? {};
  final away = teams['away'] ?? {};
  final homeName = home['name'] as String? ?? '';
  final awayName = away['name'] as String? ?? '';
  final homeGoals = goals['home'];
  final awayGoals = goals['away'];
  final status = fixture['status']?['short'] as String? ?? '';
  final elapsed = fixture['status']?['elapsed'];
  final fechaLocal = _mundialFixtureLocal(fixture);
  final ronda = league['round'] as String? ?? '';

  String horario = '—';
  if (fechaLocal != null) {
    horario =
        '${fechaLocal.hour.toString().padLeft(2, '0')}:${fechaLocal.minute.toString().padLeft(2, '0')}';
  }

  final isLive = ['1H', '2H', 'HT', 'ET', 'P'].contains(status);
  final isFinished = const {'FT', 'AET', 'PEN'}.contains(status);
  final penSuf = PenalesShootoutHelper.sufijoMarcadorParentesis(partido);

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => showMundialPartidoSheet(context, partido),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isLive
              ? const Color(0xFF0D2137)
              : const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(10),
          border: isLive
              ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4))
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ronda
      if (ronda.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(ronda,
              style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // [Nombre local + escudo] — flex mayor para texto largo
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    _mundialNombreEquipoCorta(homeName),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _mundialEscudoLista(teamHint: homeName),
              ],
            ),
          ),
          // [Hora / marcador] — columna central fija en proporción menor
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fechaLocal != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        _mundialDiaCortaEs(fechaLocal),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (isLive || isFinished)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${homeGoals ?? 0}',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text('-', style: TextStyle(color: Colors.white38, fontSize: 14)),
                            ),
                            Text(
                              '${awayGoals ?? 0}',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (penSuf != null && isFinished)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              penSuf,
                              style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    )
                  else
                    Text(
                      horario,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF00C853), fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  if (isLive)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        elapsed != null ? "$elapsed'" : 'EN VIVO',
                        style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    )
                  else if (isFinished)
                    const Text('FT', style: TextStyle(color: Colors.white38, fontSize: 9)),
                ],
              ),
            ),
          ),
          // [Escudo + nombre visitante]
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _mundialEscudoLista(teamHint: awayName),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _mundialNombreEquipoCorta(awayName),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
        ],
      ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB MEJORES JUGADORES (PREMIUM)
// ─────────────────────────────────────────────────────────────────────────────
class _TabMejores extends StatefulWidget {
  final bool esPremium;
  const _TabMejores({required this.esPremium});

  @override
  State<_TabMejores> createState() => _TabMejoresState();
}

class _TabMejoresState extends State<_TabMejores> {
  List<Map<String, dynamic>> _jugadores = [];
  bool _cargando = true;
  int _pagina = 1;
  bool _hayMas = true;

  @override
  void initState() {
    super.initState();
    if (widget.esPremium) _cargar();
    else setState(() => _cargando = false);
  }

  Future<void> _cargar() async {
    final data = await MundialService.getMejoresJugadores(pagina: _pagina);
    if (mounted) {
      setState(() {
        _jugadores.addAll(data);
        _hayMas = data.length >= 20;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // PAYWALL
    if (!widget.esPremium) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('⭐', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text('MEJORES JUGADORES',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Rating promedio, partidos jugados y goles de los mejores del Mundial.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: kIsWeb ? null : () => PaywallScreen.open(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('ACTIVAR PREMIUM',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ]),
        ),
      );
    }

    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    if (_jugadores.isEmpty) return const Center(child: Text('Sin datos', style: TextStyle(color: Colors.white54)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _jugadores.length + (_hayMas ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _jugadores.length) {
          return TextButton(
            onPressed: () { _pagina++; _cargar(); },
            child: const Text('Ver más', style: TextStyle(color: Color(0xFF00C853))),
          );
        }
        final item = _jugadores[i];
        final player = item['player'] ?? {};
        final stats = (item['statistics'] as List?)?.firstWhere(
          (s) => s['league']?['id'] == 1, orElse: () => (item['statistics'] as List?)?.first ?? {});
        final rating = double.tryParse(stats?['games']?['rating']?.toString() ?? '') ?? 0.0;
        final goles = stats?['goals']?['total'] ?? 0;
        final partidos = stats?['games']?['appearences'] ?? 0;
        final foto = player['photo'] as String? ?? '';
        final nombre = player['name'] as String? ?? '';
        final equipo = stats?['team']?['name'] as String? ?? '';
        final logoEq = stats?['team']?['logo'] as String? ?? '';
        final pos = stats?['games']?['position'] as String? ?? '';

        Color ratingColor = Colors.white54;
        if (rating >= 8.0) ratingColor = const Color(0xFF00C853);
        else if (rating >= 7.0) ratingColor = Colors.amber;
        else if (rating >= 6.0) ratingColor = Colors.orange;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: i < 3 ? const Color(0xFF00C853).withValues(alpha: 0.08) : const Color(0xFF1B2A3B),
            borderRadius: BorderRadius.circular(10),
            border: i < 3 ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.25)) : null,
          ),
          child: Row(children: [
            SizedBox(
              width: 24,
              child: Text('${i + 1}',
                  style: TextStyle(
                      color: i == 0 ? const Color(0xFF00C853) : Colors.white38,
                      fontWeight: FontWeight.bold, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white12,
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 18) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Row(children: [
                  if (logoEq.isNotEmpty)
                    DecodedNetworkImage(logoEq, width: 14, height: 14,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  const SizedBox(width: 4),
                  Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(width: 6),
                  Text(pos, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ]),
              ]),
            ),
            // Rating
            Column(children: [
              Text(rating > 0 ? rating.toStringAsFixed(1) : '-',
                  style: TextStyle(color: ratingColor, fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('rating', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
            const SizedBox(width: 14),
            // Goles
            Column(children: [
              Text('$goles',
                  style: const TextStyle(color: Color(0xFF00C853), fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('goles', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
            const SizedBox(width: 14),
            // Partidos
            Column(children: [
              Text('$partidos',
                  style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('PJ', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
          ]),
        );
      },
    );
  }
}
