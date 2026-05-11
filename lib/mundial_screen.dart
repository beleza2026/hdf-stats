import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paywall_screen.dart';
import 'mundial_partido_sheet.dart';
import 'mundial_service.dart';
import 'mundial_simulador_screen.dart';

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
  List<Map<String, dynamic>> _grupos = [];
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
        final grupo = _grupos[i] as List?;
        if (grupo == null || grupo.isEmpty) return const SizedBox();
        final nombreGrupo = grupo[0]['group'] as String? ?? 'Grupo ${i + 1}';
        return _cardGrupo(nombreGrupo, grupo.cast<Map<String, dynamic>>());
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
                  ? Image.network(logo, width: 20, height: 20,
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
    final data = await MundialService.getGoleadores();
    if (mounted) setState(() { _jugadores = data; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    if (_jugadores.isEmpty) {
      return const Center(child: Text('Sin datos', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _jugadores.length,
      itemBuilder: (context, i) {
        final item = _jugadores[i];
        final player = item['player'] ?? {};
        final stats = (item['statistics'] as List?)?.first ?? {};
        final goles = stats['goals']?['total'] ?? 0;
        final asists = stats['goals']?['assists'] ?? 0;
        final foto = player['photo'] as String? ?? '';
        final nombre = player['name'] as String? ?? '';
        final equipo = stats['team']?['name'] as String? ?? '';
        final logoEq = stats['team']?['logo'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: i == 0
                ? const Color(0xFF00C853).withValues(alpha: 0.12)
                : const Color(0xFF1B2A3B),
            borderRadius: BorderRadius.circular(10),
            border: i == 0
                ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4))
                : null,
          ),
          child: Row(children: [
            // Posición
            SizedBox(
              width: 24,
              child: Text('${i + 1}',
                  style: TextStyle(
                      color: i == 0 ? const Color(0xFF00C853) : Colors.white38,
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
                    Image.network(logoEq, width: 14, height: 14,
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
              Text('${asists ?? 0}',
                  style: const TextStyle(
                      color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('asist.',
                  style: TextStyle(color: Colors.white38, fontSize: 9)),
            ]),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB CRUCES (Octavos de final dinámico)
// ─────────────────────────────────────────────────────────────────────────────
class _TabCruces extends StatefulWidget {
  @override
  State<_TabCruces> createState() => _TabCrucesState();
}

class _TabCrucesState extends State<_TabCruces> {
  List<Map<String, dynamic>> _grupos = [];
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

  // Retorna {primero, segundo} de cada grupo
  Map<String, Map<String, dynamic>> _getPrimeroSegundo() {
    final result = <String, Map<String, dynamic>>{};
    for (final grupoRaw in _grupos) {
      final grupo = grupoRaw as List?;
      if (grupo == null || grupo.isEmpty) continue;
      final nombreGrupo = grupo[0]['group'] as String? ?? '';
      // Ordenar por rank
      final sorted = List.from(grupo)
        ..sort((a, b) => (a['rank'] ?? 99).compareTo(b['rank'] ?? 99));
      if (sorted.isNotEmpty) {
        result['${nombreGrupo}_1'] = sorted[0] as Map<String, dynamic>;
      }
      if (sorted.length > 1) {
        result['${nombreGrupo}_2'] = sorted[1] as Map<String, dynamic>;
      }
    }
    return result;
  }

  // Cruces según reglamento FIFA 2026 (12 grupos A-L)
  // 1A vs 2B | 1B vs 2A | 1C vs 2D | 1D vs 2C | 1E vs 2F | 1F vs 2E
  // 1G vs 2H | 1H vs 2G | 1I vs 2J | 1J vs 2I | 1K vs 2L | 1L vs 2K
  // + 8 mejores 3ros (bracket abierto)
  List<Map<String, String>> get _crucesBase => [
    {'a': 'Group A_1', 'b': 'Group B_2', 'label': 'Llave 1'},
    {'a': 'Group B_1', 'b': 'Group A_2', 'label': 'Llave 2'},
    {'a': 'Group C_1', 'b': 'Group D_2', 'label': 'Llave 3'},
    {'a': 'Group D_1', 'b': 'Group C_2', 'label': 'Llave 4'},
    {'a': 'Group E_1', 'b': 'Group F_2', 'label': 'Llave 5'},
    {'a': 'Group F_1', 'b': 'Group E_2', 'label': 'Llave 6'},
    {'a': 'Group G_1', 'b': 'Group H_2', 'label': 'Llave 7'},
    {'a': 'Group H_1', 'b': 'Group G_2', 'label': 'Llave 8'},
    {'a': 'Group I_1', 'b': 'Group J_2', 'label': 'Llave 9'},
    {'a': 'Group J_1', 'b': 'Group I_2', 'label': 'Llave 10'},
    {'a': 'Group K_1', 'b': 'Group L_2', 'label': 'Llave 11'},
    {'a': 'Group L_1', 'b': 'Group K_2', 'label': 'Llave 12'},
  ];

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));

    final clasificados = _getPrimeroSegundo();

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
                'Cruces proyectados según posiciones actuales. Se actualizan con la tabla.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('OCTAVOS DE FINAL',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
        ),
        ..._crucesBase.map((cruce) {
          final eq1 = clasificados[cruce['a']!];
          final eq2 = clasificados[cruce['b']!];
          return _cardCruce(cruce['label']!, eq1, eq2);
        }),
      ],
    );
  }

  Widget _cardCruce(String label, Map<String, dynamic>? eq1, Map<String, dynamic>? eq2) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        // Label
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        // Equipo 1
        Expanded(child: _equipoCruce(eq1, align: TextAlign.right)),
        // VS
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('VS',
              style: const TextStyle(
                  color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        // Equipo 2
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
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text('$pts pts',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
              const SizedBox(width: 8),
              logo.isNotEmpty
                  ? Image.network(logo, width: 28, height: 28,
                      errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 24, color: Colors.white24))
                  : const Icon(Icons.sports_soccer, size: 24, color: Colors.white24),
            ]
          : [
              logo.isNotEmpty
                  ? Image.network(logo, width: 28, height: 28,
                      errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 24, color: Colors.white24))
                  : const Icon(Icons.sports_soccer, size: 24, color: Colors.white24),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text('$pts pts',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ],
    );
    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD PARTIDO (compartida entre HOY y FIXTURE)
// ─────────────────────────────────────────────────────────────────────────────
Widget _cardPartido(BuildContext context, Map<String, dynamic> partido) {
  final fixture = partido['fixture'] ?? {};
  final teams = partido['teams'] ?? {};
  final goals = partido['goals'] ?? {};
  final league = partido['league'] ?? {};

  final home = teams['home'] ?? {};
  final away = teams['away'] ?? {};
  final homeName = home['name'] as String? ?? '';
  final awayName = away['name'] as String? ?? '';
  final homeLogo = home['logo'] as String? ?? '';
  final awayLogo = away['logo'] as String? ?? '';
  final homeGoals = goals['home'];
  final awayGoals = goals['away'];
  final status = fixture['status']?['short'] as String? ?? '';
  final elapsed = fixture['status']?['elapsed'];
  final fecha = DateTime.tryParse(fixture['date'] ?? '')?.toLocal();
  final ronda = league['round'] as String? ?? '';

  String horario = '';
  if (fecha != null) {
    horario =
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  final isLive = ['1H', '2H', 'HT', 'ET', 'P'].contains(status);
  final isFinished = const {'FT', 'AET', 'PEN'}.contains(status);

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
      Row(children: [
        // Local
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(homeName,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis),
            const SizedBox(width: 8),
            homeLogo.isNotEmpty
                ? Image.network(homeLogo, width: 28, height: 28,
                    errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 24, color: Colors.white24))
                : const Icon(Icons.sports_soccer, size: 24, color: Colors.white24),
          ]),
        ),
        // Marcador / Horario
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            if (isLive || isFinished)
              Row(children: [
                Text('${homeGoals ?? 0}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('-', style: TextStyle(color: Colors.white38, fontSize: 16)),
                ),
                Text('${awayGoals ?? 0}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ])
            else
              Text(horario,
                  style: const TextStyle(
                      color: Color(0xFF00C853), fontSize: 16, fontWeight: FontWeight.bold)),
            if (isLive)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(elapsed != null ? "$elapsed'" : 'EN VIVO',
                    style: const TextStyle(
                        color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
              )
            else if (isFinished)
              const Text('FT',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        ),
        // Visitante
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            awayLogo.isNotEmpty
                ? Image.network(awayLogo, width: 28, height: 28,
                    errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 24, color: Colors.white24))
                : const Icon(Icons.sports_soccer, size: 24, color: Colors.white24),
            const SizedBox(width: 8),
            Text(awayName,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
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
                    Image.network(logoEq, width: 14, height: 14,
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
