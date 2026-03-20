import 'package:flutter/material.dart';
import 'api_service.dart';
 
void main() {
  runApp(const HDFStatsApp());
}
 
class HDFStatsApp extends StatelessWidget {
  const HDFStatsApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HDF STATS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C853),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
 
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
 
  @override
  State<MainScreen> createState() => _MainScreenState();
}
 
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _fechaActual = -1;
  String _torneoActual = 'APERTURA';
 
  final List<Map<String, dynamic>> _sections = [
    {'icon': Icons.sports_soccer, 'label': 'Resultados'},
    {'icon': Icons.table_chart, 'label': 'Tablas'},
    {'icon': Icons.sports_soccer, 'label': 'Goleadores'},
    {'icon': Icons.sports_handball, 'label': 'Arqueros'},
    {'icon': Icons.calendar_month, 'label': 'Fixture'},
  ];
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        title: Row(
          children: const [
            Text('HDF', style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 2)),
            Text(' STATS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 2)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_outlined, color: Color(0xFF00C853)), onPressed: () {}),
          IconButton(icon: const Icon(Icons.person_outline, color: Colors.white70), onPressed: () {}),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF1B2A3B),
          selectedItemColor: const Color(0xFF00C853),
          unselectedItemColor: Colors.white38,
          currentIndex: _selectedIndex,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: _sections.map((s) => BottomNavigationBarItem(icon: Icon(s['icon']), label: s['label'])).toList(),
        ),
      ),
    );
  }
 
  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0: return _buildResultados();
      case 1: return _buildTablas();
      case 2: return _buildEquipos();
      case 3: return _buildArqueros();
      case 4: return _buildFixture();
      default: return _buildResultados();
    }
  }
 
  Widget _buildResultados() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getPartidosHoy(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay partidos hoy', style: TextStyle(color: Colors.white54)));
        }
        final partidos = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('HOY — LIGA PROFESIONAL'),
            const SizedBox(height: 12),
            ...partidos.map((partido) {
              final teams = partido['teams'];
              final goals = partido['goals'];
              final fixture = partido['fixture'];
              final status = fixture['status']['short'];
              final local = teams['home']['name'];
              final visitante = teams['away']['name'];
              final golesLocal = goals['home']?.toString() ?? '-';
              final golesVisitante = goals['away']?.toString() ?? '-';
              final fixtureId = fixture['id'] as int?;
              String statusDisplay;
              bool jugado = false;
              if (status == 'FT' || status == 'AET' || status == 'PEN') {
                statusDisplay = 'FT';
                jugado = true;
              } else if (status == '1H' || status == '2H' || status == 'ET') {
                statusDisplay = "${fixture['status']['elapsed']}'";
              } else if (status == 'NS') {
                final date = DateTime.parse(fixture['date']);
                statusDisplay = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              } else {
                statusDisplay = status;
              }
              return _matchCard(local, visitante, golesLocal, golesVisitante, statusDisplay, jugado, fixtureId);
            }),
          ],
        );
      },
    );
  }
 
  Widget _matchCard(String home, String away, String hScore, String aScore, String status, bool jugado, int? fixtureId) {
    final bool isLive = status.contains("'");
    final bool isFinished = status == 'FT';
    return GestureDetector(
      onTap: () => _mostrarDetalle(context, home, away, '$hScore - $aScore', jugado || isFinished, fixtureId: fixtureId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isLive ? const Color(0xFF00C853).withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(child: Text(home, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
              child: Text('$hScore - $aScore', style: TextStyle(color: isLive ? const Color(0xFF00C853) : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(away, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isLive ? const Color(0xFF00C853).withValues(alpha: 0.2) : isFinished ? Colors.white12 : const Color(0xFF1565C0).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(status, style: TextStyle(color: isLive ? const Color(0xFF00C853) : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildTablas() {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: ApiService.getTablas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay datos disponibles', style: TextStyle(color: Colors.white54)));
        }
        final zonas = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...zonas.entries.map((zona) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(zona.key.toUpperCase()),
                const SizedBox(height: 8),
                _tablaHeader(),
                ...zona.value.map((equipo) {
                  final team = equipo['team'];
                  final stats = equipo['all'];
                  return _tablaRow(equipo['rank'].toString(), team['name'], stats['played'].toString(), stats['win'].toString(), stats['draw'].toString(), stats['lose'].toString(), equipo['points'].toString());
                }),
                const SizedBox(height: 16),
              ],
            )),
          ],
        );
      },
    );
  }
 
  Widget _tablaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
      child: const Row(
        children: [
          SizedBox(width: 24, child: Text('#', style: TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text('EQUIPO', style: TextStyle(color: Colors.white54, fontSize: 12))),
          SizedBox(width: 28, child: Text('PJ', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text('G', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text('E', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text('P', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 32, child: Text('PTS', style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }
 
  Widget _tablaRow(String pos, String equipo, String pj, String g, String e, String p, String pts) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Expanded(child: Text(equipo, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
          SizedBox(width: 28, child: Text(pj, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text(p, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
          SizedBox(width: 32, child: Text(pts, style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }
 
  Widget _buildEquipos() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getGoleadores(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay datos disponibles', style: TextStyle(color: Colors.white54)));
        }
        final goleadores = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('GOLEADORES — LIGA PROFESIONAL'),
            const SizedBox(height: 12),
            ...goleadores.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              final player = g['player'];
              final stats = g['statistics'][0];
              return _goleadorCard((i + 1).toString(), player['name'], stats['team']['name'], stats['goals']['total'].toString());
            }),
          ],
        );
      },
    );
  }
 
  Widget _goleadorCard(String pos, String nombre, String equipo, String goles) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4))),
            child: Row(children: [
              const Icon(Icons.sports_soccer, color: Color(0xFF00C853), size: 14),
              const SizedBox(width: 4),
              Text(goles, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
        ],
      ),
    );
  }
 
  Widget _buildArqueros() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getArqueros(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay datos disponibles', style: TextStyle(color: Colors.white54)));
        }
        final arqueros = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('ARQUEROS — VALLAS INVICTAS'),
            const SizedBox(height: 12),
            ...arqueros.asMap().entries.map((entry) {
              final i = entry.key;
              final a = entry.value;
              final player = a['player'];
              final stats = a['statistics'][0];
              final goals = stats['goals'];
              final golesConcedidos = goals['conceded'] ?? 0;
              final partidosJugados = stats['games']['appearences'] ?? 1;
              final vallas = stats['games']['lineups'] != null ? (stats['goals']['saves'] ?? 0) : 0;
              final promedio = partidosJugados > 0 ? (golesConcedidos / partidosJugados).toStringAsFixed(2) : '0.00';
              return _arqueroCard(
                (i + 1).toString(),
                player['name'],
                stats['team']['name'],
                golesConcedidos.toString(),
                promedio,
                partidosJugados.toString(),
              );
            }),
          ],
        );
      },
    );
  }
 
  Widget _arqueroCard(String pos, String nombre, String equipo, String golesConcedidos, String promedio, String partidos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF00C853), size: 14),
                const SizedBox(width: 4),
                Text(golesConcedidos, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              Text('$promedio/partido', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
 
  Widget _buildFixture() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getFixture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay fixture disponible', style: TextStyle(color: Colors.white54)));
        }
 
        final todos = snapshot.data!;
 
        // Separar por torneo - IDs menores = Apertura, IDs mayores = Clausura
        final todosOrdenados = List<Map<String, dynamic>>.from(todos);
        todosOrdenados.sort((a, b) => (a['fixture']['id'] as int).compareTo(b['fixture']['id'] as int));
        final mitad = todosOrdenados.length ~/ 2;
        final apertura = todosOrdenados.take(mitad).toList();
        final clausura = todosOrdenados.skip(mitad).toList();
        final filtrados = _torneoActual == 'APERTURA' ? apertura : clausura;
 
        // Agrupar por fecha
        Map<int, List<Map<String, dynamic>>> porFecha = {};
        for (var p in filtrados) {
          final st = p['fixture']['status']['short'];
          if (st == 'PST' || st == 'CANC' || st == 'TBD') continue;
          final round = p['league']['round'] as String;
          final num = int.tryParse(round.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          porFecha.putIfAbsent(num, () => []).add(p);
        }
 
        final fechas = porFecha.keys.toList()..sort();
 
        // Inicializar en la última fecha con partidos jugados
        if (_fechaActual == -1) {
          _fechaActual = 0;
          for (int i = 0; i < fechas.length; i++) {
            final ps = porFecha[fechas[i]]!;
            final hayJugado = ps.any((p) {
              final s = p['fixture']['status']['short'];
              return s == 'FT' || s == 'AET' || s == 'PEN' || s == 'AWD' || s == 'WO';
            });
            if (hayJugado) _fechaActual = i;
          }
        }
 
        final numFecha = fechas[_fechaActual];
        final partidos = porFecha[numFecha]!;
        final hayJugadosEnFecha = partidos.any((p) {
          final s = p['fixture']['status']['short'];
          return s == 'FT' || s == 'AET' || s == 'PEN' || s == 'AWD' || s == 'WO';
        });
 
        return Column(
          children: [
            // Selector APERTURA / CLAUSURA
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF0D1B2A),
              child: Row(
                children: ['APERTURA', 'CLAUSURA'].map((t) => Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _torneoActual = t; _fechaActual = -1; }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _torneoActual == t ? const Color(0xFF00C853) : const Color(0xFF1B2A3B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: _torneoActual == t ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                )).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF1B2A3B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Color(0xFF00C853), size: 28),
                    onPressed: _fechaActual > 0 ? () => setState(() => _fechaActual--) : null,
                  ),
                  Column(children: [
                    Text('FECHA $numFecha', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)),
                    Text(hayJugadosEnFecha ? 'JUGADA' : 'PRÓXIMA', style: TextStyle(color: hayJugadosEnFecha ? Colors.white38 : const Color(0xFF00C853), fontSize: 11, letterSpacing: 1)),
                  ]),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Color(0xFF00C853), size: 28),
                    onPressed: _fechaActual < fechas.length - 1 ? () => setState(() => _fechaActual++) : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: partidos.map((p) {
                  final local = p['teams']['home']['name'];
                  final visitante = p['teams']['away']['name'];
                  final golesL = p['goals']['home']?.toString() ?? '-';
                  final golesV = p['goals']['away']?.toString() ?? '-';
                  final fecha = DateTime.parse(p['fixture']['date']);
                  final fixtureId = p['fixture']['id'] as int?;
                  final statusShort = p['fixture']['status']['short'];
                  final esJugado = statusShort == 'FT' || statusShort == 'AET' || statusShort == 'PEN' || statusShort == 'AWD' || statusShort == 'WO';
                  final hora = esJugado ? '$golesL - $golesV' : '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
 
                  return GestureDetector(
                    onTap: () => _mostrarDetalle(context, local, visitante, '$golesL - $golesV', esJugado, fixtureId: fixtureId),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2A3B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: esJugado ? Colors.transparent : const Color(0xFF00C853).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(local, style: TextStyle(color: esJugado ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
                            child: Text(hora, style: TextStyle(color: esJugado ? Colors.white70 : const Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(visitante, style: TextStyle(color: esJugado ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
 
  void _mostrarDetalle(BuildContext context, String local, String visitante, String resultado, bool jugado, {int? fixtureId}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B2A3B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<List<dynamic>>(
          future: jugado && fixtureId != null
          ? Future.wait([ApiService.getEstadisticasPartido(fixtureId), ApiService.getEventosPartido(fixtureId), ApiService.getLineupsPartido(fixtureId), ApiService.getDetallePartido(fixtureId), ApiService.getPlayersPartido(fixtureId.toString())])
            : Future.value([null, [], [], null, []]),
          builder: (context, snap) {
            final stats = snap.data?[0] as Map<String, dynamic>?;
            final eventos = List<Map<String, dynamic>>.from(snap.data?[1] ?? []);

 final lineups = List<Map<String, dynamic>>.from(snap.data?[2] ?? []);
final detalle = snap.data?.length != null && snap.data!.length > 3 
    ? snap.data![3] as Map<String, dynamic>? 
    : null;
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
int moralL = glLocal;
int moralV = glVisit;

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

// Para 1 gol de diferencia, máximo empate moral (sin invertir)
if (diferencia == 1) {
  if (glLocal > glVisit && moralL < moralV) moralL = moralV;
  if (glVisit > glLocal && moralV < moralL) moralV = moralL;
}

// Para empates, limitar diferencia moral a 1
if (glLocal == glVisit) {
  if (moralL > moralV + 1) moralL = moralV + 1;
  if (moralV > moralL + 1) moralV = moralL + 1;
}

moralLocal = moralL.toString();
moralVisitante = moralV.toString();
moralDesc = moralL > moralV
    ? '$local mereció ganar'
    : moralV > moralL
        ? '$visitante mereció ganar'
        : 'El resultado fue justo';
            }
 
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: Text(local, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10)),
                      child: Text(resultado, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 24)),
                    ),
                    Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                  ],
                ),
                const SizedBox(height: 20),
                if (jugado && fixtureId != null) ...[
                  if (snap.connectionState == ConnectionState.waiting)
                    const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF00C853))))
                  else if (stats != null) ...[
                   ...[
  _detalleSeccion('INFO DEL PARTIDO'),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.sports, color: Color(0xFF00C853), size: 16),
        const SizedBox(width: 8),
        Text('Árbitro: $arbitro', style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        const Icon(Icons.stadium, color: Color(0xFF00C853), size: 16),
        const SizedBox(width: 8),
        Text('$estadio${ciudad.isNotEmpty ? " · $ciudad" : ""}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    ]),
  ),
const SizedBox(height: 8),
              _detalleSeccion('MEJORES JUGADORES'),
              Builder(builder: (context) {
                final jugadores = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);
                if (jugadores.isEmpty) return const SizedBox.shrink();
                return Column(children: jugadores.take(5).map((j) {
                  final rating = j['rating'] as double;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Expanded(child: Text(j['nombre'], style: const TextStyle(color: Colors.white, fontSize: 13))),
                      Text(j['equipo'], style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: rating >= 7.5 ? Colors.green : rating >= 6.5 ? const Color(0xFFFF9800) : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ]),
                  );
                }).toList());
              }),
  const SizedBox(height: 8),
], _detalleSeccion('ESTADÍSTICAS'),
                    ...((stats['response'] as List).isNotEmpty
                      ? (stats['response'][0]['statistics'] as List).where((s) => ['Ball Possession', 'Shots on Goal', 'Corner Kicks', 'Fouls'].contains(s['type'])).map((s) {
                          final i = (stats['response'][0]['statistics'] as List).indexOf(s);
                          final valVisit = i < (stats['response'][1]['statistics'] as List).length ? stats['response'][1]['statistics'][i]['value']?.toString() ?? '-' : '-';
                          String label = s['type'];
                          if (label == 'Ball Possession') label = 'Posesión';
                          if (label == 'Shots on Goal') label = 'Tiros al arco';
                          if (label == 'Corner Kicks') label = 'Corners';
                          if (label == 'Fouls') label = 'Faltas';
                          return _statRow(label, s['value']?.toString() ?? '-', valVisit);
                        })
                      : []),
                    const SizedBox(height: 16),
                    // FIGURA DEL PARTIDO
if (jugado && eventos.isNotEmpty) ...[
  _detalleSeccion('FIGURA DEL PARTIDO HDF'),
  Builder(builder: (context) {
    final Map<String, int> puntos = {};
    final Map<String, String> equipos = {};
    for (var e in eventos) {
      final jugador = e['player']?['name'] ?? '';
      final tipo = e['type'] ?? '';
      final detalle = e['detail'] ?? '';
      final equipo = e['team']?['name'] ?? '';
      if (jugador.isEmpty) continue;
      puntos[jugador] ??= 0;
      equipos[jugador] = equipo;
      if (tipo == 'Goal' && detalle != 'Own Goal') puntos[jugador] = puntos[jugador]! + 3;
      if (tipo == 'Goal' && detalle == 'Own Goal') puntos[jugador] = puntos[jugador]! - 2;
      if (tipo == 'subst') { final sale = e['assist']?['name'] ?? ''; if (sale.isNotEmpty) { puntos[sale] ??= 0; equipos[sale] ??= equipo; } }
      if (tipo == 'Card' && detalle == 'Yellow Card') puntos[jugador] = puntos[jugador]! - 1;
      if (tipo == 'Card' && detalle == 'Red Card') puntos[jugador] = puntos[jugador]! - 3;
    }
    if (puntos.isEmpty) return const SizedBox();
    final sorted = puntos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final figura = sorted.first;
    final peor = sorted.last;
    final jugadores = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);
final figNombre = jugadores.isNotEmpty ? jugadores.first['nombre'] as String : figura.key;
final figEquipo = jugadores.isNotEmpty ? jugadores.first['equipo'] as String : (equipos[figura.key] ?? '');
final peorNombre = jugadores.isNotEmpty ? jugadores.last['nombre'] as String : peor.key;
final peorEquipo = jugadores.isNotEmpty ? jugadores.last['equipo'] as String : (equipos[peor.key] ?? '');
    
    return Column(children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3))),
        child: Row(children: [
          const Text('⭐', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('FIGURA DEL PARTIDO', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            Text(figura.key, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text(equipos[figNombre] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
        ]),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
        child: Row(children: [
          const Text('😤', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('PARA QUÉ TE TRAJE', style: TextStyle(color: Colors.red, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            Text(peor.key, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text(equipos[peor.key] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
        ]),
      ),
      const SizedBox(height: 8),
    ]);
  }),
],_detalleSeccion('RESULTADO MORAL'),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3))),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          Text(local, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('$moralLocal - $moralVisitante', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 20)),
                          Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ]),
                        const SizedBox(height: 8),
                        Text('🧠 $moralDesc', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12), textAlign: TextAlign.center),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _detalleSeccion('INCIDENCIAS'),
                    if (eventos.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Sin incidencias disponibles', style: TextStyle(color: Colors.white38, fontSize: 13)))
                    else
                      ...eventos.where((e) => ['Goal', 'Card', 'subst'].contains(e['type'])).map((e) {
                        final tipo = e['type'];
                        final minuto = "${e['time']['elapsed']}'";
                        final equipo = e['team']['name'] ?? '';
                        String icono = '⚽';
                        String tipoText = 'Gol: ${e['player']['name'] ?? ''}';
                        if (tipo == 'Card') {
                          icono = e['detail'] == 'Yellow Card' ? '🟡' : '🔴';
                          tipoText = '${e['detail'] == 'Yellow Card' ? 'Amarilla' : 'Roja'}: ${e['player']['name'] ?? ''}';
                        } else if (tipo == 'subst') {
                          icono = '🔄';
                          tipoText = 'Entra: ${e['player']['name'] ?? ''} / Sale: ${e['assist']['name'] ?? ''}';
                        }
                        return _incidencia(icono, minuto, tipoText, equipo);
                      }),
                      const SizedBox(height: 16),
                    if (lineups.length >= 2) ...[
                      _detalleSeccion('FORMACIONES'),
                      const SizedBox(height: 8),
                      _buildCancha(lineups, local, visitante),
                      const SizedBox(height: 16),
                    ] else ...[
                      _detalleSeccion('FORMACIONES'),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Sin formaciones disponibles', style: TextStyle(color: Colors.white38, fontSize: 13))),
                    ],
                  ] else ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No hay estadísticas disponibles', style: TextStyle(color: Colors.white38), textAlign: TextAlign.center)),
                  ],
                ] else if (!jugado) ...[
                  _detalleSeccion('HISTORIAL ENTRE AMBOS'),
                  _historialRow(local, '2-1', visitante, 'Ganó local'),
                  _historialRow(visitante, '1-1', local, 'Empate'),
                  _historialRow(local, '0-1', visitante, 'Ganó visitante'),
                  const SizedBox(height: 16),
                  _detalleSeccion('PREDICCION HDF STATS'),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3))),
                    child: const Text('Predicción próximamente', style: TextStyle(color: Color(0xFF00C853), fontSize: 12), textAlign: TextAlign.center),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
 
  Widget _detalleSeccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(titulo, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
    );
  }
 
  Widget _statRow(String stat, String local, String visitante) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(local, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(stat, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
          Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }
 
  Widget _incidencia(String icono, String minuto, String tipo, String equipo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(icono, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(minuto, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: Text(tipo, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
 
  Widget _historialRow(String local, String resultado, String visitante, String ganador) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(child: Text(local, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          Text(resultado, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Text(ganador, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
 
  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2));
  }
  Widget _buildCancha(List<Map<String, dynamic>> lineups, String local, String visitante) {
    final teamLocal = lineups[0];
    final teamVisit = lineups[1];
    final formLocal = teamLocal['formation'] ?? '';
    final formVisit = teamVisit['formation'] ?? '';
    final playersLocal = List<Map<String, dynamic>>.from(teamLocal['startXI'] ?? []);
    final playersVisit = List<Map<String, dynamic>>.from(teamVisit['startXI'] ?? []);

    Map<int, List<Map<String, dynamic>>> groupByPos(List<Map<String, dynamic>> players) {
      final Map<int, List<Map<String, dynamic>>> rows = {};
      for (var p in players) {
        final pos = (p['player']['pos'] as String? ?? 'M');
        int row;
        if (pos == 'G') row = 1;
        else if (pos == 'D') row = 2;
        else if (pos == 'M') row = 3;
        else row = 4;
        rows.putIfAbsent(row, () => []).add(p);
      }
      return rows;
    }

    Widget buildPlayerDot(Map<String, dynamic> p, bool isLocal) {
      final name = (p['player']['name'] ?? '') as String;
      final number = p['player']['number']?.toString() ?? '';
      final shortName = name.split(' ').last;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 2),
        SizedBox(width: 50, child: Text(shortName, style: const TextStyle(color: Colors.white, fontSize: 9), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
      ]);
    }

    Widget buildRows(Map<int, List<Map<String, dynamic>>> rowsMap, bool isLocal, bool invertir) {
      final sortedKeys = rowsMap.keys.toList()..sort();
      if (invertir) sortedKeys.sort((a, b) => b.compareTo(a));
      return Column(mainAxisSize: MainAxisSize.min, children: sortedKeys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: rowsMap[row]!.map((p) => buildPlayerDot(p, isLocal)).toList()),
        );
      }).toList());
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32), width: 2),
      ),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(formVisit, style: const TextStyle(color: Color(0xFF2196F3), fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
        Container(height: 1, color: Colors.white12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: buildRows(groupByPos(playersVisit), false, false)),
        Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.white24),
        Container(width: 60, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24))),
        Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.white24),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: buildRows(groupByPos(playersLocal), true, true)),
        Container(height: 1, color: Colors.white12),
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Text(local, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(formLocal, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
      ]),
    );
  }
}