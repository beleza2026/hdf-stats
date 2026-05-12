import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'racha_model.dart';

class ApiService {
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const int _ligaArgentina = 128;
  static const int _season = 2026;

  /// Temporada principal de la app (Liga Profesional en `getFixture`, etc.).
  static int get temporadaLigaPrincipal => _season;

  /// Agrupa `league.round` de la Liga 128: 1–99 fecha regular, 200 octavos, 300 cuartos, 400 semis, 500 final, 999 otro.
  static int ligaFixtureBucket(String roundRaw) {
    final r = roundRaw.trim().toLowerCase();
    if (r.isEmpty) return 0;
    if (r.contains('round of 16') ||
        r.contains('octavos') ||
        r.contains('1/8') ||
        r.contains('8th finals') ||
        r.contains('8ths') ||
        r.contains('16avos')) {
      return 200;
    }
    if (r.contains('quarter') ||
        r.contains('cuartos') ||
        r.contains('4tos') ||
        r.contains('4°') ||
        r.contains('1/4') ||
        r.contains('1/4 final') ||
        r.contains('1/4 de final') ||
        r.contains('cuarto de final') ||
        r.contains('cuartos de final') ||
        r == 'r8' ||
        (RegExp(r'\br8\b').hasMatch(r) && !r.contains('group')) ||
        RegExp(r'\bround\s+of\s+8\b').hasMatch(r) ||
        RegExp(r'\bqf\b').hasMatch(r) ||
        (RegExp(r'\bround[-\s]*8\b').hasMatch(r) && !r.contains('group')) ||
        RegExp(r'\b4tos?\s*final').hasMatch(r)) {
      return 300;
    }
    if (r.contains('semi')) return 400;
    if (r.contains('final') && !r.contains('season') && !r.contains('quarter')) {
      return 500;
    }
    final reg = RegExp(
      r'(apertura|clausura|regular\s*season)\s*[-–]\s*(\d+)',
      caseSensitive: false,
    );
    final m = reg.firstMatch(r);
    if (m != null) {
      final n = int.tryParse(m.group(2)!) ?? 0;
      return n.clamp(0, 99);
    }
    final fe = RegExp(r'\bfecha\s*(\d+)', caseSensitive: false).firstMatch(r);
    if (fe != null) {
      return (int.tryParse(fe.group(1)!) ?? 0).clamp(0, 99);
    }
    final tail = RegExp(r'[-–]\s*(\d+)\s*$').firstMatch(r);
    if (tail != null) {
      final v = int.tryParse(tail.group(1)!) ?? 0;
      if (v >= 1 && v <= 38) return v;
    }
    return 999;
  }

  /// Misma nómina que en copas (vivo): partidos de copa se filtran a estos clubes.
  static const Set<String> _equiposArgTablaDT = {
    '451', '435', '436', '453', '460', '445', '438', '440', '450', '434', '446', '449',
    '1064', '452', '441', '456', '457', '463', '2432',
  };

  /// DT con al menos un partido (liga/copa) en esta ventana se considera en actividad.
  static const int dtVentanaActividadDias = 45;

  /// Solo partidos en esta ventana entran al pipeline de lineups (evita cientos de requests y cuelgues).
  static const int _dtTablaFixturesLookbackDays = 200;

  /// Tope de seguridad de partidos a procesar (los más recientes tras ordenar).
  static const int _dtTablaMaxFixturesLineups = 420;

  static String _ymdApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, String> get _headers => {
    'x-apisports-key': _apiKey,
  };

  // ─── CACHE GLOBAL ────────────────────────────────────────────────
  // Standings y fixtures se comparten entre todos los métodos.
  // Solo se hace 1 request por sesión, sin importar cuántos métodos lo pidan.
  static Future<dynamic>? _standingsFuture;
  static Future<List>? _fixturesFuture;
  static Future<Map<String, List<Map<String, dynamic>>>>? _tiemposFuture;
  static List<RachaEquipo>? _rachasCache;
  static Future<List>? _fixturesPrevFuture;
  static final Map<int, List<Map<String, dynamic>>> _fixtureEventsCache = {};
  static final Map<int, List<Map<String, dynamic>>> _fixturePlayersCache = {};

  static void clearCache() {
    _standingsFuture = null;
    _fixturesFuture = null;
    _tiemposFuture = null;
    _rachasCache = null;
    _fixtureEventsCache.clear();
    _fixturePlayersCache.clear();
    _prediccionesCache = null;
    _prediccionesCacheTime = null;
    _tablaDTsCache = null;
    _tablaPosesionCache = null;
    _tablaPosesionCacheTime = null;
    _fixturesPrevFuture = null;
    _tablasCache = null;
    _fixtureFullListCache = null;
    _fixtureFullListCacheTime = null;
    _fixtureFullListInFlight = null;
    _indiceMatchgolCache = null;
    _indiceMatchgolCacheTime = null;
    _indiceMatchgolInFlight = null;
    _tablaMoralResultCache = null;
    _tablaMoralResultCacheTime = null;
    _tablaMoralInFlight = null;
    _ultimos5Cache.clear();
    _ultimos5CacheTime.clear();
    _ultimos5InFlight.clear();
    _tablaDTsEpoch++;
  }

  // ─── Caché corta + una sola petición en vuelo (evita spam al cambiar de pestaña) ───
  static List<Map<String, dynamic>>? _fixtureFullListCache;
  static DateTime? _fixtureFullListCacheTime;
  static Future<List<Map<String, dynamic>>>? _fixtureFullListInFlight;

  static Map<String, dynamic>? _indiceMatchgolCache;
  static DateTime? _indiceMatchgolCacheTime;
  static Future<Map<String, dynamic>>? _indiceMatchgolInFlight;

  static Map<String, List<Map<String, dynamic>>>? _tablaMoralResultCache;
  static DateTime? _tablaMoralResultCacheTime;
  static Future<Map<String, List<Map<String, dynamic>>>>? _tablaMoralInFlight;

  static final Map<int, List<Map<String, dynamic>>> _ultimos5Cache = {};
  static final Map<int, DateTime> _ultimos5CacheTime = {};
  static final Map<int, Future<List<Map<String, dynamic>>>> _ultimos5InFlight = {};

  static Future<dynamic> _getStandingsData() {
    _standingsFuture ??= http.get(
      Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
      headers: _headers,
    ).then((r) => r.statusCode == 200 ? jsonDecode(r.body) : null);
    return _standingsFuture!;
  }

  /// IDs de clubes en la Liga Profesional (todos los grupos del standings).
  static Future<Set<int>> _teamIdsLigaProfesional() async {
    try {
      final data = await _getStandingsData();
      if (data == null) return {};
      final standings = data['response']?[0]?['league']?['standings'] as List?;
      if (standings == null) return {};
      final ids = <int>{};
      for (final group in standings) {
        final zona = group as List;
        for (final row in zona) {
          final m = row as Map<String, dynamic>;
          final tid = _idFromDynamic(m['team']?['id']);
          if (tid != null) ids.add(tid);
        }
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  static Future<List> _getFixturesData() {
    _fixturesFuture = http.get(
    Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&status=FT'),
      headers: _headers,
    ).then((r) => r.statusCode == 200
        ? (jsonDecode(r.body)['response'] as List)
        : <dynamic>[]);
    return _fixturesFuture!;
  }
  static Future<List<dynamic>> _getFixturesAllData() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 55));
      if (r.statusCode != 200) return [];
      final raw = jsonDecode(r.body)['response'];
      return raw is List ? raw : [];
    } catch (_) {
      return [];
    }
  }

  /// Liga Prof.: partidos en ventana reciente (preferido para tabla DT).
  static Future<List<dynamic>> _getFixturesLigaVentanaParaDTs(String from, String to) async {
    try {
      final r = await http
          .get(
            Uri.parse(
              '$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&from=$from&to=$to',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 55));
      if (r.statusCode != 200) return [];
      final raw = jsonDecode(r.body)['response'];
      return raw is List ? raw : [];
    } catch (_) {
      return [];
    }
  }
  // ─────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getPartidosHoy() async {
  final hoy = DateTime.now().toLocal();
  final fecha = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
  final leagues = [_ligaArgentina, 13, 11]; // Liga + Libertadores + Sudamericana
  final List<Map<String, dynamic>> todos = [];
  try {
    for (final league in leagues) {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$league&season=$_season&date=$fecha&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        // Para Copas, solo equipos argentinos
        if (league != _ligaArgentina) {
          final argIds = ['451','435','436','453','460','445','438','440','450','434','446','449','1064','452','441','456','457','463','2432'];
          todos.addAll(fixtures
            .map((f) => f as Map<String, dynamic>)
            .where((f) {
              final hId = f['teams']['home']['id'].toString();
              final aId = f['teams']['away']['id'].toString();
              return argIds.contains(hId) || argIds.contains(aId);
            }).toList());
        } else {
          todos.addAll(fixtures.map((f) => f as Map<String, dynamic>).toList());
        }
      }
    }
    return todos;
  } catch (e) {
    return [];
  }
}

  static DateTime _dateOnlyLocal(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Sábado de la semana calendario que contiene [now] (hora local del dispositivo).
  static DateTime _sabadoSemanaContiene(DateTime now) {
    final d = _dateOnlyLocal(now);
    final diasAtras = (d.weekday - DateTime.saturday + 7) % 7;
    return d.subtract(Duration(days: diasAtras));
  }

  /// Partidos **finalizados** de Liga Profesional entre el sábado y el domingo de esa semana,
  /// con ganador y etiqueta de fecha (p. ej. R8) según `league.round` de la API.
  ///
  /// Devuelve: `titulo`, `items` (lista de mapas con localName, awayName, gh, ga, winnerName, round),
  /// `sabado`, `domingo` (yyyy-MM-dd).
  static Future<Map<String, dynamic>> getLigaArgFinDeSemanaGanadores() async {
    final now = DateTime.now();
    final sab = _sabadoSemanaContiene(now);
    final dom = sab.add(const Duration(days: 1));
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final from = ymd(sab);
    final to = ymd(dom);

    final porId = <int, Map<String, dynamic>>{};
    for (final season in [_season, _season - 1]) {
      try {
        final uri = Uri.parse(
          '$_baseUrl/fixtures?league=$_ligaArgentina&season=$season&from=$from&to=$to&timezone=America/Argentina/Buenos_Aires',
        );
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final list = data['response'] as List? ?? [];
        for (final raw in list) {
          final f = raw as Map<String, dynamic>;
          final id = f['fixture']?['id'];
          final fid = id is int ? id : int.tryParse('$id') ?? 0;
          if (fid <= 0) continue;
          porId[fid] = f;
        }
      } catch (_) {}
    }

    int? numeroFecha(String? round) {
      if (round == null || round.isEmpty) return null;
      final m = RegExp(r'(\d+)\s*$').firstMatch(round.trim());
      return m != null ? int.tryParse(m.group(1)!) : null;
    }

    String? roundMuestra;
    final items = <Map<String, dynamic>>[];
    for (final f in porId.values) {
      final st = f['fixture']?['status']?['short'] as String? ?? '';
      if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
      final teams = f['teams'] as Map<String, dynamic>?;
      final goals = f['goals'] as Map<String, dynamic>?;
      if (teams == null || goals == null) continue;
      final home = teams['home'] as Map<String, dynamic>?;
      final away = teams['away'] as Map<String, dynamic>?;
      if (home == null || away == null) continue;
      final gh = (goals['home'] as num?)?.toInt() ?? 0;
      final ga = (goals['away'] as num?)?.toInt() ?? 0;
      final localName = home['name'] as String? ?? '';
      final awayName = away['name'] as String? ?? '';
      String winnerName;
      if (gh > ga) {
        winnerName = localName;
      } else if (ga > gh) {
        winnerName = awayName;
      } else {
        winnerName = 'Empate';
      }
      final round = f['league']?['round'] as String? ?? '';
      if (round.isNotEmpty) roundMuestra ??= round;
      items.add({
        'localName': localName,
        'awayName': awayName,
        'gh': gh,
        'ga': ga,
        'winnerName': winnerName,
        'empate': gh == ga,
        'round': round,
        'fecha': f['fixture']?['date'] as String? ?? '',
      });
    }
    items.sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));

    final n = numeroFecha(roundMuestra);
    final titulo = n != null
        ? 'LIGA PROFESIONAL — FECHA R$n — GANADORES (sáb.–dom.)'
        : 'LIGA PROFESIONAL — GANADORES FIN DE SEMANA (sáb.–dom.)';

    return {
      'titulo': titulo,
      'round': roundMuestra ?? '',
      'numeroFecha': n,
      'items': items,
      'sabado': from,
      'domingo': to,
    };
  }

  static Map<String, List<Map<String, dynamic>>>? _tablasCache;

  static int? _idFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static Future<Map<String, List<Map<String, dynamic>>>> getTablas() async {
    try {
      final data = await _getStandingsData();
      if (data != null) {
        final standings = data['response'][0]['league']['standings'] as List;
        Map<String, List<Map<String, dynamic>>> zonas = {};
        for (int i = 0; i < standings.length && i < 2; i++) {
          final zona = standings[i] as List;
          zonas['Zona ${String.fromCharCode(65 + i)}'] =
              zona.map((e) => e as Map<String, dynamic>).toList();
        }
        if (zonas.isNotEmpty) {
          // Reinyectar equipos que desaparecen mientras juegan (API los saca del standings en vivo)
          if (_tablasCache != null) {
            for (final zonaKey in zonas.keys) {
              final cached = _tablasCache![zonaKey] ?? [];
              final nuevosIds = zonas[zonaKey]!
                  .map((e) => _idFromDynamic((e['team'] as Map<String, dynamic>?)?['id']))
                  .whereType<int>()
                  .toSet();
              for (final eq in cached) {
                final tid = _idFromDynamic((eq['team'] as Map<String, dynamic>?)?['id']);
                if (tid != null && !nuevosIds.contains(tid)) zonas[zonaKey]!.add(eq);
              }
              int pts(Map<String, dynamic> x) =>
                  (x['points'] is num) ? (x['points'] as num).toInt() : int.tryParse('${x['points']}') ?? 0;
              int gd(Map<String, dynamic> x) {
                final g = x['goalsDiff'];
                if (g is num) return g.toInt();
                return int.tryParse('$g') ?? 0;
              }
              zonas[zonaKey]!.sort((a, b) {
                final d = pts(b).compareTo(pts(a));
                if (d != 0) return d;
                return gd(b).compareTo(gd(a));
              });
            }
          }
          _tablasCache = Map.from(zonas.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v))));
          return zonas;
        }
      }
      return _tablasCache ?? {};
    } catch (e) {
      return _tablasCache ?? {};
    }
  }

  static Future<Map<String, List<Map<String, dynamic>>>> getTablasAnualYPromedios() async {
    try {
      final data = await _getStandingsData();
      if (data != null) {
        final standings = data['response'][0]['league']['standings'] as List;
        Map<String, List<Map<String, dynamic>>> result = {};
        for (final group in standings) {
          final zona = group as List;
          if (zona.isEmpty) continue;
          final sample = zona[0] as Map<String, dynamic>;
          final groupStr = (sample['group'] as String? ?? '').toLowerCase();
          if (groupStr.contains('anual')) {
            result['Anual'] = zona.map((e) => e as Map<String, dynamic>).toList();
          } else if (groupStr.contains('promedios')) {
            result['Promedios'] = zona.map((e) => e as Map<String, dynamic>).toList();
          }
        }
        return result;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<Map<String, List<Map<String, dynamic>>>> getTablasTiempos() {
    _tiemposFuture ??= _computeTablasTiempos();
    return _tiemposFuture!;
  }

  static Future<Map<String, List<Map<String, dynamic>>>> _computeTablasTiempos() async {
    try {
      // Fetch dedicado — no usa caché compartido de _fixturesFuture
      final resF = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (resF.statusCode != 200) return {};
      final dataFixturesList = (jsonDecode(resF.body)['response'] as List);
      final dataTablas = await _getStandingsData();
      if (dataFixturesList.isNotEmpty && dataTablas != null) {
        final fixtures = dataFixturesList;
        final standings = dataTablas['response'][0]['league']['standings'] as List;

        // Mapear team ID -> zona y nombre
        Map<int, String> idZona = {};
        Map<int, String> idNombre = {};
        for (int i = 0; i < standings.length; i++) {
          final equipos = standings[i] as List;
          if (equipos.isEmpty) continue;
          final group = equipos[0]['group'] as String? ?? '';
          final zona = group.contains('Group A') ? 'Zona A' : group.contains('Group B') ? 'Zona B' : null;
          if (zona == null) continue;
          for (var eq in equipos) {
            final id = eq['team']['id'] as int;
            idZona[id] = zona;
            idNombre[id] = eq['team']['name'] as String;
          }
        }

        // Inicializar stats por zona
        Map<String, Map<int, Map<String, dynamic>>> zonas = {
          'Zona A': {},
          'Zona B': {},
        };

        void initEquipo(String zona, int id) {
          zonas[zona]!.putIfAbsent(id, () => {
            'nombre': idNombre[id] ?? '',
            'pj1': 0, 'g1': 0, 'e1': 0, 'p1': 0, 'pts1': 0,
            'pj2': 0, 'g2': 0, 'e2': 0, 'p2': 0, 'pts2': 0,
          });
        }

        for (var f in fixtures) {
          final m = f as Map<String, dynamic>;
          // Igual que tabla moral / condición local-visita: solo fase por fechas, hasta antes de playoffs.
          if (!_fixtureCuentaParaTablaMoral(m)) continue;
          final status = f['fixture']?['status']?['short'] as String? ?? '';
          if (status != 'FT' && status != 'AET' && status != 'PEN') continue;
          final ft = f['score']?['fulltime'];
          if (ft == null || ft['home'] == null || ft['away'] == null) continue;

          final homeId = f['teams']['home']['id'] as int;
          final awayId = f['teams']['away']['id'] as int;
          final zonaHome = idZona[homeId];
          final zonaAway = idZona[awayId];
          if (zonaHome == null && zonaAway == null) continue;

          final ht = f['score']?['halftime'];
          final htValido = ht != null && ht['home'] != null && ht['away'] != null;
          final htH = htValido ? (ht['home'] as num).toInt() : 0;
          final htA = htValido ? (ht['away'] as num).toInt() : 0;
          final ftH = (ft['home'] as num).toInt();
          final ftA = (ft['away'] as num).toInt();
          final stH = ftH - htH;
          final stA = ftA - htA;

          // Registrar equipo LOCAL en su zona
          if (zonaHome != null) {
            final z = zonaHome;
            initEquipo(z, homeId);
            final eq = zonas[z]![homeId]!;
            // pj1 siempre incrementa (usa 0-0 si no hay datos HT)
            eq['pj1'] = (eq['pj1'] as int) + 1;
            if (htH > htA)      { eq['g1'] = (eq['g1'] as int)+1; eq['pts1'] = (eq['pts1'] as int)+3; }
            else if (htH == htA){ eq['e1'] = (eq['e1'] as int)+1; eq['pts1'] = (eq['pts1'] as int)+1; }
            else                { eq['p1'] = (eq['p1'] as int)+1; }
            eq['pj2'] = (eq['pj2'] as int) + 1;
            if (stH > stA)      { eq['g2'] = (eq['g2'] as int)+1; eq['pts2'] = (eq['pts2'] as int)+3; }
            else if (stH == stA){ eq['e2'] = (eq['e2'] as int)+1; eq['pts2'] = (eq['pts2'] as int)+1; }
            else                { eq['p2'] = (eq['p2'] as int)+1; }
          }

          // Registrar equipo VISITANTE en su zona
          if (zonaAway != null) {
            final z = zonaAway;
            initEquipo(z, awayId);
            final eq = zonas[z]![awayId]!;
            // pj1 siempre incrementa (usa 0-0 si no hay datos HT)
            eq['pj1'] = (eq['pj1'] as int) + 1;
            if (htA > htH)      { eq['g1'] = (eq['g1'] as int)+1; eq['pts1'] = (eq['pts1'] as int)+3; }
            else if (htH == htA){ eq['e1'] = (eq['e1'] as int)+1; eq['pts1'] = (eq['pts1'] as int)+1; }
            else                { eq['p1'] = (eq['p1'] as int)+1; }
            eq['pj2'] = (eq['pj2'] as int) + 1;
            if (stA > stH)      { eq['g2'] = (eq['g2'] as int)+1; eq['pts2'] = (eq['pts2'] as int)+3; }
            else if (stH == stA){ eq['e2'] = (eq['e2'] as int)+1; eq['pts2'] = (eq['pts2'] as int)+1; }
            else                { eq['p2'] = (eq['p2'] as int)+1; }
          }
        }

        return {
          'Zona A': zonas['Zona A']!.values.toList(),
          'Zona B': zonas['Zona B']!.values.toList(),
        };
      }
      return {};
    } catch (e) {
      return {};
    }
  }
  static Future<List<Map<String, dynamic>>> getHeadToHead(int homeId, int awayId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures/headtohead?h2h=$homeId-$awayId&last=10'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        return fixtures.map((f) => f as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  static Future<List<Map<String, dynamic>>> getAsistencias() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topassists?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assists = data['response'] as List;
        return assists.map((a) => a as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getGoleadores() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topscorers?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final scorers = data['response'] as List;
        return scorers.map((s) => s as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getFixture() async {
    const ttl = Duration(minutes: 2);
    final now = DateTime.now();
    if (_fixtureFullListCache != null &&
        _fixtureFullListCacheTime != null &&
        now.difference(_fixtureFullListCacheTime!) < ttl) {
      return List<Map<String, dynamic>>.from(_fixtureFullListCache!);
    }
    if (_fixtureFullListInFlight != null) {
      return List<Map<String, dynamic>>.from(await _fixtureFullListInFlight!);
    }
    _fixtureFullListInFlight = _getFixtureInternal().then((list) {
      _fixtureFullListCache = list;
      _fixtureFullListCacheTime = DateTime.now();
      return list;
    }).whenComplete(() => _fixtureFullListInFlight = null);
    return List<Map<String, dynamic>>.from(await _fixtureFullListInFlight!);
  }

  static Future<List<Map<String, dynamic>>> _getFixtureInternal() async {
    try {
      Future<List<Map<String, dynamic>>> _fetchFixturesPaginated(
          int season, String query) async {
        final acc = <Map<String, dynamic>>[];
        var page = 1;
        while (true) {
          try {
            final uri = page == 1
                ? Uri.parse(
                    '$_baseUrl/fixtures?league=$_ligaArgentina&season=$season$query&timezone=America/Argentina/Buenos_Aires')
                : Uri.parse(
                    '$_baseUrl/fixtures?league=$_ligaArgentina&season=$season$query&timezone=America/Argentina/Buenos_Aires&page=$page');
            final response = await http.get(uri, headers: _headers);
            if (response.statusCode != 200) break;
            final decoded = jsonDecode(response.body);
            if (decoded is! Map<String, dynamic>) break;
            final data = decoded;
            final errs = data['errors'];
            if (errs is Map && errs.isNotEmpty) break;
            final fixtures = data['response'] as List? ?? [];
            for (final f in fixtures) {
              acc.add(f as Map<String, dynamic>);
            }
            final paging = data['paging'];
            final totalPages = paging is Map
                ? (paging['total'] as num?)?.toInt() ?? 1
                : 1;
            if (page >= totalPages || fixtures.isEmpty) break;
            page++;
          } catch (_) {
            break;
          }
        }
        return acc;
      }

      Future<List<Map<String, dynamic>>> _fetchFixtures(int season, String query) async {
        try {
          final response = await http.get(
            Uri.parse(
                '$_baseUrl/fixtures?league=$_ligaArgentina&season=$season$query&timezone=America/Argentina/Buenos_Aires'),
            headers: _headers,
          );
          if (response.statusCode != 200) return [];
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) return [];
          final fixtures = (decoded['response'] as List? ?? []);
          return fixtures.map((f) => f as Map<String, dynamic>).toList();
        } catch (_) {
          return [];
        }
      }

      final Map<dynamic, Map<String, dynamic>> porFixtureId = {};
      // Solo la temporada configurada: mezclar 2025 completo traía el calendario del año pasado.
      for (final season in [_season]) {
        // Primera oleada en paralelo (antes todo en serie → muy lento al armar el fixture).
        final wave1 = await Future.wait<List<Map<String, dynamic>>>([
          _fetchFixturesPaginated(season, ''),
          _fetchFixtures(season, '&status=NS'),
          _fetchFixtures(season, '&next=50'),
          _fetchFixtures(season, '&status=NS&round=Round%20of%2016'),
          _fetchFixtures(season, '&status=NS&round=Octavos%20de%20Final'),
        ]);
        final allFixtures = wave1[0];
        final nsFixtures = wave1[1];
        final proximos = wave1[2];
        final koR16NsEn = wave1[3];
        final koR16NsEs = wave1[4];

        // ── Cuartos (R8): MISMO MODELO que R16 + refuerzos FT/TBD/LIVE (a veces el dump no los lista).
        //    Rondas genéricas API (inglés / español / alias) + Apertura/Clausura como en el fixture oficial.
        Future<List<Map<String, dynamic>>> koR8Layer(
            String status, List<String> rounds) async {
          final acc = <Map<String, dynamic>>[];
          for (final rd in rounds) {
            acc.addAll(await _fetchFixtures(
                season, '&status=$status&round=${Uri.encodeComponent(rd)}'));
            await Future.delayed(const Duration(milliseconds: 70));
          }
          return acc;
        }

        const r8Statuses = ['NS', 'TBD', 'FT', 'LIVE'];
        const r8RoundsGeneric = [
          'Round of 8',
          'Cuartos de Final',
          'Quarter-finals',
        ];
        const r8RoundsFase = [
          'Apertura - Round of 8',
          'Clausura - Round of 8',
          'Apertura - Quarter-finals',
          'Clausura - Quarter-finals',
          'Apertura - Cuartos de Final',
          'Clausura - Cuartos de Final',
          '1st Phase - Quarter-finals',
        ];

        final koR8 = <Map<String, dynamic>>[];
        for (final st in r8Statuses) {
          koR8.addAll(await koR8Layer(st, r8RoundsGeneric));
          koR8.addAll(await koR8Layer(st, r8RoundsFase));
        }
        // Sin filtrar por status (por si la API solo devuelve algunos cruces así).
        for (final rd in r8RoundsFase) {
          koR8.addAll(await _fetchFixtures(
              season, '&round=${Uri.encodeComponent(rd)}'));
          await Future.delayed(const Duration(milliseconds: 70));
        }

        for (final fixture in [
          ...allFixtures,
          ...nsFixtures,
          ...koR16NsEn,
          ...koR16NsEs,
          ...proximos,
          ...koR8,
        ]) {
          final fixtureData = fixture['fixture'] as Map<String, dynamic>?;
          final fixtureId = fixtureData?['id'];
          if (fixtureId == null) continue;
          porFixtureId[fixtureId] = fixture;
        }
      }
      return porFixtureId.values.toList();
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getEstadisticasPartido(int fixtureId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures/statistics?fixture=$fixtureId'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static int _golesEncajadosEquipoEnFixture(Map<String, dynamic> f, int teamId) {
    final homeIdRaw = f['teams']?['home']?['id'];
    final awayIdRaw = f['teams']?['away']?['id'];
    final hid = homeIdRaw is int ? homeIdRaw : int.tryParse('$homeIdRaw') ?? 0;
    final aid = awayIdRaw is int ? awayIdRaw : int.tryParse('$awayIdRaw') ?? 0;
    final gh = (f['goals']?['home'] as num?)?.toInt();
    final ga = (f['goals']?['away'] as num?)?.toInt();
    if (gh == null || ga == null) return -1;
    if (teamId == hid) return ga;
    if (teamId == aid) return gh;
    return -1;
  }

  static int? _oponenteTeamId(Map<String, dynamic> f, int teamId) {
    final homeIdRaw = f['teams']?['home']?['id'];
    final awayIdRaw = f['teams']?['away']?['id'];
    final hid =
        homeIdRaw is int ? homeIdRaw : int.tryParse('$homeIdRaw') ?? 0;
    final aid =
        awayIdRaw is int ? awayIdRaw : int.tryParse('$awayIdRaw') ?? 0;
    if (teamId == hid) return aid;
    if (teamId == aid) return hid;
    return null;
  }

  /// Minuto efectivo del último gol que le hicieron al equipo [teamId] (rival [opponentTeamId] anota).
  /// Usa `elapsed` + `extra` del evento (p. ej. 90+4 → 94).
  static int? _ultimoMinutoGolRecibido(
      List<Map<String, dynamic>> events, int opponentTeamId) {
    var best = -1;
    for (final e in events) {
      if ((e['type'] as String?) != 'Goal') continue;
      final tidRaw = e['team']?['id'];
      final tid = tidRaw is int ? tidRaw : int.tryParse('$tidRaw') ?? 0;
      if (tid != opponentTeamId) continue;
      final t = e['time'];
      if (t is! Map) continue;
      final elRaw = t['elapsed'];
      final exRaw = t['extra'];
      final el = elRaw is int ? elRaw : (elRaw is num ? elRaw.toInt() : 0);
      final ex = exRaw is int ? exRaw : (exRaw is num ? exRaw.toInt() : 0);
      final score = el + ex;
      if (score > best) best = score;
    }
    if (best < 0) return null;
    return best;
  }

  /// Último gol del rival en [enteredAt, leftAt] (minutos de partido del arquero en cancha).
  static int? _ultimoMinutoGolRecibidoEnVentana(
    List<Map<String, dynamic>> events,
    int opponentTeamId,
    int enteredAt,
    int leftAt,
  ) {
    var best = -1;
    for (final e in events) {
      if ((e['type'] as String?) != 'Goal') continue;
      final tidRaw = e['team']?['id'];
      final tid = tidRaw is int ? tidRaw : int.tryParse('$tidRaw') ?? 0;
      if (tid != opponentTeamId) continue;
      final t = e['time'];
      if (t is! Map) continue;
      final elRaw = t['elapsed'];
      final exRaw = t['extra'];
      final el = elRaw is int ? elRaw : (elRaw is num ? elRaw.toInt() : 0);
      final ex = exRaw is int ? exRaw : (exRaw is num ? exRaw.toInt() : 0);
      final g = el + ex;
      if (g < enteredAt || g > leftAt) continue;
      if (g > best) best = g;
    }
    if (best < 0) return null;
    return best;
  }

  static Future<List<Map<String, dynamic>>> _eventosFixtureCached(
      int fixtureId) async {
    if (fixtureId <= 0) return [];
    final hit = _fixtureEventsCache[fixtureId];
    if (hit != null) return hit;
    final list = await getEventosPartido(fixtureId);
    _fixtureEventsCache[fixtureId] = list;
    return list;
  }

  static Future<List<Map<String, dynamic>>> _jugadoresFixtureCached(
      int fixtureId) async {
    if (fixtureId <= 0) return [];
    final hit = _fixturePlayersCache[fixtureId];
    if (hit != null) return hit;
    final list = await getPlayersPartido(fixtureId.toString());
    _fixturePlayersCache[fixtureId] = list;
    return list;
  }

  static Future<Map<String, dynamic>?> _filaArqueroEnPartido(
    int fixtureId,
    int teamId,
    int playerId,
  ) async {
    if (fixtureId <= 0 || teamId <= 0 || playerId <= 0) return null;
    final lista = await _jugadoresFixtureCached(fixtureId);
    for (final j in lista) {
      final pid = j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0;
      final tid =
          j['equipoId'] is int ? j['equipoId'] as int : int.tryParse('${j['equipoId']}') ?? 0;
      if (pid == playerId && tid == teamId) return j;
    }
    return null;
  }

  static int _minutosFixtureParaRacha(Map<String, dynamic> f) {
    final status = f['fixture']?['status']?['short'] as String? ?? '';
    final elapsedRaw = f['fixture']?['status']?['elapsed'];
    final el = elapsedRaw is int
        ? elapsedRaw
        : (elapsedRaw is num ? elapsedRaw.toInt() : 0);
    switch (status) {
      case 'FT':
        return el > 0 ? el : 90;
      case 'AET':
        return el > 0 ? el : 120;
      case 'PEN':
        return el > 0 ? el : 120;
      case 'AWD':
      case 'WO':
        return 90;
      case '1H':
      case 'HT':
      case '2H':
      case 'ET':
      case 'BT':
      case 'INT':
      case 'LIVE':
        return el;
      default:
        if (status == 'NS' || status == 'TBD' || status == 'PST' || status == 'CANC') {
          return 0;
        }
        return el > 0 ? el : 90;
    }
  }

  /// Partidos del equipo en Liga Prof. (128), temporada actual, más reciente primero.
  ///
  /// `fixtures?player=` devuelve error en este plan de API ("Player field do not exist");
  /// `team` + `league` sí funciona. Primer GET **sin** `&page=` (con timezone, `page=1` rompe).
  static Future<List<Map<String, dynamic>>> _fixturesTeamLigaArgPaginated(
      int teamId) async {
    if (teamId <= 0) return [];
    final acc = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final uri = page == 1
          ? Uri.parse(
              '$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&team=$teamId&timezone=America/Argentina/Buenos_Aires')
          : Uri.parse(
              '$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&team=$teamId&timezone=America/Argentina/Buenos_Aires&page=$page');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) break;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final errs = data['errors'];
      if (errs is Map && errs.isNotEmpty) break;
      final fixtures = data['response'] as List? ?? [];
      for (final raw in fixtures) {
        acc.add(raw as Map<String, dynamic>);
      }
      final paging = data['paging'];
      final totalPages = paging is Map
          ? (paging['total'] as num?)?.toInt() ?? 1
          : 1;
      if (page >= totalPages || fixtures.isEmpty) break;
      page++;
    }
    acc.sort((a, b) {
      final da = DateTime.tryParse(a['fixture']?['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['fixture']?['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final c = db.compareTo(da);
      if (c != 0) return c;
      final ida = a['fixture']?['id'];
      final idb = b['fixture']?['id'];
      final ia = ida is int ? ida : int.tryParse('$ida') ?? 0;
      final ib = idb is int ? idb : int.tryParse('$idb') ?? 0;
      return ib.compareTo(ia);
    });
    return acc;
  }

  /// Minutos sin gol **solo con este arquero en cancha** (`fixtures/players`: minutos,
  /// titular/suplente). Partidos sin jugar no suman ni cortan. Goles fuera de su ventana
  /// (otro arquero) no cuentan para cortar su racha en ese partido.
  static Future<int> _rachaMinutosSinGolArqueroLiga(
      int playerId, int teamId) async {
    final fixtures = await _fixturesTeamLigaArgPaginated(teamId);
    if (fixtures.isEmpty) return 0;
    var sum = 0;
    for (final f in fixtures) {
      final homeIdRaw = f['teams']?['home']?['id'];
      final awayIdRaw = f['teams']?['away']?['id'];
      final hid =
          homeIdRaw is int ? homeIdRaw : int.tryParse('$homeIdRaw') ?? 0;
      final aid =
          awayIdRaw is int ? awayIdRaw : int.tryParse('$awayIdRaw') ?? 0;
      if (teamId != hid && teamId != aid) continue;

      final status = f['fixture']?['status']?['short'] as String? ?? '';
      if (status == 'PST' || status == 'CANC') continue;
      if (status == 'NS' || status == 'TBD') continue;

      final fidRaw = f['fixture']?['id'];
      final fid = fidRaw is int ? fidRaw : int.tryParse('$fidRaw') ?? 0;

      final fila = await _filaArqueroEnPartido(fid, teamId, playerId);
      if (fila == null) continue;

      final pos = (fila['posicion'] as String? ?? '').toUpperCase();
      if (pos != 'G' && pos != 'GOALKEEPER') continue;

      final minJug = (fila['minutos'] as num?)?.toInt() ?? 0;
      if (minJug <= 0) continue;

      final total = _minutosFixtureParaRacha(f);
      final supl = fila['suplente'] == true;
      final enteredAt =
          supl ? (total - minJug).clamp(0, total) : 0;
      final leftAt = (enteredAt + minJug).clamp(0, total);

      final gc = _golesEncajadosEquipoEnFixture(f, teamId);
      if (gc < 0) continue;

      final opp = _oponenteTeamId(f, teamId);
      if (opp == null) continue;

      if (gc == 0) {
        sum += minJug;
        continue;
      }

      final events = await _eventosFixtureCached(fid);
      final ultimoEnVentana =
          _ultimoMinutoGolRecibidoEnVentana(events, opp, enteredAt, leftAt);
      if (ultimoEnVentana == null) {
        sum += minJug;
        continue;
      }

      final resto = (leftAt - ultimoEnVentana).clamp(0, leftAt);
      sum += resto;
      break;
    }
    return sum;
  }

  static Future<List<Map<String, dynamic>>> getArqueros() async {
    try {
      // 1. Traer equipos desde standings
      final standingsData = await _getStandingsData();
      if (standingsData == null) return [];
      final grupos = standingsData['response']?[0]?['league']?['standings'] as List? ?? [];
      final Set<int> teamIds = {};
      for (var grupo in grupos) {
        for (var equipo in (grupo as List)) {
          final id = equipo['team']?['id'] as int?;
          if (id != null) teamIds.add(id);
        }
      }

      // 2. Requests en lotes de 5 con delay para evitar rate limiting
      var arqueros = <Map<String, dynamic>>[];
      final teamList = teamIds.toList();
      const loteSize = 5;
      for (int i = 0; i < teamList.length; i += loteSize) {
        final lote = teamList.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((teamId) async {
          try {
            int page = 1;
            while (true) {
              final res = await http.get(
                Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&team=$teamId&page=$page'),
                headers: _headers,
              );
              if (res.statusCode != 200) break;
              final data = jsonDecode(res.body);
              final players = data['response'] as List? ?? [];
              for (var p in players) {
                final stats = (p['statistics'] as List?)?.first;
                if (stats == null) continue;
                final pos = stats['games']?['position'] as String? ?? '';
                if (pos != 'Goalkeeper' && pos != 'G') continue;
                final played = stats['games']?['appearences'] as int? ?? 0;
                if (played == 0) continue;
                arqueros.add(Map<String, dynamic>.from(p));
              }
              final totalPages = data['paging']?['total'] as int? ?? 1;
              if (page >= totalPages) break;
              page++;
            }
          } catch (_) {}
        }));
        // Pausa corta entre lotes (antes 300 ms; demasiado lento en UI).
        if (i + loteSize < teamList.length) {
          await Future.delayed(const Duration(milliseconds: 90));
        }
      }

      // 3. Un jugador puede repetirse entre páginas/equipos; quedarnos con una fila por id.
      final byPlayerId = <int, Map<String, dynamic>>{};
      for (var a in arqueros) {
        final rawId = a['player']?['id'];
        final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
        if (id <= 0) continue;
        byPlayerId[id] = a;
      }
      arqueros = byPlayerId.values.toList();

      // 4. Promedio temporada: minutos jugados (capados) / goles encajados — no es "racha" ni minutos seguidos sin gol.
      for (var a in arqueros) {
        final stats = a['statistics'][0];
        final conceded = (stats['goals']?['conceded'] as num?)?.toInt() ?? 0;
        final apps = (stats['games']?['appearences'] as num?)?.toInt() ?? 0;
        var minutos = (stats['games']?['minutes'] as num?)?.toInt() ?? 0;
        final partidosParaTope = apps <= 0 ? 1 : apps;
        final maxRazonable = 102 * partidosParaTope;
        if (minutos > maxRazonable) minutos = maxRazonable;
        a['minutosCapArq'] = minutos;
        a['minPorGolRecibido'] = conceded > 0 ? (minutos / conceded).round() : null;
        // Compat. UI `main.dart` pestaña MIN/GOL (antes en api vieja era min/concedidos o minutos si 0 GC).
        a['minutosSinGol'] = conceded > 0 ? (minutos / conceded).round() : minutos;
      }

      // 5. Racha Liga: minutos sin gol solo con este arquero en cancha (eventos + fixtures/players).
      const rachaLoteSize = 4;
      for (int i = 0; i < arqueros.length; i += rachaLoteSize) {
        final lote = arqueros.skip(i).take(rachaLoteSize).toList();
        await Future.wait(lote.map((a) async {
          final rawPid = a['player']?['id'];
          final pid = rawPid is int ? rawPid : int.tryParse('$rawPid') ?? 0;
          final rawTid = a['statistics']?[0]?['team']?['id'];
          final tid = rawTid is int ? rawTid : int.tryParse('$rawTid') ?? 0;
          if (pid <= 0 || tid <= 0) {
            a['rachaMinSinGolLiga'] = 0;
            return;
          }
          try {
            a['rachaMinSinGolLiga'] =
                await _rachaMinutosSinGolArqueroLiga(pid, tid);
          } catch (_) {
            a['rachaMinSinGolLiga'] = 0;
          }
        }));
        if (i + rachaLoteSize < arqueros.length) {
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }

      // 6. Ordenar por menor ratio goles concedidos/partido
      arqueros.sort((a, b) {
        final statsA = a['statistics'][0];
        final statsB = b['statistics'][0];
        final playedA = (statsA['games']?['appearences'] as int? ?? 1).toDouble();
        final playedB = (statsB['games']?['appearences'] as int? ?? 1).toDouble();
        final concA = (statsA['goals']?['conceded'] as int? ?? 999).toDouble();
        final concB = (statsB['goals']?['conceded'] as int? ?? 999).toDouble();
        return (concA / playedA).compareTo(concB / playedB);
      });

      return arqueros;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getEventosPartido(int fixtureId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures/events?fixture=$fixtureId'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final events = List<Map<String, dynamic>>.from(data['response']);
        return events;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getLineupsPartido(int fixtureId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures/lineups?fixture=$fixtureId'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lineups = data['response'] as List;
        return lineups.map((l) => l as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  static Future<Map<String, dynamic>?> getDetallePartido(int fixtureId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/fixtures?id=$fixtureId'), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['response'] != null && (data['response'] as List).isNotEmpty) return data['response'][0];
      }
      return null;
    } catch (e) { return null; }
  }
  static Future<List<Map<String, dynamic>>> getPlayersPartido(String fixtureId) async {
    try {
      final url = Uri.parse('$_baseUrl/fixtures/players?fixture=$fixtureId');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final teams = data['response'] as List? ?? [];
      final jugadores = <Map<String, dynamic>>[];
      for (final team in teams) {
        if (team is! Map<String, dynamic>) continue;
        final teamName = team['team']?['name'] as String? ?? '';
        final teamIdRaw = team['team']?['id'];
        final teamId = teamIdRaw is int ? teamIdRaw : (teamIdRaw is num ? teamIdRaw.toInt() : int.tryParse('$teamIdRaw') ?? 0);
        final teamLogo = team['team']?['logo'] as String? ?? '';
        final players = team['players'] as List? ?? [];
        for (final p in players) {
          if (p is! Map<String, dynamic>) continue;
          final statsList = p['statistics'];
          if (statsList is! List || statsList.isEmpty) continue;
          final stats = statsList[0];
          if (stats is! Map<String, dynamic>) continue;
          final games = stats['games'] as Map<String, dynamic>? ?? {};
          final numRaw = games['number'];
          final dorsalVal = numRaw is int ? numRaw : int.tryParse('$numRaw') ?? 0;
          final rating = games['rating'];
          final shots = stats['shots'];
          final tirosOn = shots is Map<String, dynamic> ? (shots['on'] ?? 0) : 0;
          final passes = stats['passes'];
          final pasesAcc = passes is Map<String, dynamic> ? (passes['accuracy'] ?? 0) : 0;
          final goals = stats['goals'];
          final cards = stats['cards'];
          final fouls = stats['fouls'];
          final pl = p['player'];
          if (pl is! Map<String, dynamic>) continue;
          jugadores.add({
            'id': pl['id'],
            'nombre': pl['name'],
            'foto': pl['photo'],
            'equipo': teamName,
            'equipoId': teamId,
            'equipoLogo': teamLogo,
            'rating': rating != null ? (double.tryParse(rating.toString()) ?? 0.0) : 0.0,
            'tieneRating': rating != null,
            'tiros': tirosOn,
            'pases': pasesAcc,
            'minutos': games['minutes'] ?? 0,
            'posicion': games['position'] ?? '',
            'numero': dorsalVal,
            'dorsal': dorsalVal,
            'capitan': games['captain'] ?? false,
            'suplente': games['substitute'] ?? false,
            'goles': goals is Map<String, dynamic> ? (goals['total'] ?? 0) : 0,
            'asistencias': goals is Map<String, dynamic> ? (goals['assists'] ?? 0) : 0,
            'saves': goals is Map<String, dynamic> ? (goals['saves'] ?? 0) : 0,
            'amarillas': cards is Map<String, dynamic> ? (cards['yellow'] ?? 0) : 0,
            'rojas': cards is Map<String, dynamic> ? (cards['red'] ?? 0) : 0,
            'faltas': fouls is Map<String, dynamic> ? (fouls['committed'] ?? 0) : 0,
          });
        }
      }
      jugadores.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      return jugadores;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUltimos5(int teamId) async {
    if (teamId <= 0) return [];
    const ttl = Duration(minutes: 2);
    final now = DateTime.now();
    final t = _ultimos5CacheTime[teamId];
    if (t != null &&
        now.difference(t) < ttl &&
        _ultimos5Cache.containsKey(teamId)) {
      return List<Map<String, dynamic>>.from(_ultimos5Cache[teamId]!);
    }
    final f = _ultimos5InFlight.putIfAbsent(teamId, () {
      return _getUltimos5Internal(teamId).then((list) {
        _ultimos5Cache[teamId] = list;
        _ultimos5CacheTime[teamId] = DateTime.now();
        return list;
      }).whenComplete(() => _ultimos5InFlight.remove(teamId));
    });
    return List<Map<String, dynamic>>.from(await f);
  }

  static Future<List<Map<String, dynamic>>> _getUltimos5Internal(int teamId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?team=$teamId&season=$_season&last=10'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final list = data['response'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getEficaciaGoleadores() async {
    try {
      // 1. Traer fixtures usando cache global
      final fixturesCached = await _getFixturesData();
      int maxPartidos = 1;
      if (fixturesCached.isNotEmpty) {
        final fixtures = fixturesCached;
        final Map<int, int> partidosPorEquipo = {};
        for (var f in fixtures) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final hId = f['teams']['home']['id'] as int;
          final aId = f['teams']['away']['id'] as int;
          partidosPorEquipo[hId] = (partidosPorEquipo[hId] ?? 0) + 1;
          partidosPorEquipo[aId] = (partidosPorEquipo[aId] ?? 0) + 1;
        }
        if (partidosPorEquipo.isNotEmpty) {
          maxPartidos = partidosPorEquipo.values.reduce((a, b) => a > b ? a : b);
        }
      }
      final minimoPartidos = (maxPartidos * 0.5).ceil();

      // 2. Traer top scorers y filtrar por minimo de partidos
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topscorers?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final scorers = data['response'] as List;
      List<Map<String, dynamic>> result = [];
      for (var s in scorers) {
        final player = s['player'];
        final stats = s['statistics'][0];
        final goles = stats['goals']['total'] as int? ?? 0;
        final partidos = stats['games']['appearences'] as int? ?? 0;
        if (partidos < minimoPartidos || goles == 0) continue;
        final ratio = goles / partidos;
        result.add({
          'id': player['id'],
          'nombre': player['name'],
          'foto': player['photo'],
          'equipo': stats['team']['name'],
          'goles': goles,
          'partidos': partidos,
          'ratio': ratio,
          'minimoRef': minimoPartidos,
          'maxRef': maxPartidos,
        });
      }
      result.sort((a, b) => (b['ratio'] as double).compareTo(a['ratio'] as double));
      return result.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getHistoricosGoleadores() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topscorers?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final scorers = data['response'] as List;
      final top20 = scorers.take(20).toList();

      // Traer goles del jugador en su club actual en todas las temporadas
      final futures = top20.map((s) async {
        final playerId = s['player']['id'];
        final teamId = s['statistics'][0]['team']['id'];
        final teamName = s['statistics'][0]['team']['name'] as String;
        try {
          final res = await http.get(
            Uri.parse('$_baseUrl/players?id=$playerId&team=$teamId'),
            headers: _headers,
          );
          if (res.statusCode != 200) return null;
          final d = jsonDecode(res.body);
          final list = d['response'] as List;
          if (list.isEmpty) return null;
          int totalGoles = 0;
          int totalPartidos = 0;
          for (var entry in list) {
            for (var st in (entry['statistics'] as List)) {
              totalGoles += (st['goals']['total'] as int? ?? 0);
              totalPartidos += (st['games']['appearences'] as int? ?? 0);
            }
          }
          if (totalGoles == 0) return null;
          return {
            'nombre': s['player']['name'],
            'equipo': teamName,
            'golesEnClub': totalGoles,
            'partidosEnClub': totalPartidos,
          };
        } catch (e) {
          return null;
        }
      }).toList();

      final results = await Future.wait(futures);
      final validos = results.whereType<Map<String, dynamic>>().toList();
      validos.sort((a, b) => (b['golesEnClub'] as int).compareTo(a['golesEnClub'] as int));
      return validos;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getPartidosEnVivo() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&live=all'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        return fixtures.map((f) => f as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Partidos del Mundial (league id 1) en curso — para tabla de grupos proyectada.
  static Future<List<Map<String, dynamic>>> getMundialPartidosEnVivo() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$_mundialId&season=$_mundialSeason&live=all'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List?;
        if (fixtures == null) return [];
        return fixtures.map((f) => f as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTablaArbitros() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&status=FT'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final fixtures = (data['response'] as List).cast<Map<String, dynamic>>();

      final Map<String, Map<String, dynamic>> arbitros = {};
      final List<Map<String, dynamic>> fixturesConArbitro = [];

      for (var f in fixtures) {
        final ref = f['fixture']['referee'] as String?;
        if (ref == null || ref.isEmpty || ref == 'null') continue;
        final nombre = ref.split(',')[0].trim();
        final homeGoals = f['goals']['home'] as int? ?? 0;
        final awayGoals = f['goals']['away'] as int? ?? 0;
        final homeId = f['teams']['home']['id'] as int;
        final awayId = f['teams']['away']['id'] as int;
        final homeName = f['teams']['home']['name'] as String;
        final awayName = f['teams']['away']['name'] as String;

        arbitros.putIfAbsent(nombre, () => {
          'nombre': nombre,
          'foto': null,
          'partidos': 0, 'victoriasLocal': 0, 'victoriasVisitante': 0, 'empates': 0,
          'amarillasLocal': 0, 'amarillasVisitante': 0,
          'rojasLocal': 0, 'rojasVisitante': 0,
          'penalesLocal': 0, 'penalesVisitante': 0,
          'varTotal': 0,
          'varGolesAnuladosLocal': 0, 'varGolesAnuladosVisitante': 0,
          'varPenalesConfirmados': 0, 'varPenalesAnulados': 0,
          'equipoStats': <int, Map<String, dynamic>>{},
        });

        arbitros[nombre]!['partidos'] += 1;
        if (homeGoals > awayGoals) arbitros[nombre]!['victoriasLocal'] += 1;
        else if (awayGoals > homeGoals) arbitros[nombre]!['victoriasVisitante'] += 1;
        else arbitros[nombre]!['empates'] += 1;

        // Inicializar stats por equipo
        final equipoStats = arbitros[nombre]!['equipoStats'] as Map<int, Map<String, dynamic>>;
        equipoStats.putIfAbsent(homeId, () => {'nombre': homeName, 'partidos': 0, 'victorias': 0, 'penales': 0, 'amarillas': 0, 'rojas': 0});
        equipoStats.putIfAbsent(awayId, () => {'nombre': awayName, 'partidos': 0, 'victorias': 0, 'penales': 0, 'amarillas': 0, 'rojas': 0});
        equipoStats[homeId]!['partidos'] += 1;
        equipoStats[awayId]!['partidos'] += 1;
        if (homeGoals > awayGoals) equipoStats[homeId]!['victorias'] += 1;
        else if (awayGoals > homeGoals) equipoStats[awayId]!['victorias'] += 1;

        fixturesConArbitro.add({'fixture': f, 'nombre': nombre});
      }

      // Traer foto del árbitro (una sola vez por árbitro)
      final nombresUnicos = arbitros.keys.toList();
      await Future.wait(nombresUnicos.map((nombre) async {
        try {
          final res = await http.get(
            Uri.parse('$_baseUrl/referees?name=$nombre'),
            headers: _headers,
          );
          if (res.statusCode == 200) {
            final d = jsonDecode(res.body)['response'] as List;
            if (d.isNotEmpty) {
              arbitros[nombre]!['foto'] = d[0]['photo'];
            }
          }
        } catch (e) {}
      }));

      // Traer eventos en lotes de 20 en paralelo
      const loteSize = 20;
      for (int i = 0; i < fixturesConArbitro.length; i += loteSize) {
        final lote = fixturesConArbitro.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((item) async {
          final f = item['fixture'] as Map<String, dynamic>;
          final nombre = item['nombre'] as String;
          final fixtureId = f['fixture']['id'];
          final homeId = f['teams']['home']['id'] as int;
          final awayId = f['teams']['away']['id'] as int;
          try {
            final evRes = await http.get(
              Uri.parse('$_baseUrl/fixtures/events?fixture=$fixtureId'),
              headers: _headers,
            );
            if (evRes.statusCode != 200) return;
            final events = (jsonDecode(evRes.body)['response'] as List);
            final equipoStats = arbitros[nombre]!['equipoStats'] as Map<int, Map<String, dynamic>>;
            for (var e in events) {
              final tipo = e['type'] as String? ?? '';
              final detalle = e['detail'] as String? ?? '';
              final teamId = e['team']?['id'] as int?;
              final esLocal = teamId == homeId;
              if (tipo == 'Card') {
                if (detalle == 'Yellow Card') {
                  if (esLocal) { arbitros[nombre]!['amarillasLocal'] += 1; equipoStats[homeId]?['amarillas'] += 1; }
                  else { arbitros[nombre]!['amarillasVisitante'] += 1; equipoStats[awayId]?['amarillas'] += 1; }
                } else if (detalle == 'Red Card' || detalle == 'Yellow Red Card') {
                  if (esLocal) { arbitros[nombre]!['rojasLocal'] += 1; equipoStats[homeId]?['rojas'] += 1; }
                  else { arbitros[nombre]!['rojasVisitante'] += 1; equipoStats[awayId]?['rojas'] += 1; }
                }
              }
              if (tipo == 'Goal' && detalle == 'Penalty') {
                if (esLocal) { arbitros[nombre]!['penalesLocal'] += 1; equipoStats[homeId]?['penales'] += 1; }
                else { arbitros[nombre]!['penalesVisitante'] += 1; equipoStats[awayId]?['penales'] += 1; }
              }
              // Goles de corner (córner directo / gol olímpico)
              if (tipo == 'Goal' && detalle == 'Own Goal') {
                arbitros[nombre]!['golesPropia'] = (arbitros[nombre]!['golesPropia'] as int? ?? 0) + 1;
              }
              if (tipo == 'Goal' && (detalle == 'Corner' || detalle == 'Direct Corner')) {
                arbitros[nombre]!['golesCorner'] = (arbitros[nombre]!['golesCorner'] as int? ?? 0) + 1;
              }
              if (tipo == 'Var') {
                arbitros[nombre]!['varTotal'] += 1;
                if (detalle == 'Goal cancelled') {
                  if (esLocal) arbitros[nombre]!['varGolesAnuladosLocal'] += 1;
                  else arbitros[nombre]!['varGolesAnuladosVisitante'] += 1;
                } else if (detalle == 'Penalty confirmed') {
                  arbitros[nombre]!['varPenalesConfirmados'] += 1;
                } else if (detalle == 'Penalty cancelled') {
                  arbitros[nombre]!['varPenalesAnulados'] += 1;
                }
              }
            }
          } catch (e) {}
        }));
      }

      final result = arbitros.values.map((a) {
        final partidos = a['partidos'] as int;
        final amarillas = (a['amarillasLocal'] as int) + (a['amarillasVisitante'] as int);
        final rojas = (a['rojasLocal'] as int) + (a['rojasVisitante'] as int);
        final penales = (a['penalesLocal'] as int) + (a['penalesVisitante'] as int);
        final promAmarillas = partidos > 0 ? amarillas / partidos : 0.0;
        final favLocal = (a['penalesLocal'] as int) - (a['amarillasLocal'] as int) ~/ 3;
        final favVisit = (a['penalesVisitante'] as int) - (a['amarillasVisitante'] as int) ~/ 3;
        final favorece = favLocal > favVisit ? 'Local' : favVisit > favLocal ? 'Visitante' : 'Neutro';

        // Calcular equipo más beneficiado y perjudicado (deben ser DISTINTOS)
        final equipoStats = a['equipoStats'] as Map<int, Map<String, dynamic>>;
        String equipoBeneficiado = '-';
        String equipoPerjudicado = '-';
        final equiposOrdenados = equipoStats.values.toList()
          ..sort((x, y) {
            final sx = (x['penales'] as int) * 3 - (x['amarillas'] as int) - (x['rojas'] as int) * 3;
            final sy = (y['penales'] as int) * 3 - (y['amarillas'] as int) - (y['rojas'] as int) * 3;
            return sy.compareTo(sx);
          });
        if (equiposOrdenados.isNotEmpty) {
          equipoBeneficiado = equiposOrdenados.first['nombre'] as String;
          final candidato = equiposOrdenados.lastWhere(
            (eq) => eq['nombre'] != equipoBeneficiado,
            orElse: () => <String, dynamic>{},
          );
          if (candidato.isNotEmpty) equipoPerjudicado = candidato['nombre'] as String;
        }

        return {
          ...a,
          'amarillasTotal': amarillas, 'rojasTotal': rojas, 'penalesTotal': penales,
          'promAmarillas': promAmarillas, 'favorece': favorece,
          'equipoBeneficiado': equipoBeneficiado,
          'equipoPerjudicado': equipoPerjudicado,
          'varTotal': a['varTotal'] ?? 0,
          'varGolesAnuladosLocal': a['varGolesAnuladosLocal'] ?? 0,
          'varGolesAnuladosVisitante': a['varGolesAnuladosVisitante'] ?? 0,
          'varPenalesConfirmados': a['varPenalesConfirmados'] ?? 0,
          'varPenalesAnulados': a['varPenalesAnulados'] ?? 0,
          'varIndice': partidos > 0 ? ((a['varTotal'] ?? 0) as int) / partidos : 0.0,
        };
      }).toList();

      result.sort((a, b) => (b['partidos'] as int).compareTo(a['partidos'] as int));
      return result;
    } catch (e) {
      return [];
    }
  }

  static List<Map<String, dynamic>>? _prediccionesCache;
  static DateTime? _prediccionesCacheTime;

  static Future<List<Map<String, dynamic>>> _fetchPrediccionesLigaTodos() async {
    final acc = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      try {
        final uri = page == 1
            ? Uri.parse(
                '$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&timezone=America/Argentina/Buenos_Aires')
            : Uri.parse(
                '$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&timezone=America/Argentina/Buenos_Aires&page=$page');
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode != 200) break;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) break;
        final errs = decoded['errors'];
        if (errs is Map && errs.isNotEmpty) break;
        final fixtures = decoded['response'] as List? ?? [];
        for (final f in fixtures) {
          acc.add(f as Map<String, dynamic>);
        }
        final paging = decoded['paging'];
        final totalPages = paging is Map
            ? (paging['total'] as num?)?.toInt() ?? 1
            : 1;
        if (page >= totalPages || fixtures.isEmpty) break;
        page++;
      } catch (_) {
        break;
      }
    }
    return acc;
  }

  static Future<List<Map<String, dynamic>>> getPredicciones() async {
    // Cache 45 min — evita recalcular y resultados cambiantes
    if (_prediccionesCache != null && _prediccionesCacheTime != null &&
        DateTime.now().difference(_prediccionesCacheTime!).inMinutes < 45) {
      return _prediccionesCache!;
    }
    try {
      final todos = await _fetchPrediccionesLigaTodos();

      int? proximaFecha;
      Map<int, List<Map<String, dynamic>>> porFecha = {};
      if (todos.isNotEmpty) {
      int fixtureIdSort(Map<String, dynamic> p) {
        final raw = p['fixture']?['id'];
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        return int.tryParse('$raw') ?? 0;
      }

      final todosOrdenados = List<Map<String, dynamic>>.from(todos)
        ..sort((a, b) => fixtureIdSort(a).compareTo(fixtureIdSort(b)));

      // Toda la temporada: fechas regulares solo buckets 1–99 (ligaFixtureBucket).
      // Antes solo se miraba la mitad de los fixtures por id y se parseaba `round`
      // quitando no-dígitos → mezclaba playoffs en clave 0 y se perdía la próxima fecha.
      for (final p in todosOrdenados) {
        final st = p['fixture']?['status']?['short'] as String? ?? '';
        if (st == 'PST' || st == 'CANC' || st == 'TBD') continue;
        final round = (p['league']?['round'] as String?)?.trim() ?? '';
        final b = ligaFixtureBucket(round);
        if (b < 1 || b > 99) continue;
        porFecha.putIfAbsent(b, () => []).add(p);
      }
      final fechas = porFecha.keys.toList()..sort();

      // Fecha en curso = la más alta con al menos 1 partido activo o FT
      int fechaEnCurso = 0;
      for (final f in fechas) {
        final tieneActividad = porFecha[f]!.any((p) {
          final s = p['fixture']['status']['short'] as String;
          return s == 'FT' || s == 'AET' || s == 'PEN' || s == '1H' || s == '2H' || s == 'HT';
        });
        if (tieneActividad && f > fechaEnCurso) fechaEnCurso = f;
      }
      // Si la fecha en curso todavía tiene NS → mostrar esos partidos
      if (fechaEnCurso > 0) {
        final nsEnCurso = porFecha[fechaEnCurso]?.where((p) =>
            p['fixture']['status']['short'] == 'NS').toList() ?? [];
        if (nsEnCurso.isNotEmpty) proximaFecha = fechaEnCurso;
      }
      // Si la fecha en curso está completa → mostrar la siguiente
      if (proximaFecha == null) {
        for (final f in fechas) {
          if (f <= fechaEnCurso) continue;
          if (porFecha[f]!.any((p) => p['fixture']['status']['short'] == 'NS')) {
            proximaFecha = f; break;
          }
        }
      }
      }

      List<Map<String, dynamic>> ligaPreds = [];
      if (proximaFecha != null) {
        final partidos = porFecha[proximaFecha]!.where((p) {
          final s = p['fixture']['status']['short'] as String;
          return s == 'NS';
        }).toList();
        final sortKey = 'A_${proximaFecha.toString().padLeft(4, '0')}';
        final label = 'LIGA PROFESIONAL · Fecha $proximaFecha';
        ligaPreds = await Future.wait(partidos.map((p) => _calcularPrediccionPartido(
              p,
              grupoSortKey: sortKey,
              grupoLabel: label,
              fechaLiga: proximaFecha,
            )));
      }

      final yaLigaFids = <int>{
        for (final pred in ligaPreds)
          if ((pred['fixtureId'] as int?) != null &&
              (pred['fixtureId'] as int) > 0)
            pred['fixtureId'] as int
      };
      final ligaKoPreds =
          await _prediccionesLigaArgPlayoffsNs(todos, yaLigaFids);

      // Solo Liga Profesional Argentina (fecha regular + liguilla LPF).
      final all = [...ligaPreds, ...ligaKoPreds];
      all.sort((a, b) {
        final c = (a['grupoSortKey'] as String).compareTo(b['grupoSortKey'] as String);
        if (c != 0) return c;
        final da = a['fechaHora'] as String? ?? '';
        final db = b['fechaHora'] as String? ?? '';
        return da.compareTo(db);
      });

      if (all.isEmpty) return _prediccionesCache ?? [];

      _prediccionesCache = all;
      _prediccionesCacheTime = DateTime.now();
      return all;
    } catch (e) {
      return _prediccionesCache ?? [];
    }
  }

  static String _labelDiaPrediccion(DateTime dt) {
    const dias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return '${dias[dt.weekday]} ${dt.day}/${dt.month}';
  }

  /// Eliminatorias LPF (128): octavos/cuartos/semis/final — no entran en el reparto por "fecha" regular
  /// (además `getPredicciones` solo miraba la mitad de los fixtures por id).
  static Future<List<Map<String, dynamic>>> _prediccionesLigaArgPlayoffsNs(
    List<Map<String, dynamic>> todos,
    Set<int> excluirFixtureIds,
  ) async {
    const faseEtiqueta = <int, String>{
      200: 'Octavos de final',
      300: 'Cuartos de final',
      400: 'Semifinales',
      500: 'Final',
      999: 'Eliminatorias',
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidatos = <Map<String, Object>>[];
    for (final p in todos) {
      final st = p['fixture']?['status']?['short'] as String? ?? '';
      if (st != 'NS') continue;
      final idRaw = p['fixture']?['id'];
      final id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;
      if (id == 0 || excluirFixtureIds.contains(id)) continue;
      final round = (p['league']?['round'] as String?)?.trim() ?? '';
      final b = ligaFixtureBucket(round);
      final fase = faseEtiqueta[b];
      if (fase == null) continue;
      final ds = p['fixture']?['date'] as String?;
      if (ds == null) continue;
      DateTime dt;
      try {
        dt = DateTime.parse(ds).toLocal();
      } catch (_) {
        continue;
      }
      final dOnly = DateTime(dt.year, dt.month, dt.day);
      if (dOnly.isBefore(today)) continue;
      final sortKey = 'A_LKO_${b.toString().padLeft(3, '0')}';
      final label =
          'LIGA PROFESIONAL · $fase · ${_labelDiaPrediccion(dt)}${round.isNotEmpty ? ' · $round' : ''}';
      candidatos.add({'p': p, 'sortKey': sortKey, 'label': label});
    }
    candidatos.sort((a, b) {
      final c = (a['sortKey'] as String).compareTo(b['sortKey'] as String);
      if (c != 0) return c;
      final da =
          (a['p'] as Map<String, dynamic>)['fixture']?['date'] as String? ?? '';
      final db =
          (b['p'] as Map<String, dynamic>)['fixture']?['date'] as String? ?? '';
      return da.compareTo(db);
    });
    final out = <Map<String, dynamic>>[];
    const batch = 3;
    for (var i = 0; i < candidatos.length; i += batch) {
      final slice = candidatos.skip(i).take(batch).toList();
      out.addAll(await Future.wait(slice.map((c) => _calcularPrediccionPartido(
            c['p'] as Map<String, dynamic>,
            grupoSortKey: c['sortKey'] as String,
            grupoLabel: c['label'] as String,
            fechaLiga: null,
          ))));
      if (i + batch < candidatos.length) {
        await Future.delayed(const Duration(milliseconds: 220));
      }
    }
    return out;
  }

  static Future<Map<String, dynamic>> _calcularPrediccionPartido(
    Map<String, dynamic> p, {
    required String grupoSortKey,
    required String grupoLabel,
    int? fechaLiga,
  }) async {
    final fidRaw = p['fixture']?['id'];
    final fixtureId = fidRaw is int ? fidRaw : int.tryParse('$fidRaw') ?? 0;
    final leagueStatId =
        (p['league']?['id'] as num?)?.toInt() ?? _ligaArgentina;
    final seasonStat = (p['league']?['season'] as num?)?.toInt() ?? _season;

    final homeRaw = p['teams']?['home']?['id'];
    final awayRaw = p['teams']?['away']?['id'];
    final homeId = homeRaw is int ? homeRaw : int.tryParse('$homeRaw') ?? 0;
    final awayId = awayRaw is int ? awayRaw : int.tryParse('$awayRaw') ?? 0;
    final homeName = p['teams']?['home']?['name'] as String? ?? '';
    final awayName = p['teams']?['away']?['name'] as String? ?? '';
    final homeLogo = p['teams']?['home']?['logo'] as String?;
    final awayLogo = p['teams']?['away']?['logo'] as String?;
    final fechaHora = p['fixture']?['date'] as String?;
    final venueId = p['fixture']?['venue']?['id'] as int?;
    final venueName = p['fixture']?['venue']?['name'] as String? ?? '';
    final venueCity = p['fixture']?['venue']?['city'] as String? ?? '';

        final results = await Future.wait([
          getUltimos5(homeId),
          getUltimos5(awayId),
          getHeadToHead(homeId, awayId),
          getStatsEquipoTorneo(homeId, leagueStatId, seasonStat),
          getStatsEquipoTorneo(awayId, leagueStatId, seasonStat),
        ]);
        final ultLocal = results[0] as List<Map<String, dynamic>>;
        final ultVisit = results[1] as List<Map<String, dynamic>>;
        final h2h = results[2] as List<Map<String, dynamic>>;
        final statsLocal = results[3] as Map<String, dynamic>;
        final statsVisit = results[4] as Map<String, dynamic>;

        // ── ALGORITMO v2: 40% FORMA CONDICIÓN + 35% TORNEO + 25% H2H ──

        // — BLOQUE A: Forma reciente en CONDICIÓN (local como local, visitante como visitante) —
        double puntosFormaLocal = 0, puntosFormaVisit = 0;
        int partidosFormaLocal = 0, partidosFormaVisit = 0;

        // Local: buscar sus partidos jugando de LOCAL
        for (var f in ultLocal) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final esHome = f['teams']['home']['id'] == homeId;
          if (!esHome) continue;
          final hg = f['goals']['home'] as int? ?? 0;
          final ag = f['goals']['away'] as int? ?? 0;
          if (hg > ag) puntosFormaLocal += 3;
          else if (hg == ag) puntosFormaLocal += 1;
          partidosFormaLocal++;
          if (partidosFormaLocal >= 5) break;
        }
        // Si tiene menos de 3 partidos como local, completar con partidos de visitante
        if (partidosFormaLocal < 3) {
          for (var f in ultLocal) {
            final st = f['fixture']['status']['short'] as String;
            if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
            final esHome = f['teams']['home']['id'] == homeId;
            if (esHome) continue;
            final hg = f['goals']['home'] as int? ?? 0;
            final ag = f['goals']['away'] as int? ?? 0;
            if (ag > hg) puntosFormaLocal += 3;
            else if (hg == ag) puntosFormaLocal += 1;
            partidosFormaLocal++;
            if (partidosFormaLocal >= 5) break;
          }
        }

        // Visitante: buscar sus partidos jugando de VISITANTE
        for (var f in ultVisit) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final esHome = f['teams']['home']['id'] == awayId;
          if (esHome) continue;
          final hg = f['goals']['home'] as int? ?? 0;
          final ag = f['goals']['away'] as int? ?? 0;
          if (ag > hg) puntosFormaVisit += 3;
          else if (hg == ag) puntosFormaVisit += 1;
          partidosFormaVisit++;
          if (partidosFormaVisit >= 5) break;
        }
        if (partidosFormaVisit < 3) {
          for (var f in ultVisit) {
            final st = f['fixture']['status']['short'] as String;
            if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
            final esHome = f['teams']['home']['id'] == awayId;
            if (!esHome) continue;
            final hg = f['goals']['home'] as int? ?? 0;
            final ag = f['goals']['away'] as int? ?? 0;
            if (hg > ag) puntosFormaVisit += 3;
            else if (hg == ag) puntosFormaVisit += 1;
            partidosFormaVisit++;
            if (partidosFormaVisit >= 5) break;
          }
        }

        // Normalizar forma a escala 0-1
        final maxPtosL = (partidosFormaLocal > 0 ? partidosFormaLocal : 5) * 3.0;
        final maxPtosV = (partidosFormaVisit > 0 ? partidosFormaVisit : 5) * 3.0;
        final formaLocalNorm = puntosFormaLocal / maxPtosL;
        final formaVisitNorm = puntosFormaVisit / maxPtosV;

        // — BLOQUE B: Stats torneo en condición —
        final totalLocalFor = (statsLocal['goals']?['for']?['total']?['home'] as num?)?.toDouble() ?? 0.0;
        final totalVisitFor = (statsVisit['goals']?['for']?['total']?['away'] as num?)?.toDouble() ?? 0.0;
        final totalLocalAgainst = (statsLocal['goals']?['against']?['total']?['home'] as num?)?.toDouble() ?? 0.0;
        final totalVisitAgainst = (statsVisit['goals']?['against']?['total']?['away'] as num?)?.toDouble() ?? 0.0;
        final pjLocalHome = (statsLocal['fixtures']?['played']?['home'] as num?)?.toDouble() ?? 0.0;
        final pjVisitAway = (statsVisit['fixtures']?['played']?['away'] as num?)?.toDouble() ?? 0.0;

        final avgGolLocalFavor = pjLocalHome > 0 ? totalLocalFor / pjLocalHome : 1.1;
        final avgGolVisitFavor = pjVisitAway > 0 ? totalVisitFor / pjVisitAway : 0.8;
        final avgGolLocalContra = pjLocalHome > 0 ? totalLocalAgainst / pjLocalHome : 1.0;
        final avgGolVisitContra = pjVisitAway > 0 ? totalVisitAgainst / pjVisitAway : 1.2;

        final vLocal = (statsLocal['fixtures']?['wins']?['home'] as num?)?.toDouble() ?? 0.0;
        final eLocal = (statsLocal['fixtures']?['draws']?['home'] as num?)?.toDouble() ?? 0.0;
        final vVisit = (statsVisit['fixtures']?['wins']?['away'] as num?)?.toDouble() ?? 0.0;
        final eVisit = (statsVisit['fixtures']?['draws']?['away'] as num?)?.toDouble() ?? 0.0;

        final torneoLocalNorm = pjLocalHome > 0 ? (vLocal * 3 + eLocal) / (pjLocalHome * 3) : 0.33;
        final torneoVisitNorm = pjVisitAway > 0 ? (vVisit * 3 + eVisit) / (pjVisitAway * 3) : 0.33;

        // — BLOQUE C: H2H histórico (últimos 10) —
        int h2hLocal = 0, h2hVisit = 0, h2hEmpate = 0;
        double h2hGolesLocal = 0, h2hGolesVisit = 0;
        int h2hCount = 0;
        for (var f in h2h.take(10)) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final fHomeId = f['teams']['home']['id'] as int;
          final hg = f['goals']['home'] as int? ?? 0;
          final ag = f['goals']['away'] as int? ?? 0;
          if (fHomeId == homeId) {
            h2hGolesLocal += hg; h2hGolesVisit += ag;
            if (hg > ag) h2hLocal++;
            else if (ag > hg) h2hVisit++;
            else h2hEmpate++;
          } else {
            h2hGolesLocal += ag; h2hGolesVisit += hg;
            if (ag > hg) h2hLocal++;
            else if (hg > ag) h2hVisit++;
            else h2hEmpate++;
          }
          h2hCount++;
        }
        final h2hLocalNorm = h2hCount > 0 ? h2hLocal / h2hCount.toDouble() : 0.35;
        final h2hVisitNorm = h2hCount > 0 ? h2hVisit / h2hCount.toDouble() : 0.28;

        // — MIX FINAL: 40% forma condición + 35% torneo + 25% H2H —
        const wForma = 0.40, wTorneo = 0.35, wH2h = 0.25;

        double scoreLocal = formaLocalNorm * wForma + torneoLocalNorm * wTorneo + h2hLocalNorm * wH2h + 0.05; // +5% ventaja local
        double scoreVisit = formaVisitNorm * wForma + torneoVisitNorm * wTorneo + h2hVisitNorm * wH2h;
        double scoreEmpate = (1.0 - scoreLocal - scoreVisit).clamp(0.15, 0.40);

        // Renormalizar para que sumen 100%
        final scoreSum = scoreLocal + scoreVisit + scoreEmpate;
        double pctLocal = (scoreLocal / scoreSum * 100).clamp(20.0, 75.0);
        double pctVisit = (scoreVisit / scoreSum * 100).clamp(15.0, 65.0);
        double pctEmpate = (100.0 - pctLocal - pctVisit).clamp(15.0, 40.0);
        final pctSum2 = pctLocal + pctVisit + pctEmpate;
        pctLocal = pctLocal / pctSum2 * 100;
        pctVisit = pctVisit / pctSum2 * 100;
        pctEmpate = pctEmpate / pctSum2 * 100;

        // — MARCADOR PREDICHO —
        final defVisitFactor = avgGolVisitContra / 1.2;
        final defLocalFactor = avgGolLocalContra / 1.0;
        double golesLocalEsp = avgGolLocalFavor * defVisitFactor;
        double golesVisitEsp = avgGolVisitFavor * defLocalFactor;

        // Mezclar con H2H si hay datos suficientes
        if (h2hCount >= 3) {
          final avgH2hLocal = h2hGolesLocal / h2hCount;
          final avgH2hVisit = h2hGolesVisit / h2hCount;
          golesLocalEsp = golesLocalEsp * 0.6 + avgH2hLocal * 0.4;
          golesVisitEsp = golesVisitEsp * 0.6 + avgH2hVisit * 0.4;
        }

        // Ajuste por forma reciente (±0.3 goles máximo)
        final ajusteGolesL = ((formaLocalNorm - 0.5) * 0.6).clamp(-0.3, 0.3);
        final ajusteGolesV = ((formaVisitNorm - 0.5) * 0.6).clamp(-0.3, 0.3);
        golesLocalEsp = (golesLocalEsp + ajusteGolesL + 0.1).clamp(0.3, 3.5);
        golesVisitEsp = (golesVisitEsp + ajusteGolesV).clamp(0.2, 2.8);

        final golesLocalPred = golesLocalEsp.round().clamp(0, 4);
        final golesVisitPred = golesVisitEsp.round().clamp(0, 3);

        // Forma reciente para display (bolitas W/D/L — últimos 5 general)
        List<String> formaRecLocal = [], formaRecVisit = [];
        for (var f in ultLocal) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final esHome = f['teams']['home']['id'] == homeId;
          final hg = f['goals']['home'] as int? ?? 0;
          final ag = f['goals']['away'] as int? ?? 0;
          if (esHome) formaRecLocal.add(hg > ag ? 'W' : hg == ag ? 'D' : 'L');
          else formaRecLocal.add(ag > hg ? 'W' : hg == ag ? 'D' : 'L');
          if (formaRecLocal.length >= 5) break;
        }
        for (var f in ultVisit) {
          final st = f['fixture']['status']['short'] as String;
          if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
          final esHome = f['teams']['home']['id'] == awayId;
          final hg = f['goals']['home'] as int? ?? 0;
          final ag = f['goals']['away'] as int? ?? 0;
          if (esHome) formaRecVisit.add(hg > ag ? 'W' : hg == ag ? 'D' : 'L');
          else formaRecVisit.add(ag > hg ? 'W' : hg == ag ? 'D' : 'L');
          if (formaRecVisit.length >= 5) break;
        }


    return {
          'fixtureId': fixtureId,
          'homeId': homeId, 'awayId': awayId,
          'homeName': homeName, 'awayName': awayName,
          'homeLogo': homeLogo, 'awayLogo': awayLogo,
          'fechaHora': fechaHora,
          'venueId': venueId,
          'venueName': venueName,
          'venueCity': venueCity,
          'pctLocal': pctLocal, 'pctEmpate': pctEmpate, 'pctVisit': pctVisit,
          'formaLocal': formaRecLocal, 'formaVisit': formaRecVisit,
          'h2hLocal': h2hLocal, 'h2hEmpate': h2hEmpate, 'h2hVisit': h2hVisit,
          'golesLocalPred': golesLocalPred, 'golesVisitPred': golesVisitPred,
          'fecha': fechaLiga ?? 0,
          'grupoSortKey': grupoSortKey,
          'grupoLabel': grupoLabel,
        };
  }

  // Cache para TablaDTs (deduplicar peticiones en vuelo: evita carreras que dejan la caché vacía).
  static List<Map<String, dynamic>>? _tablaDTsCache;
  static Future<List<Map<String, dynamic>>>? _tablaDTsInFlight;
  static int _tablaDTsEpoch = 0;

  static List<Map<String, dynamic>>? _tablaPosesionCache;
  static DateTime? _tablaPosesionCacheTime;

  static double? _parseBallPossessionBlock(Map<String, dynamic> block) {
    final stats = block['statistics'] as List? ?? [];
    for (final s in stats) {
      if (s['type'] == 'Ball Possession') {
        final v = s['value']?.toString().replaceAll('%', '').trim() ?? '';
        return double.tryParse(v);
      }
    }
    return null;
  }

  /// Promedio de posesión acumulada solo Liga Profesional (estadísticas por partido).
  static Future<List<Map<String, dynamic>>> getTablaPosesion({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _tablaPosesionCache != null &&
        _tablaPosesionCacheTime != null &&
        DateTime.now().difference(_tablaPosesionCacheTime!).inMinutes < 60) {
      return _tablaPosesionCache!;
    }
    try {
      final resFix = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (resFix.statusCode != 200) return _tablaPosesionCache ?? [];

      final todos = (jsonDecode(resFix.body)['response'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final jugados = todos.where((f) {
        final s = f['fixture']?['status']?['short'] as String? ?? '';
        return s == 'FT' || s == 'AET' || s == 'PEN';
      }).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['fixture']?['date'] as String? ?? '') ??
              DateTime(2000);
          final db = DateTime.tryParse(b['fixture']?['date'] as String? ?? '') ??
              DateTime(2000);
          return da.compareTo(db);
        });

      final Map<int, Map<String, dynamic>> acum = {};

      const loteSize = 8;
      for (int i = 0; i < jugados.length; i += loteSize) {
        final lote = jugados.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((f) async {
          final fxId = f['fixture']?['id'] as int?;
          if (fxId == null) return;
          try {
            final res = await http.get(
              Uri.parse('$_baseUrl/fixtures/statistics?fixture=$fxId'),
              headers: _headers,
            );
            if (res.statusCode != 200) return;
            final blocks =
                (jsonDecode(res.body)['response'] as List? ?? []).cast<Map<String, dynamic>>();
            if (blocks.length < 1) return;

            for (final block in blocks) {
              final team = block['team'] as Map<String, dynamic>?;
              if (team == null) continue;
              final tid = team['id'] as int?;
              if (tid == null) continue;
              final pct = _parseBallPossessionBlock(block);
              if (pct == null) continue;

              acum.putIfAbsent(
                tid,
                () => {
                  'sum': 0.0,
                  'n': 0,
                  'nombre': team['name'] as String? ?? '',
                  'logo': team['logo'] as String? ?? '',
                },
              );
              acum[tid]!['sum'] = (acum[tid]!['sum'] as double) + pct;
              acum[tid]!['n'] = (acum[tid]!['n'] as int) + 1;
              acum[tid]!['nombre'] = team['name'] as String? ?? acum[tid]!['nombre'];
              acum[tid]!['logo'] = team['logo'] as String? ?? acum[tid]!['logo'];
            }
          } catch (_) {}
        }));
        if (i + loteSize < jugados.length) {
          await Future.delayed(const Duration(milliseconds: 220));
        }
      }

      final List<Map<String, dynamic>> rows = [];
      for (final e in acum.entries) {
        final n = e.value['n'] as int;
        if (n == 0) continue;
        final sum = e.value['sum'] as double;
        final prom = sum / n;
        final int colorValue;
        final String zonaCorta;
        if (prom >= 55) {
          colorValue = 0xFF2196F3;
          zonaCorta = 'Dominante';
        } else if (prom >= 48) {
          colorValue = 0xFFFFC107;
          zonaCorta = 'Equilibrado';
        } else if (prom >= 42) {
          colorValue = 0xFFFF9800;
          zonaCorta = 'Defensivo';
        } else {
          colorValue = 0xFFE53935;
          zonaCorta = 'Muy defensivo';
        }
        rows.add({
          'teamId': e.key,
          'nombre': e.value['nombre'],
          'logo': e.value['logo'],
          'promedio': double.parse(prom.toStringAsFixed(1)),
          'partidos': n,
          'zonaCorta': zonaCorta,
          'zonaColor': colorValue,
        });
      }
      rows.sort((a, b) =>
          (b['promedio'] as double).compareTo(a['promedio'] as double));

      _tablaPosesionCache = rows;
      _tablaPosesionCacheTime = DateTime.now();
      return rows;
    } catch (_) {
      return _tablaPosesionCache ?? [];
    }
  }

  /// Liga + Libertadores + Sudamericana + Copa Argentina (solo duelos con argentinos en copas).
  static Future<List<Map<String, dynamic>>> _fixturesLigaYCopasArgParaDTs() async {
    final byId = <int, Map<String, dynamic>>{};

    void ingest(Map<String, dynamic> m) {
      final id = _idFromDynamic(m['fixture']?['id']);
      if (id == null) return;
      final s = m['fixture']?['status']?['short'] as String? ?? '';
      if (s != 'FT' && s != 'AET' && s != 'PEN') return;
      byId[id] = m;
    }

    final hasta = DateTime.now();
    final desde = hasta.subtract(const Duration(days: _dtTablaFixturesLookbackDays));
    final from = _ymdApi(desde);
    final to = _ymdApi(hasta);

    try {
      var ligaRaw = await _getFixturesLigaVentanaParaDTs(from, to);
      if (ligaRaw.isEmpty) {
        ligaRaw = await _getFixturesAllData();
      }
      for (final f in ligaRaw) {
        if (f is Map<String, dynamic>) ingest(f);
      }
    } catch (_) {}

    Future<void> fetchCup(int leagueId, List<int> seasons) async {
      for (final sea in seasons) {
        try {
          final r = await http
              .get(
                Uri.parse(
                  '$_baseUrl/fixtures?league=$leagueId&season=$sea&from=$from&to=$to',
                ),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 55));
          if (r.statusCode != 200) continue;
          final raw = jsonDecode(r.body)['response'];
          final resp = raw is List ? raw : const [];
          for (final f in resp) {
            final m = f as Map<String, dynamic>;
            final hId = m['teams']?['home']?['id']?.toString() ?? '';
            final aId = m['teams']?['away']?['id']?.toString() ?? '';
            if (!_equiposArgTablaDT.contains(hId) && !_equiposArgTablaDT.contains(aId)) {
              continue;
            }
            ingest(m);
          }
        } catch (_) {}
      }
    }

    await fetchCup(13, [_season, 2025]);
    await fetchCup(11, [_season, 2025]);
    await fetchCup(_copaArgentina, [_season, 2025]);

    var list = byId.values.toList();
    list.sort((a, b) {
      final da = DateTime.tryParse(a['fixture']?['date'] as String? ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['fixture']?['date'] as String? ?? '') ?? DateTime(2000);
      return da.compareTo(db);
    });
    if (list.length > _dtTablaMaxFixturesLineups) {
      list = list.sublist(list.length - _dtTablaMaxFixturesLineups);
    }
    return list;
  }

  static Future<List<Map<String, dynamic>>> getTablaDTs({bool forceRefresh = false}) async {
    if (!forceRefresh && _tablaDTsCache != null) return _tablaDTsCache!;

    if (forceRefresh) {
      _tablaDTsEpoch++;
      if (_tablaDTsInFlight != null) {
        await _tablaDTsInFlight;
      }
      _tablaDTsCache = null;
    }

    if (_tablaDTsInFlight != null) {
      return List<Map<String, dynamic>>.from(await _tablaDTsInFlight!);
    }

    final epochAtStart = _tablaDTsEpoch;
    final fut = _getTablaDTsInternal(epochAtStart);
    _tablaDTsInFlight = fut;
    fut.whenComplete(() {
      if (identical(_tablaDTsInFlight, fut)) {
        _tablaDTsInFlight = null;
      }
    });
    return List<Map<String, dynamic>>.from(await fut);
  }

  static Future<List<Map<String, dynamic>>> _getTablaDTsInternal(int epochAtStart) async {
    try {
      // Liga + copas (argentinos), terminados, orden cronológico ascendente
      final fixtures = await _fixturesLigaYCopasArgParaDTs();

      // coachId -> stats acumulados
      final Map<String, Map<String, dynamic>> dts = {};

      // Lotes de 10, pausa de 200ms entre lotes
      const loteSize = 10;
      for (int i = 0; i < fixtures.length; i += loteSize) {
        final lote = fixtures.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((f) async {
          try {
            final fm = f;
            final fxId = _idFromDynamic(fm['fixture']?['id']);
            final homeId = _idFromDynamic(fm['teams']?['home']?['id']);
            final awayId = _idFromDynamic(fm['teams']?['away']?['id']);
            if (fxId == null || homeId == null || awayId == null) return;
            final hGoals = _intFromApi(fm['goals']?['home']);
            final aGoals = _intFromApi(fm['goals']?['away']);
            final res = await http
                .get(
                  Uri.parse('$_baseUrl/fixtures/lineups?fixture=$fxId'),
                  headers: _headers,
                )
                .timeout(const Duration(seconds: 22));
            if (res.statusCode != 200) return;
            final decoded = jsonDecode(res.body);
            final rawLu = decoded is Map<String, dynamic> ? decoded['response'] : null;
            if (rawLu is! List) return;
            final lineups = rawLu.whereType<Map<String, dynamic>>().toList();
            for (final lu in lineups) {
              final coach = lu['coach'] as Map<String, dynamic>?;
              if (coach == null) continue;
              final coachId = coach['id']?.toString() ?? '';
              if (coachId.isEmpty) continue;

              final luTeamId = _idFromDynamic(lu['team']?['id']);
              if (luTeamId == null) continue;
              // Solo DT de clubes argentinos: LPF y Copa Arg. cuentan todos; en Libertadores/Sudamericana solo el bando argentino.
              final leagueF = _idFromDynamic(fm['league']?['id']) ?? 0;
              final esCompetenciaSoloArg =
                  leagueF == _ligaArgentina || leagueF == _copaArgentina;
              if (!esCompetenciaSoloArg &&
                  !_equiposArgTablaDT.contains(luTeamId.toString())) {
                continue;
              }
              final isHome   = luTeamId == homeId;
              final teamName = (isHome ? fm['teams']['home']['name'] : fm['teams']['away']['name']) as String;
              final teamLogo = (isHome ? fm['teams']['home']['logo'] : fm['teams']['away']['logo']) as String? ?? '';
              final gano     = isHome ? hGoals > aGoals : aGoals > hGoals;
              final empato   = hGoals == aGoals;
              final res2     = gano ? 'W' : empato ? 'D' : 'L';

              if (!dts.containsKey(coachId)) {
                dts[coachId] = {
                  'id':         coachId,
                  'nombre':     coach['name'] as String? ?? '',
                  'foto':       coach['photo'] as String?,
                  'equipo':     teamName,
                  'equipoId':   luTeamId,
                  'equipoLogo': teamLogo,
                  'partidos':   0, 'victorias': 0, 'empates': 0, 'derrotas': 0,
                  'racha':      <String>[],
                };
              }
              // Actualizar siempre el equipo (queda el del partido mas reciente por orden asc)
              dts[coachId]!['equipo']     = teamName;
              dts[coachId]!['equipoId']   = luTeamId;
              dts[coachId]!['equipoLogo'] = teamLogo;
              if (dts[coachId]!['foto'] == null) dts[coachId]!['foto'] = coach['photo'];

              dts[coachId]!['partidos'] = (dts[coachId]!['partidos'] as int) + 1;
              if (gano)        dts[coachId]!['victorias'] = (dts[coachId]!['victorias'] as int) + 1;
              else if (empato) dts[coachId]!['empates']   = (dts[coachId]!['empates']   as int) + 1;
              else             dts[coachId]!['derrotas']  = (dts[coachId]!['derrotas']  as int) + 1;
              (dts[coachId]!['racha'] as List<String>).add(res2);

              final fechaStr = fm['fixture']?['date'] as String? ?? '';
              final fechaPartido = DateTime.tryParse(fechaStr);
              if (fechaPartido != null) {
                final prev = dts[coachId]!['_ultimaFecha'] as DateTime?;
                if (prev == null || fechaPartido.isAfter(prev)) {
                  dts[coachId]!['_ultimaFecha'] = fechaPartido;
                }
              }
            }
          } catch (_) {}
        }));
        if (i + loteSize < fixtures.length) {
          await Future.delayed(const Duration(milliseconds: 90));
        }
      }

      // Calcular stats finales
      final result = dts.values.map((dt) {
        final racha     = (dt['racha'] as List<String>);
        final partidos  = dt['partidos']  as int;
        final victorias = dt['victorias'] as int;
        final empates   = dt['empates']   as int;
        final derrotas  = dt['derrotas']  as int;
        final puntos    = victorias * 3 + empates;
        final pctPuntos = partidos > 0 ? (puntos / (partidos * 3) * 100) : 0.0;
        final ultimos5  = racha.length >= 5 ? racha.sublist(racha.length - 5) : List<String>.from(racha);

        String rachaActual = '';
        if (racha.isNotEmpty) {
          final ultimo = racha.last;
          int count = 0;
          for (int j = racha.length - 1; j >= 0; j--) {
            if (racha[j] == ultimo) count++;
            else break;
          }
          rachaActual = '$count$ultimo';
        }

        int trailingSinGanar = 0;
        for (int j = racha.length - 1; j >= 0; j--) {
          if (racha[j] == 'W') break;
          trailingSinGanar++;
        }
        final alertaSinGanar5 = trailingSinGanar >= 5;

        int trailingL = 0;
        for (int j = racha.length - 1; j >= 0; j--) {
          if (racha[j] != 'L') break;
          trailingL++;
        }
        final alertaTresDerrotas = trailingL >= 3;
        final alertaRoja = alertaSinGanar5 || alertaTresDerrotas;

        final ultima = dt['_ultimaFecha'] as DateTime?;
        final limite = DateTime.now().toUtc().subtract(const Duration(days: dtVentanaActividadDias));
        final dtEnActividad =
            ultima != null && ultima.toUtc().isAfter(limite);

        final limpio = Map<String, dynamic>.from(dt)..remove('_ultimaFecha');

        return <String, dynamic>{
          ...limpio,
          'puntos':      puntos,
          'pctPuntos':   pctPuntos,
          'rachaActual': rachaActual,
          'ultimos5':    ultimos5,
          'alertaSinGanar5': alertaSinGanar5,
          'alertaTresDerrotas': alertaTresDerrotas,
          'alertaRoja': alertaRoja,
          'ultimaFechaPartido': ultima?.toIso8601String(),
          'dtEnActividad': dtEnActividad,
        };
      }).toList()
        ..sort((a, b) => (b['pctPuntos'] as double).compareTo(a['pctPuntos'] as double));

      if (epochAtStart == _tablaDTsEpoch) {
        _tablaDTsCache = result;
      }
      return result;
    } catch (e) {
      return _tablaDTsCache ?? [];
    }
  }

  /// Color ARGB para UI según índice de presión (0–100).
  static int _presionColorValue(double p) {
    if (p >= 72) return 0xFFFF5252;
    if (p >= 55) return 0xFFFF7043;
    if (p >= 40) return 0xFFFF9800;
    if (p >= 25) return 0xFFFFC107;
    return 0xFF00C853;
  }

  /// Combina % de puntos, racha actual y últimos 5 en un índice 0–100 (más = más presión).
  static Map<String, dynamic> _metadataPresionDT(Map<String, dynamic> dt) {
    final pct = (dt['pctPuntos'] as num?)?.toDouble() ?? 0;
    final rachaActual = dt['rachaActual'] as String? ?? '';
    final ultimos5 = (dt['ultimos5'] as List?)?.cast<String>() ?? [];
    final partidos = (dt['partidos'] as int?) ?? 0;

    double presion = (100.0 - pct) * 0.40;

    if (rachaActual.isNotEmpty) {
      final last = rachaActual[rachaActual.length - 1];
      final nStr = rachaActual.substring(0, rachaActual.length - 1);
      final n = int.tryParse(nStr) ?? 1;
      if (last == 'L') {
        presion += (n * 8.0).clamp(0, 42);
      } else if (last == 'W') {
        presion -= (n * 6.5).clamp(0, 32);
      } else if (last == 'D') {
        presion += (n * 1.8).clamp(0, 10);
      }
    }

    for (final r in ultimos5) {
      if (r == 'L') presion += 4.8;
      if (r == 'W') presion -= 3.2;
      if (r == 'D') presion += 1.2;
    }

    if (partidos < 4) {
      presion *= (partidos / 4).clamp(0.35, 1.0);
    }

    if (dt['alertaSinGanar5'] == true) presion += 16;
    if (dt['alertaTresDerrotas'] == true) presion += 12;

    presion = presion.clamp(0.0, 100.0);

    String label;
    if (presion >= 80) {
      label = 'Cuerda floja';
    } else if (presion >= 62) {
      label = 'Riesgo alto';
    } else if (presion >= 45) {
      label = 'Caliente';
    } else if (presion >= 28) {
      label = 'En observación';
    } else {
      label = 'Relativamente estable';
    }

    var color = _presionColorValue(presion);
    if (dt['alertaRoja'] == true) color = 0xFFFF5252;

    return {
      'presion': presion,
      'presionLabel': label,
      'presionColor': color,
    };
  }

  /// Solo DT de clubes de la Liga Profesional (standings), en actividad; presión y orden por riesgo.
  /// Los datos (PJ, racha, alertas) ya incluyen Liga + Copa Arg. + copas int. del lado argentino.
  static Future<List<Map<String, dynamic>>> getCuerdaFloja({bool forceRefresh = false}) async {
    final dts = await getTablaDTs(forceRefresh: forceRefresh);
    final lpfIds = await _teamIdsLigaProfesional();
    final activos = dts.where((d) {
      if (d['dtEnActividad'] != true) return false;
      if (lpfIds.isEmpty) return true;
      final id = _idFromDynamic(d['equipoId']);
      if (id == null) return false;
      return lpfIds.contains(id);
    }).toList();
    final withP = activos.map((dt) {
      final meta = _metadataPresionDT(dt);
      return <String, dynamic>{...dt, ...meta};
    }).toList();
    withP.sort((a, b) =>
        ((b['presion'] as num?)?.toDouble() ?? 0).compareTo((a['presion'] as num?)?.toDouble() ?? 0));
    try {
      await _enriquecerFotosCuerdaFloja(withP)
          .timeout(const Duration(seconds: 14));
    } catch (_) {}
    return withP;
  }

  static int _intFromApi(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// True si el endpoint /coachs devolvió algo útil para mostrar (carrera, edad, etc.).
  static bool carreraDTTieneValor(Map<String, dynamic> m) {
    if (m.isEmpty) return false;
    final career = m['carrera'];
    if (career is List && career.isNotEmpty) return true;
    if (_intFromApi(m['edad']) > 0) return true;
    final nat = (m['nacionalidad'] as String?)?.trim() ?? '';
    if (nat.isNotEmpty) return true;
    final foto = (m['foto'] as String?)?.trim() ?? '';
    if (foto.isNotEmpty) return true;
    if (_intFromApi(m['aniosExp']) > 0) return true;
    return _intFromApi(m['totalClubes']) > 0;
  }

  /// Lineups a veces vienen sin `photo`; el detalle por id suele traerla.
  static Future<void> _enriquecerFotosCuerdaFloja(List<Map<String, dynamic>> lista) async {
    const lote = 5;
    for (var i = 0; i < lista.length; i += lote) {
      final chunk = lista.skip(i).take(lote).toList();
      await Future.wait(chunk.map((dt) async {
        final f = dt['foto'] as String?;
        if (f != null && f.isNotEmpty) return;
        final cid = dt['id'] as String? ?? '';
        if (cid.isEmpty) return;
        try {
          final r = await http
              .get(
                Uri.parse('$_baseUrl/coachs?id=$cid'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 12));
          if (r.statusCode != 200) return;
          final decoded = jsonDecode(r.body);
          final list = decoded is Map<String, dynamic> ? decoded['response'] : null;
          if (list is! List || list.isEmpty) return;
          final first = list[0];
          if (first is! Map<String, dynamic>) return;
          final ph = first['photo'] as String?;
          if (ph != null && ph.isNotEmpty) dt['foto'] = ph;
        } catch (_) {}
      }));
      if (i + lote < lista.length) {
        await Future.delayed(const Duration(milliseconds: 140));
      }
    }
  }

  /// Carga perfil y carrera del DT actual del club [teamId] (ID de equipo, no de coach).
  static Future<Map<String, dynamic>> getCarreraDT(String teamId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/coachs?team=$teamId'),
        headers: _headers,
      );
      if (res.statusCode != 200) return {};
      final data = jsonDecode(res.body)['response'] as List;
      if (data.isEmpty) return {};

      // Buscar DT actual (end == null para este equipo)
      final tid = int.tryParse(teamId) ?? 0;
      Map<String, dynamic>? coach;
      for (final c in data) {
        final career = (c['career'] as List?) ?? [];
        for (final cargo in career) {
          if ((cargo['team'] as Map?)?['id'] == tid && cargo['end'] == null) {
            coach = c as Map<String, dynamic>;
            break;
          }
        }
        if (coach != null) break;
      }
      coach ??= data[0] as Map<String, dynamic>;

      final career = (coach['career'] as List?) ?? [];
      String primerAnio = '';
      if (career.isNotEmpty) {
        final primero = career.last;
        primerAnio = ((primero['start'] as String?) ?? '').length >= 4
            ? (primero['start'] as String).substring(0, 4) : '';
      }
      final anioInicio = int.tryParse(primerAnio) ?? 0;
      final ph = coach['photo'] as String? ?? '';
      final nat = coach['nationality'];

      return {
        'edad':         _intFromApi(coach['age']),
        'nacionalidad': nat == null ? '' : nat.toString(),
        'foto':         ph,
        'aniosExp':     anioInicio > 0 ? (_season - anioInicio) : 0,
        'totalClubes':  career.length,
        'carrera':      career,
      };
    } catch (e) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getStatsEquipo(int teamId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/statistics?team=$teamId&season=$_season&league=$_ligaArgentina'),
        headers: _headers,
      );
      if (response.statusCode != 200) return {};
      final data = jsonDecode(response.body);
      return Map<String, dynamic>.from(data['response'] ?? {});
    } catch (e) {
      return {};
    }
  }

  /// Estadísticas del equipo en un torneo concreto (copa); si la API no devuelve datos, cae a la Liga Prof.
  static Future<Map<String, dynamic>> getStatsEquipoTorneo(
      int teamId, int leagueId, int season) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/teams/statistics?team=$teamId&season=$season&league=$leagueId'),
        headers: _headers,
      );
      if (response.statusCode != 200) return getStatsEquipo(teamId);
      final data = jsonDecode(response.body);
      final raw = data['response'];
      if (raw == null) return getStatsEquipo(teamId);
      if (raw is Map && raw.isEmpty) return getStatsEquipo(teamId);
      return Map<String, dynamic>.from(raw as Map);
    } catch (_) {
      return getStatsEquipo(teamId);
    }
  }

  static Future<String> getAlertaIA({
    required String local,
    required String visitante,
    required String resultado,
    required String minuto,
    required Map<String, dynamic>? stats,
    required List<Map<String, dynamic>> eventos,
  }) async {
    try {
      String posLocal = '50%', posVisit = '50%';
      int tirosLocal = 0, tirosVisit = 0;
      int amarillasLocal = 0, amarillasVisit = 0;
      int rojasLocal = 0, rojasVisit = 0;

      if (stats != null && stats['response'] != null && (stats['response'] as List).length >= 2) {
        final statL = List<Map<String, dynamic>>.from(stats['response'][0]['statistics'] ?? []);
        final statV = List<Map<String, dynamic>>.from(stats['response'][1]['statistics'] ?? []);
        for (var s in statL) {
          if (s['type'] == 'Ball Possession') posLocal = s['value']?.toString() ?? '50%';
          if (s['type'] == 'Shots on Goal') tirosLocal = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
        }
        for (var s in statV) {
          if (s['type'] == 'Ball Possession') posVisit = s['value']?.toString() ?? '50%';
          if (s['type'] == 'Shots on Goal') tirosVisit = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
        }
      }

      final homeId = stats?['response']?[0]?['team']?['id'];
      for (var e in eventos) {
        final tipo = e['type'] ?? '';
        final detalle = e['detail'] ?? '';
        final esLocal = e['team']?['id'] == homeId;
        if (tipo == 'Card') {
          if (detalle == 'Yellow Card') { if (esLocal) amarillasLocal++; else amarillasVisit++; }
          if (detalle == 'Red Card') { if (esLocal) rojasLocal++; else rojasVisit++; }
        }
      }

      final ultimosEventos = eventos.reversed.take(5).where((e) {
        final t = e['type'] ?? '';
        return t == 'Goal' || t == 'Card' || t == 'Var';
      }).map((e) {
        final min = e['time']?['elapsed']?.toString() ?? '';
        final tipo = e['type'] ?? '';
        final jugador = e['player']?['name'] ?? '';
        final equipo = e['team']?['name'] ?? '';
        final detalle = e['detail'] ?? '';
        return "$min' $tipo ($detalle) - $jugador ($equipo)";
      }).join('\n');

      final prompt = 'Sos el analista de HDF Stats, una app argentina de fútbol. Analizá este partido EN VIVO con tono futbolero rioplatense, directo y apasionado. Máximo 3 oraciones cortas.\n\nPartido: $local $resultado $visitante (min $minuto)\nPosesión: $local $posLocal — $visitante $posVisit\nTiros al arco: $local $tirosLocal — $visitante $tirosVisit\nTarjetas: $local ${amarillasLocal}🟡 ${rojasLocal}🔴 — $visitante ${amarillasVisit}🟡 ${rojasVisit}🔴\nÚltimos eventos:\n$ultimosEventos\n\nDescribí qué está pasando: quién domina, momentum, peligro o algo llamativo. Usá emojis de fútbol. Sin asteriscos ni markdown.';

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': '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',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5',
          'max_tokens': 200,
          'messages': [{'role': 'user', 'content': prompt}],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['content'] as List?)?.first?['text'] as String? ?? 'Sin análisis disponible.';
      }
      return 'Sin análisis disponible.';
    } catch (e) {
      return 'Sin análisis disponible.';
    }
  }
  /// Copa Argentina (API-Sports id **130**). El 515 es otra competencia (Argelia U21).
  static const int _copaArgentina = 130;

  // Equipos de la liga para onboarding
  static Future<List<Map<String, dynamic>>> getEquiposLiga() async {
    try {
      final data = await _getStandingsData();
      if (data != null) {
        final standings = data['response'] as List;
        if (standings.isEmpty) return [];
        final grupos = standings[0]['league']['standings'] as List;
        final equipos = <Map<String, dynamic>>[];
        for (final grupo in grupos) {
          for (final e in (grupo as List)) {
            equipos.add({
              'id': e['team']['id'],
              'nombre': e['team']['name'],
              'escudo': e['team']['logo'],
            });
          }
        }
        // Deduplicar por ID
        final seen = <int>{};
        final unique = equipos.where((e) => seen.add(e['id'] as int)).toList();
        unique.sort((a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));
        return unique;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Copa Argentina - partidos del dia
  static Future<List<Map<String, dynamic>>> getPartidosCopa() async {
    final hoy = DateTime.now();
    final fecha = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    for (final season in [_season, 2025]) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/fixtures?league=$_copaArgentina&season=$season&date=$fecha'),
          headers: _headers,
        );
        if (response.statusCode == 200) {
          final fixtures = (jsonDecode(response.body)['response'] as List);
          if (fixtures.isNotEmpty) return fixtures.map((f) => f as Map<String, dynamic>).toList();
        }
      } catch (_) { continue; }
    }
    return [];
  }

  // Copa Argentina - fixture completo (prueba 2026 y 2025)
  static Future<List<Map<String, dynamic>>> getFixtureCopa() async {
    for (final season in [_season, 2025]) {
      try {
        final acc = <Map<String, dynamic>>[];
        var page = 1;
        while (true) {
          final response = await http.get(
            Uri.parse(
                '$_baseUrl/fixtures?league=$_copaArgentina&season=$season&page=$page'),
            headers: _headers,
          );
          if (response.statusCode != 200) break;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final fixtures = data['response'] as List? ?? [];
          for (final f in fixtures) {
            acc.add(f as Map<String, dynamic>);
          }
          final paging = data['paging'];
          final totalPages = paging is Map
              ? (paging['total'] as num?)?.toInt() ?? 1
              : 1;
          if (page >= totalPages || fixtures.isEmpty) break;
          page++;
        }
        if (acc.isNotEmpty) return acc;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

    // Copa Argentina - goleadores
  static Future<List<Map<String, dynamic>>> getGoleadoresCopa() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topscorers?league=$_copaArgentina&season=2025'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        return players.take(20).map((p) => {
          'nombre': p['player']['name'],
          'foto': p['player']['photo'],
          'equipo': p['statistics'][0]['team']['name'],
          'escudo': p['statistics'][0]['team']['logo'],
          'goles': p['statistics'][0]['goals']['total'] ?? 0,
          'partidos': p['statistics'][0]['games']['appearences'] ?? 0,
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }


  // Tabla Moral Acumulada con zonas
  // Calcula y guarda resultado moral de cada partido jugado
  static Future<Map<String, dynamic>> _calcularMoralFixture(Map<String, dynamic> fixture, Map<String, String> headers) async {
    final fId = fixture['fixture']['id'] as int;
    final homeId = fixture['teams']['home']['id'].toString();
    final awayId = fixture['teams']['away']['id'].toString();
    final homeName = fixture['teams']['home']['name'] as String;
    final awayName = fixture['teams']['away']['name'] as String;
    final glLocal = (fixture['goals']['home'] as num?)?.toInt() ?? 0;
    final glVisit = (fixture['goals']['away'] as num?)?.toInt() ?? 0;

    int moralL = glLocal;
    int moralV = glVisit;

    try {
      final statsResp = await http.get(
        Uri.parse('https://v3.football.api-sports.io/fixtures/statistics?fixture=$fId'),
        headers: headers,
      );
      if (statsResp.statusCode == 200) {
        final statsList = jsonDecode(statsResp.body)['response'] as List;
        if (statsList.length >= 2) {
          double posLocal = 50, posVisit = 50;
          int tirosLocal = 0, tirosVisit = 0, cornersLocal = 0, cornersVisit = 0;
          for (final s in (statsList[0]['statistics'] as List)) {
            final v = s['value']?.toString() ?? '0';
            if (s['type'] == 'Ball Possession') posLocal = double.tryParse(v.replaceAll('%','')) ?? 50;
            if (s['type'] == 'Shots on Goal') tirosLocal = int.tryParse(v) ?? 0;
            if (s['type'] == 'Corner Kicks') cornersLocal = int.tryParse(v) ?? 0;
          }
          for (final s in (statsList[1]['statistics'] as List)) {
            final v = s['value']?.toString() ?? '0';
            if (s['type'] == 'Ball Possession') posVisit = double.tryParse(v.replaceAll('%','')) ?? 50;
            if (s['type'] == 'Shots on Goal') tirosVisit = int.tryParse(v) ?? 0;
            if (s['type'] == 'Corner Kicks') cornersVisit = int.tryParse(v) ?? 0;
          }
          final difPos = posLocal - posVisit;
          final difTiros = tirosLocal - tirosVisit;
          final difCorners = cornersLocal - cornersVisit;
          double dominio = 0;
          if (difPos.abs() > 25) dominio += difPos > 0 ? 1.5 : -1.5;
          else if (difPos.abs() > 15) dominio += difPos > 0 ? 1.0 : -1.0;
          if (difTiros.abs() >= 3) dominio += difTiros > 0 ? 1.0 : -1.0;
          else if (difTiros.abs() >= 1) dominio += difTiros > 0 ? 0.5 : -0.5;
          if (difCorners.abs() >= 5) dominio += difCorners > 0 ? 0.5 : -0.5;
          final diferencia = (glLocal - glVisit).abs();
          final ajuste = dominio.round().clamp(-1, 1);
          moralL += ajuste; moralV -= ajuste;
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
        }
      }
    } catch (_) {}

    // Guardar en Firestore
    try {
      await FirebaseFirestore.instance
          .collection('resultados_morales')
          .doc(fId.toString())
          .set({
        'fixtureId': fId,
        'homeId': homeId,
        'awayId': awayId,
        'homeNombre': homeName,
        'awayNombre': awayName,
        'moralLocal': moralL,
        'moralVisitante': moralV,
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    return {
      'fixtureId': fId,
      'homeId': homeId,
      'awayId': awayId,
      'moralLocal': moralL,
      'moralVisitante': moralV,
    };
  }

  /// Tabla moral = solo fase de liga por fechas. Excluye play-offs bajo el mismo league id.
  /// API-Sports: a veces `Regular Season - N`, en LPF 2026 suele ser `Apertura - N` / `Clausura - N`;
  /// excluye `Apertura - Round of 16`, octavos/cuartos/semis/final, etc.
  /// También usado por [getTablasTiempos] (1er y 2do tiempo): mismos partidos que la moral.
  static bool _fixtureCuentaParaTablaMoral(Map<String, dynamic> f) {
    final round = (f['league']?['round'] as String? ?? '').trim();
    if (round.isEmpty) return false;
    if (_esRondaPlayoffsLigaArg(round)) return false;
    final lower = round.toLowerCase();
    if (lower.contains('play-off') || lower.contains('playoff')) return false;
    if (lower.contains('round of')) return false;
    if (lower.contains('relegation') || lower.contains('descenso')) return false;
    if (round.contains('Regular Season')) return true;
    if (RegExp(r'^(Apertura|Clausura) - \d+$').hasMatch(round)) return true;
    return false;
  }

  static Map<String, List<Map<String, dynamic>>> _copyTablaMoral(
      Map<String, List<Map<String, dynamic>>> src) {
    return {
      for (final e in src.entries)
        e.key: e.value.map((m) => Map<String, dynamic>.from(m)).toList(),
    };
  }

  static Future<Map<String, List<Map<String, dynamic>>>> getTablaMoral() async {
    const ttl = Duration(seconds: 90);
    final now = DateTime.now();
    if (_tablaMoralResultCache != null &&
        _tablaMoralResultCacheTime != null &&
        now.difference(_tablaMoralResultCacheTime!) < ttl) {
      return _copyTablaMoral(_tablaMoralResultCache!);
    }
    if (_tablaMoralInFlight != null) {
      return _copyTablaMoral(await _tablaMoralInFlight!);
    }
    _tablaMoralInFlight = _getTablaMoralInternal().then((m) {
      _tablaMoralResultCache = m;
      _tablaMoralResultCacheTime = DateTime.now();
      return m;
    }).whenComplete(() => _tablaMoralInFlight = null);
    return _copyTablaMoral(await _tablaMoralInFlight!);
  }

  static Future<Map<String, List<Map<String, dynamic>>>> _getTablaMoralInternal() async {
    try {
      // PASO 1: Standings + Fixtures usando cache global (1 request cada uno en toda la sesión)
      final standData = await _getStandingsData();
      final allFixtures = await _getFixturesData();

      final Map<String, String> equipoZona = {};
      final Map<String, int> ptsRealesMap = {};
      final Map<String, String> equipoLogo = {};

      if (standData != null) {
        final standings = standData['response'][0]['league']['standings'] as List;
        for (int i = 0; i < standings.length; i++) {
          final grupo = standings[i] as List;
          if (grupo.isEmpty) continue;
          // Leer zona del campo 'group' real de la API
          final groupStr = (grupo[0]['group'] as String? ?? '').toLowerCase();
          if (!groupStr.contains('apertura')) continue;
          final zona = groupStr.contains('group b') ? 'Zona B' : 'Zona A';
          for (final e in grupo) {
            final id = e['team']['id'].toString();
            equipoZona[id] = zona;
            ptsRealesMap[id] = (e['points'] as num?)?.toInt() ?? 0;
            equipoLogo[id] = e['team']['logo'] as String? ?? '';
          }
        }
      }

      final jugados = allFixtures.where((f) {
        final m = Map<String, dynamic>.from(f as Map);
        final s = m['fixture']['status']['short'];
        if (s != 'FT' && s != 'AET' && s != 'PEN') return false;
        return _fixtureCuentaParaTablaMoral(m);
      }).toList();

      // PASO 2: Leer Firestore
      final firestoreSnap = await FirebaseFirestore.instance
          .collection('resultados_morales')
          .get();
      final Map<String, Map<String, dynamic>> morales = {
        for (final d in firestoreSnap.docs) d.id: d.data()
      };

      // PASO 3: Para fixtures que faltan en Firestore → calcular con GOLES ÚNICAMENTE
      // (sin llamar a /fixtures/statistics — cero 429)
      if (jugados.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        bool hayNuevos = false;
        for (final f in jugados) {
          final fId = f['fixture']['id'].toString();
          if (morales.containsKey(fId)) continue;
          final homeId = f['teams']['home']['id'].toString();
          final awayId = f['teams']['away']['id'].toString();
          final glL = (f['goals']['home'] as num?)?.toInt() ?? 0;
          final glV = (f['goals']['away'] as num?)?.toInt() ?? 0;
          final doc = {
            'fixtureId': int.parse(fId),
            'homeId': homeId,
            'awayId': awayId,
            'homeNombre': f['teams']['home']['name'] as String,
            'awayNombre': f['teams']['away']['name'] as String,
            'moralLocal': glL,
            'moralVisitante': glV,
            'ts': FieldValue.serverTimestamp(),
          };
          morales[fId] = doc;
          batch.set(
            FirebaseFirestore.instance.collection('resultados_morales').doc(fId),
            doc, SetOptions(merge: true),
          );
          hayNuevos = true;
        }
        if (hayNuevos) await batch.commit();
      }

     if (morales.isEmpty && jugados.isEmpty) return {};

// PASO 4: Construir tabla desde jugados (API) — IDs siempre correctos
final Map<String, Map<String, dynamic>> tabla = {};
for (final f in jugados) {
  final fId = f['fixture']['id'].toString();
  final homeId = f['teams']['home']['id'].toString();
  final awayId = f['teams']['away']['id'].toString();
  final moralData = morales[fId];
  final data = moralData ?? {
    'homeId': homeId,
    'awayId': awayId,
    'homeNombre': f['teams']['home']['name'] as String,
    'awayNombre': f['teams']['away']['name'] as String,
    'moralLocal': (f['goals']['home'] as num?)?.toInt() ?? 0,
    'moralVisitante': (f['goals']['away'] as num?)?.toInt() ?? 0,
  };
  if (homeId.isEmpty || awayId.isEmpty) continue;
        final moralL = (data['moralLocal'] as num?)?.toInt() ?? 0;
        final moralV = (data['moralVisitante'] as num?)?.toInt() ?? 0;
        final zonaH = equipoZona[homeId] ?? 'Zona A';
        final zonaV = equipoZona[awayId] ?? 'Zona A';

        tabla.putIfAbsent(homeId, () => {
          'nombre': data['homeNombre'] ?? '',
          'logo': equipoLogo[homeId] ?? '',
          'zona': zonaH, 'pj': 0, 'g': 0, 'e': 0, 'p': 0,
          'gf': 0, 'gc': 0, 'pts': 0, 'ptsReal': ptsRealesMap[homeId] ?? 0,
        });
        tabla.putIfAbsent(awayId, () => {
          'nombre': data['awayNombre'] ?? '',
          'logo': equipoLogo[awayId] ?? '',
          'zona': zonaV, 'pj': 0, 'g': 0, 'e': 0, 'p': 0,
          'gf': 0, 'gc': 0, 'pts': 0, 'ptsReal': ptsRealesMap[awayId] ?? 0,
        });

        if (equipoLogo[homeId] != null) tabla[homeId]!['logo'] = equipoLogo[homeId]!;
        if (equipoLogo[awayId] != null) tabla[awayId]!['logo'] = equipoLogo[awayId]!;
        if (equipoZona[homeId] != null) tabla[homeId]!['zona'] = equipoZona[homeId]!;
        if (equipoZona[awayId] != null) tabla[awayId]!['zona'] = equipoZona[awayId]!;
        if (ptsRealesMap[homeId] != null) tabla[homeId]!['ptsReal'] = ptsRealesMap[homeId]!;
        if (ptsRealesMap[awayId] != null) tabla[awayId]!['ptsReal'] = ptsRealesMap[awayId]!;

        tabla[homeId]!['pj'] = (tabla[homeId]!['pj'] as int) + 1;
        tabla[awayId]!['pj'] = (tabla[awayId]!['pj'] as int) + 1;
        tabla[homeId]!['gf'] = (tabla[homeId]!['gf'] as int) + moralL;
        tabla[homeId]!['gc'] = (tabla[homeId]!['gc'] as int) + moralV;
        tabla[awayId]!['gf'] = (tabla[awayId]!['gf'] as int) + moralV;
        tabla[awayId]!['gc'] = (tabla[awayId]!['gc'] as int) + moralL;
        if (moralL > moralV) {
          tabla[homeId]!['g'] = (tabla[homeId]!['g'] as int) + 1;
          tabla[homeId]!['pts'] = (tabla[homeId]!['pts'] as int) + 3;
          tabla[awayId]!['p'] = (tabla[awayId]!['p'] as int) + 1;
        } else if (moralV > moralL) {
          tabla[awayId]!['g'] = (tabla[awayId]!['g'] as int) + 1;
          tabla[awayId]!['pts'] = (tabla[awayId]!['pts'] as int) + 3;
          tabla[homeId]!['p'] = (tabla[homeId]!['p'] as int) + 1;
        } else {
          tabla[homeId]!['e'] = (tabla[homeId]!['e'] as int) + 1;
          tabla[homeId]!['pts'] = (tabla[homeId]!['pts'] as int) + 1;
          tabla[awayId]!['e'] = (tabla[awayId]!['e'] as int) + 1;
          tabla[awayId]!['pts'] = (tabla[awayId]!['pts'] as int) + 1;
        }
      }

      // PASO 5: Agrupar y ordenar
      final resultado = <String, List<Map<String, dynamic>>>{'Zona A': [], 'Zona B': []};
      for (final entry in tabla.entries) {
        final eq = {...entry.value, 'id': entry.key};
        resultado[eq['zona'] as String]?.add(eq);
      }
      for (final zona in resultado.keys) {
        resultado[zona]!.sort((a, b) {
          final d = (b['pts'] as int).compareTo(a['pts'] as int);
          if (d != 0) return d;
          return ((b['gf'] as int) - (b['gc'] as int))
              .compareTo((a['gf'] as int) - (a['gc'] as int));
        });
      }
      return resultado;
    } catch (e) {
      return {};
    }
  }

  // ══ MUNDIAL 2026 ══════════════════════════════════════════════════════════
  static const int _mundialId = 1;
  static const int _mundialSeason = 2026;
  static Map<String, List<Map<String, dynamic>>>? _mundialGruposCache;

  // Grupos del Mundial — 12 grupos A-L con 4 selecciones cada uno
  static Future<Map<String, List<Map<String, dynamic>>>> getMundialGrupos() async {
    if (_mundialGruposCache != null && _mundialGruposCache!.isNotEmpty) {
      return _mundialGruposCache!;
    }
    try {
      final uri = Uri.parse(
          '$_baseUrl/standings?league=$_mundialId&season=$_mundialSeason');
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null || (data['response'] as List).isEmpty) return {};
      final standings = data['response'][0]['league']['standings'] as List;
      final Map<String, List<Map<String, dynamic>>> grupos = {};
      for (final group in standings) {
        final zona = group as List;
        if (zona.isEmpty) continue;
        final groupName = zona[0]['group'] as String? ?? '';
        if (!groupName.startsWith('Group')) continue;
        grupos[groupName] = zona.map((e) => e as Map<String, dynamic>).toList();
      }
      _mundialGruposCache = grupos;
      return grupos;
    } catch (e) {
      return {};
    }
  }

  // Fixture del Mundial — todos los partidos de grupos
  static Future<List<Map<String, dynamic>>> getMundialFixture({String? fecha}) async {
    try {
      var url = '$_baseUrl/fixtures?league=$_mundialId&season=$_mundialSeason&timezone=America/Argentina/Buenos_Aires';
      if (fecha != null) url += '&date=$fecha';
      final uri = Uri.parse(url);
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null) return [];
      final fixtures = (data['response'] as List)
          .map((f) => f as Map<String, dynamic>)
          .toList();
      fixtures.sort((a, b) {
        final da = DateTime.tryParse(a['fixture']['date'] as String? ?? '') ?? DateTime(2026);
        final db = DateTime.tryParse(b['fixture']['date'] as String? ?? '') ?? DateTime(2026);
        return da.compareTo(db);
      });
      return fixtures;
    } catch (e) {
      return [];
    }
  }

  // Goleadores del Mundial
  static Future<List<Map<String, dynamic>>> getMundialGoleadores() async {
    try {
      final uri = Uri.parse(
          '$_baseUrl/players/topscorers?league=$_mundialId&season=$_mundialSeason');
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null) return [];
      return (data['response'] as List)
          .map((p) => p as Map<String, dynamic>)
          .take(20)
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Proximos partidos del Mundial (hoy y mañana)
  static Future<List<Map<String, dynamic>>> getMundialHoy() async {
    try {
      final hoy = DateTime.now().toLocal();
      final fechaStr = '${hoy.year}-${hoy.month.toString().padLeft(2,'0')}-${hoy.day.toString().padLeft(2,'0')}';
      final uri = Uri.parse(
          '$_baseUrl/fixtures?league=$_mundialId&season=$_mundialSeason&date=$fechaStr&timezone=America/Argentina/Buenos_Aires');
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null) return [];
      return (data['response'] as List).map((f) => f as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }
  // ══ FIN MUNDIAL 2026 ══════════════════════════════════════════════════════


  // Plantel de selección para el Mundial
  static Future<List<dynamic>> getPlantelSeleccion(int teamId) async {
    try {
      final uri = Uri.parse('$_baseUrl/players/squads?team=$teamId');
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null || (data['response'] as List).isEmpty) return [];
      return (data['response'][0]['players'] as List);
    } catch (e) { return []; }
  }

  // Plantel LPF — usa /players?league&season&team para obtener datos completos
  static Future<List<dynamic>> getPlantillaClub(int teamId) async {
    try {
      final List<dynamic> todos = [];
      int page = 1;
      while (true) {
        final uri = Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&team=$teamId&page=$page');
        final res = await http.get(uri, headers: _headers);
        if (res.statusCode != 200) break;
        final data = jsonDecode(res.body);
        final players = data['response'] as List? ?? [];
        todos.addAll(players);
        final totalPages = data['paging']?['total'] as int? ?? 1;
        if (page >= totalPages) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 90));
      }
      return todos;
    } catch (e) { return []; }
  }

  // Stats de jugadores en el Mundial 2026
  static Future<List<dynamic>> getStatsCopaJugadores(int teamId) async {
    try {
      final uri = Uri.parse('$_baseUrl/players?league=$_mundialId&season=$_mundialSeason&team=$teamId');
      final res = await http.get(uri, headers: _headers);
      final data = jsonDecode(res.body);
      if (data['response'] == null) return [];
      return data['response'] as List;
    } catch (e) { return []; }
  }

  // Carrera histórica de jugadores en selección
  static Future<List<dynamic>> getCarreraJugadoresSeleccion(int teamId) async {
    try {
      final squad = await getPlantelSeleccion(teamId);
      if (squad.isEmpty) return [];
      // Máx. 10 jugadores; en paralelo (antes: 10 × HTTP en serie + 300 ms → ~3 s solo en esperas).
      final top = squad.take(10).toList();
      Future<dynamic> fetchRow(dynamic p) async {
        final playerId = p['id'] as int?;
        if (playerId == null) return null;
        try {
          final uri = Uri.parse('$_baseUrl/players?id=$playerId&season=2024');
          final res = await http.get(uri, headers: _headers);
          final data = jsonDecode(res.body);
          if (data['response'] != null && (data['response'] as List).isNotEmpty) {
            return data['response'][0];
          }
        } catch (_) {}
        return null;
      }

      final outs = await Future.wait(top.map(fetchRow));
      return outs.where((e) => e != null).toList();
    } catch (e) {
      return [];
    }
  }



  // ══ NOTICIAS RSS ══════════════════════════════════════════════════════════
  // Mapeo de equipos a keywords para filtrar noticias
  static const Map<int, List<String>> _teamKeywords = {
    435: ['River', 'River Plate', 'Millonario'],
    433: ['Boca', 'Boca Juniors', 'Xeneize'],
    440: ['Racing', 'Racing Club', 'Academia'],
    436: ['Independiente'],
    437: ['San Lorenzo', 'Ciclón'],
    438: ['Huracán', 'Huracan', 'Quemero'],
    442: ['Vélez', 'Velez', 'Fortín'],
    432: ['Talleres'],
    443: ['Belgrano'],
    444: ['Estudiantes'],
    445: ['Gimnasia'],
    446: ['Rosario Central', 'Central'],
    447: ['Newell\'s', 'Newells', 'Lepra'],
    450: ['Lanús', 'Lanus', 'Granate'],
    451: ['Banfield'],
    452: ['Arsenal'],
    453: ['Tigre'],
    454: ['Quilmes'],
    455: ['Platense'],
    456: ['Sarmiento'],
    457: ['Colón', 'Colon'],
    458: ['Unión', 'Union'],
    459: ['Atlético Tucumán', 'Atletico Tucuman', 'Decano'],
    460: ['Godoy Cruz', 'Tomba'],
    461: ['Instituto'],
    462: ['Riestra', 'Deportivo Riestra'],
    463: ['Aldosivi'],
    464: ['Barracas Central'],
    465: ['Argentinos Juniors', 'Argentinos', 'Bicho'],
  };

  static List<String> _getKeywordsForTeam(int? teamId, String? teamName) {
    if (teamId != null && _teamKeywords.containsKey(teamId)) {
      return _teamKeywords[teamId]!;
    }
    if (teamName != null && teamName.isNotEmpty) {
      // Fallback: use team name parts
      final parts = teamName.split(' ').where((p) => p.length > 3).toList();
      return [teamName, ...parts];
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getNoticias({
    int? teamId,
    String? teamName,
  }) async {
    final feeds = [
      'https://www.ole.com.ar/rss/futbol-argentino.xml',
      'https://www.tycsports.com/rss.xml',
      'https://www.espn.com.ar/rss/futbol/nota',
    ];

    final keywords = _getKeywordsForTeam(teamId, teamName);
    final allNoticias = <Map<String, dynamic>>[];

    for (final feedUrl in feeds) {
      try {
        final response = await http.get(
          Uri.parse(feedUrl),
          headers: {'Accept': 'application/rss+xml, application/xml, text/xml'},
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final body = response.body;
          final items = _parseRss(body, feedUrl);
          allNoticias.addAll(items);
        }
      } catch (_) {}
    }

    // Filter to Argentina-only news
    const argKeywords = [
      'liga profesional', 'lpf', 'apertura', 'clausura', 'afa', 
      'boca', 'river', 'racing', 'independiente', 'san lorenzo',
      'huracán', 'huracan', 'vélez', 'velez', 'talleres', 'belgrano',
      'estudiantes', 'gimnasia', 'rosario central', 'newell', 'lanús', 'lanus',
      'banfield', 'tigre', 'platense', 'sarmiento', 'colón', 'colon',
      'unión', 'union', 'atlético tucumán', 'atletico tucuman', 'godoy cruz',
      'instituto', 'riestra', 'aldosivi', 'barracas', 'argentinos juniors',
      'quilmes', 'arsenal', 'zona a', 'zona b', 'torneo apertura', 'torneo clausura',
      'bombonera', 'monumental', 'superclásico', 'superclasico',
    ];

    final argNoticias = allNoticias.where((n) {
      final title = (n['titulo'] as String? ?? '').toLowerCase();
      final desc = (n['descripcion'] as String? ?? '').toLowerCase();
      return argKeywords.any((kw) => title.contains(kw) || desc.contains(kw));
    }).toList();

    // Filter by team keywords if provided
    if (keywords.isNotEmpty) {
      final filtered = argNoticias.where((n) {
        final title = (n['titulo'] as String? ?? '').toLowerCase();
        final desc = (n['descripcion'] as String? ?? '').toLowerCase();
        return keywords.any((kw) =>
          title.contains(kw.toLowerCase()) ||
          desc.contains(kw.toLowerCase()));
      }).toList();
      if (filtered.isNotEmpty) return filtered;
      return [];
    }

    return argNoticias;
  }

  static List<Map<String, dynamic>> _parseRss(String xml, String feedUrl) {
    final items = <Map<String, dynamic>>[];
    try {
      // Extract source name from URL
      String source = 'Noticias';
      if (feedUrl.contains('ole')) source = 'Olé';
      else if (feedUrl.contains('tyc')) source = 'TyC Sports';
      else if (feedUrl.contains('espn')) source = 'ESPN';

      // Find all <item> blocks
      final itemRegex = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
      final matches = itemRegex.allMatches(xml);

      for (final match in matches) {
        final itemXml = match.group(1) ?? '';

        final titulo = _extractTag(itemXml, 'title');
        final descripcion = _extractTag(itemXml, 'description');
        final link = _extractTag(itemXml, 'link');
        final pubDate = _extractTag(itemXml, 'pubDate');
        final imagen = _extractImage(itemXml);

        if (titulo.isNotEmpty) {
          items.add({
            'titulo': _cleanHtml(titulo),
            'descripcion': _cleanHtml(descripcion),
            'link': link,
            'fecha': _parseDate(pubDate),
            'imagen': imagen,
            'fuente': source,
          });
        }
        if (items.length >= 30) break;
      }
    } catch (_) {}
    return items;
  }

  static String _extractTag(String xml, String tag) {
    final regex = RegExp('<$tag[^>]*>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?<\\/$tag>',
        caseSensitive: false, dotAll: true);
    final match = regex.firstMatch(xml);
    return match?.group(1)?.trim() ?? '';
  }

  static String _extractImage(String xml) {
    // Try media:content, enclosure, or img in description
    final patterns = [
      RegExp(r'<media:content[^>]*url="([^"]+)"', caseSensitive: false),
      RegExp(r'<enclosure[^>]*url="([^"]+)"', caseSensitive: false),
      RegExp(r'<img[^>]*src="([^"]+)"', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(xml);
      if (m != null) return m.group(1) ?? '';
    }
    return '';
  }

  static String _cleanHtml(String text) {
    return text
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  }

  static String _parseDate(String pubDate) {
    try {
      final dt = DateTime.parse(pubDate);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
      return 'Hace ${diff.inDays} días';
    } catch (_) {
      // Try RFC 822 format (common in RSS)
      try {
        // Simple extraction of day/month
        final parts = pubDate.split(' ');
        if (parts.length >= 4) return '${parts[1]} ${parts[2]}';
      } catch (_) {}
      return '';
    }
  }
  // ══ FIN NOTICIAS RSS ══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getEquipoDeFecha() async {
    try {
      final allFixtures = await _getFixturesData();
      int maxRound = 0;
      for (var f in allFixtures) {
        final status = f['fixture']['status']['short'] as String? ?? '';
        final round = f['league']['round'] as String? ?? '';
        if ((status == 'FT' || status == 'AET' || status == 'PEN') &&
            round.contains('Regular Season')) {
          final parts = round.split('- ');
          if (parts.length == 2) {
            final n = int.tryParse(parts[1].trim()) ?? 0;
            if (n > maxRound) maxRound = n;
          }
        }
      }
      if (maxRound == 0) return [];
      final roundStr = 'Regular Season - $maxRound';
      final fixtureIds = <int>[];
      for (var f in allFixtures) {
        final round = f['league']['round'] as String? ?? '';
        if (round == roundStr) {
          final id = f['fixture']['id'] as int?;
          if (id != null) fixtureIds.add(id);
        }
      }
      if (fixtureIds.isEmpty) return [];
      final results = await Future.wait(
        fixtureIds.map((id) => getPlayersPartido(id.toString())),
      );
      final Map<int, Map<String, dynamic>> best = {};
      for (var list in results) {
        for (var p in list) {
          final id = p['id'] as int;
          final r = p['rating'] as double;
          if (!best.containsKey(id) || r > (best[id]!['rating'] as double)) {
            best[id] = p;
          }
        }
      }
      final starters = best.values
          .where((p) => p['tieneRating'] == true && p['suplente'] == false)
          .toList();
      starters.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      return starters;
    } catch (e) {
      return [];
    }
  }

  // ── RACHAS DE EQUIPOS ────────────────────────────────────────────────────
  // Reutiliza _getFixturesData() — sin llamada extra a la API
  static Future<List<RachaEquipo>> getRachasEquipos({bool forceRefresh = false}) async {
    if (!forceRefresh && _rachasCache != null) return _rachasCache!;
    try {
      final fixtures = await _getFixturesData();
      final Map<int, Map<String, dynamic>> teamMap = {};

      for (final fixture in fixtures) {
        final status = fixture['fixture']?['status']?['short'] as String? ?? '';
        if (status != 'FT') continue;

        final homeTeam  = fixture['teams']?['home']  as Map<String, dynamic>? ?? {};
        final awayTeam  = fixture['teams']?['away']  as Map<String, dynamic>? ?? {};
        final homeGoals = fixture['goals']?['home']  as int?;
        final awayGoals = fixture['goals']?['away']  as int?;
        final dateStr   = fixture['fixture']?['date'] as String?;
        if (homeGoals == null || awayGoals == null || dateStr == null) continue;

        final fecha = DateTime.tryParse(dateStr);
        if (fecha == null) continue;

        final String homeRes, awayRes;
        if (homeGoals > awayGoals) { homeRes = 'W'; awayRes = 'L'; }
        else if (homeGoals == awayGoals) { homeRes = 'D'; awayRes = 'D'; }
        else { homeRes = 'L'; awayRes = 'W'; }

        _addPartidoRacha(teamMap, homeTeam['id'] as int, homeTeam['name'] as String,
            homeTeam['logo'] as String, PartidoRacha(fecha: fecha, resultado: homeRes, esLocal: true));
        _addPartidoRacha(teamMap, awayTeam['id'] as int, awayTeam['name'] as String,
            awayTeam['logo'] as String, PartidoRacha(fecha: fecha, resultado: awayRes, esLocal: false));
      }

      final rachas = <RachaEquipo>[];
      teamMap.forEach((id, data) {
        final partidos = (data['partidos'] as List<PartidoRacha>)
          ..sort((a, b) => b.fecha.compareTo(a.fecha));
        rachas.add(RachaEquipo.fromPartidos(
          teamId: id,
          teamName: data['name'] as String,
          teamLogo: data['logo'] as String,
          partidos: partidos,
        ));
      });
      rachas.sort((a, b) => a.teamName.compareTo(b.teamName));
      _rachasCache = rachas;
      return rachas;
    } catch (e) {
      return _rachasCache ?? [];
    }
  }

  static void _addPartidoRacha(Map<int, Map<String, dynamic>> map,
      int id, String name, String logo, PartidoRacha partido) {
    map.putIfAbsent(id, () => {'name': name, 'logo': logo, 'partidos': <PartidoRacha>[]});
    (map[id]!['partidos'] as List<PartidoRacha>).add(partido);
  }
  // ── FIN RACHAS ───────────────────────────────────────────────────────────

  // ── CLIMA ────────────────────────────────────────────────────────────────
  static const String _weatherKey = '7a9a478b04215760440c86834eb07620';

  static const Map<String, List<double>> _estadioCoords = {
    'Kempes': [-31.3609, -64.2372],
    'Monumental': [-34.5452, -58.4510],
    'Armando': [-34.6345, -58.3647],
    'Bombonera': [-34.6345, -58.3647],
    'Cilindro': [-34.6598, -58.3753],
    'Libertadores de América': [-34.6651, -58.3697],
    'Bidegain': [-34.6446, -58.4380],
    'Gasómetro': [-34.6446, -58.4380],
    'Ducó': [-34.6510, -58.4390],
    'Amalfitani': [-34.6360, -58.5270],
    'Grondona': [-34.6743, -58.3551],
    'Sola': [-34.7420, -58.2612],
    'Hirschi': [-34.9271, -57.9589],
    'Zerillo': [-34.9139, -57.9443],
    'Gigante': [-32.9363, -60.6704],
    'Bielsa': [-32.9488, -60.6635],
    'Madre de Ciudades': [-28.4534, -65.8698],
    'Malvinas': [-32.8956, -68.8539],
    'Villagra': [-31.4312, -64.1854],
    'Riestra': [-34.6261, -58.4631],
  };

  static List<double>? _coordsParaEstadio(String nombre) {
    for (final entry in _estadioCoords.entries) {
      if (nombre.toLowerCase().contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }

  static Future<Map<String, dynamic>> getClimaEstadio(String estadio, {DateTime? matchTime}) async {
    try {
      final coords = _coordsParaEstadio(estadio);
      if (coords == null) return {};
      final resp = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=${coords[0]}&lon=${coords[1]}&appid=$_weatherKey&units=metric&lang=es'
      )).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return {};
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final weather = (data['weather'] as List?)?.first as Map<String, dynamic>? ?? {};
      final main = data['main'] as Map<String, dynamic>? ?? {};
      final wind = data['wind'] as Map<String, dynamic>? ?? {};
      return {
        'descripcion': weather['description'] as String? ?? '',
        'temp': (main['temp'] as num?)?.round() ?? 0,
        'humedad': main['humidity'] as int? ?? 0,
        'viento': ((wind['speed'] as num?) ?? 0) * 3.6,
      };
    } catch (_) { return {}; }
  }

  static String climaEmoji(String descripcion) {
    final d = descripcion.toLowerCase();
    if (d.contains('tormenta') || d.contains('storm')) return '⛈️';
    if (d.contains('lluvia') || d.contains('rain') || d.contains('llovizna')) return '🌧️';
    if (d.contains('nieve') || d.contains('snow')) return '❄️';
    if (d.contains('niebla') || d.contains('fog')) return '🌫️';
    if (d.contains('nublado') || d.contains('cloud') || d.contains('nub')) return '☁️';
    if (d.contains('parcialmente') || d.contains('partly')) return '⛅';
    if (d.contains('despejado') || d.contains('clear') || d.contains('sol')) return '☀️';
    return '🌤️';
  }

  // ── PREVIEW EQUIPO (top rating + goleadores + edad promedio) ─────────────
  static Future<Map<String, dynamic>> getPreviewEquipo(int teamId) async {
    try {
      final uri = Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&team=$teamId&page=1');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) return {'rating': [], 'goles': [], 'promedioEdad': 0.0};
      final players = (jsonDecode(res.body)['response'] as List? ?? []).cast<Map<String, dynamic>>();
      final conStats = players.where((p) {
        final stats = (p['statistics'] as List?)?.first;
        return (stats?['games']?['appearences'] as int? ?? 0) > 0;
      }).map((p) {
        final stats = (p['statistics'] as List).first as Map<String, dynamic>;
        final ratingStr = stats['games']?['rating'] as String? ?? '0';
        final rating = double.tryParse(ratingStr) ?? 0.0;
        final goles = stats['goals']?['total'] as int? ?? 0;
        final foto = p['player']?['photo'] as String? ?? '';
        final nombre = p['player']?['name'] as String? ?? '';
        final edad = p['player']?['age'] as int? ?? 0;
        return {'nombre': nombre, 'foto': foto, 'rating': rating, 'goles': goles, 'edad': edad};
      }).toList();
      final edades = conStats.map((p) => p['edad'] as int? ?? 0).where((e) => e > 0).toList();
      final promedioEdad = edades.isNotEmpty ? edades.reduce((a, b) => a + b) / edades.length : 0.0;
      final porRating = List<Map<String, dynamic>>.from(conStats)
        ..removeWhere((p) => (p['rating'] as double) == 0.0)
        ..sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      final porGoles = List<Map<String, dynamic>>.from(conStats)
        ..removeWhere((p) => (p['goles'] as int) == 0)
        ..sort((a, b) => (b['goles'] as int).compareTo(a['goles'] as int));
      return {'rating': porRating.take(3).toList(), 'goles': porGoles.take(3).toList(), 'promedioEdad': promedioEdad};
    } catch (_) { return {'rating': [], 'goles': [], 'promedioEdad': 0.0}; }
  }

  // ── STANDINGS FOR TEAMS ───────────────────────────────────────────────────
  static Future<Map<int, Map<String, dynamic>>> getStandingsForTeams(int homeId, int awayId) async {
    try {
      final data = await _getStandingsData();
      final result = <int, Map<String, dynamic>>{};
      for (final league in (data['response'] as List? ?? [])) {
        for (final group in (league['league']?['standings'] as List? ?? [])) {
          for (final team in (group as List)) {
            final id = team['team']?['id'] as int?;
            if (id == homeId || id == awayId) {
              result[id!] = {'pos': team['rank'] as int? ?? 0, 'pts': team['points'] as int? ?? 0};
            }
          }
        }
      }
      return result;
    } catch (_) { return {}; }
  }

  // ── FOTO DE ESTADIO ──────────────────────────────────────────────────────
  static final Map<int, String?> _venueFotoCache = {};

  static Future<String?> getVenueFoto(int? venueId) async {
    if (venueId == null) return null;
    if (_venueFotoCache.containsKey(venueId)) return _venueFotoCache[venueId];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/venues?id=$venueId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) { _venueFotoCache[venueId] = null; return null; }
      final data = jsonDecode(res.body)['response'] as List? ?? [];
      if (data.isEmpty) { _venueFotoCache[venueId] = null; return null; }
      final foto = data[0]['image'] as String?;
      _venueFotoCache[venueId] = foto;
      return foto;
    } catch (_) {
      _venueFotoCache[venueId] = null;
      return null;
    }
  }

  static Future<Map<String, dynamic>> getIndiceMatchgol() async {
    const ttl = Duration(minutes: 15);
    final now = DateTime.now();
    if (_indiceMatchgolCache != null &&
        _indiceMatchgolCacheTime != null &&
        now.difference(_indiceMatchgolCacheTime!) < ttl) {
      return Map<String, dynamic>.from(_indiceMatchgolCache!);
    }
    if (_indiceMatchgolInFlight != null) {
      return Map<String, dynamic>.from(await _indiceMatchgolInFlight!);
    }
    _indiceMatchgolInFlight = _getIndiceMatchgolInternal().then((m) {
      _indiceMatchgolCache = m;
      _indiceMatchgolCacheTime = DateTime.now();
      return m;
    }).whenComplete(() => _indiceMatchgolInFlight = null);
    return Map<String, dynamic>.from(await _indiceMatchgolInFlight!);
  }

  static Future<Map<String, dynamic>> _getIndiceMatchgolInternal() async {
    try {
      final Map<int, Map<String, dynamic>> merged = {};
      final Set<int> seen = {};
      void absorb(List<dynamic> items) {
        for (final item in items) {
          final player = item['player'];
          final statsList = item['statistics'] as List? ?? [];
          if (player == null || statsList.isEmpty) continue;
          final st = statsList[0] as Map<String, dynamic>;
          final pidRaw = player['id'];
          final int? pid = pidRaw is int
              ? pidRaw
              : pidRaw is num
                  ? pidRaw.toInt()
                  : int.tryParse('$pidRaw');
          if (pid == null || pid == 0) continue;
          final double rating = double.tryParse(st['games']?['rating']?.toString() ?? '') ?? 0.0;
          if (!seen.contains(pid)) {
            seen.add(pid);
            merged[pid] = {'player': player, 'statistics': [st]};
          } else {
            final double existingRating = double.tryParse(merged[pid]!['statistics'][0]['games']?['rating']?.toString() ?? '') ?? 0.0;
            if (rating > existingRating) merged[pid] = {'player': player, 'statistics': [st]};
          }
        }
      }
      await Future.wait([
        () async {
          try {
            final r1 = await http.get(
                Uri.parse('$_baseUrl/players/topscorers?league=$_ligaArgentina&season=$_season'),
                headers: _headers);
            if (r1.statusCode == 200) absorb(jsonDecode(r1.body)['response'] as List? ?? []);
          } catch (_) {}
        }(),
        () async {
          try {
            final r2 = await http.get(
                Uri.parse('$_baseUrl/players/topassists?league=$_ligaArgentina&season=$_season'),
                headers: _headers);
            if (r2.statusCode == 200) absorb(jsonDecode(r2.body)['response'] as List? ?? []);
          } catch (_) {}
        }(),
      ]);

      Future<List<dynamic>?> fetchPlayersPage(int page) async {
        try {
          final res = await http.get(
            Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&page=$page'),
            headers: _headers,
          );
          if (res.statusCode != 200) return null;
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          return data['response'] as List?;
        } catch (_) {
          return null;
        }
      }

      var totalPages = 1;
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&page=1'),
          headers: _headers,
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final p = data['paging'];
          totalPages = p is Map ? (p['total'] as num?)?.toInt() ?? 1 : 1;
          absorb(data['response'] as List? ?? []);
        }
      } catch (_) {}

      const maxPages = 20;
      const batch = 4;
      final cap = totalPages > maxPages ? maxPages : totalPages;
      for (var start = 2; start <= cap; start += batch) {
        final ends = <int>[];
        for (var i = 0; i < batch && start + i <= cap; i++) {
          ends.add(start + i);
        }
        final chunks = await Future.wait(ends.map(fetchPlayersPage));
        for (final pl in chunks) {
          if (pl != null && pl.isNotEmpty) absorb(pl);
        }
        if (start + batch <= cap) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
      final List<Map<String, dynamic>> all = [];
      for (final item in merged.values) {
        final st = item['statistics'][0] as Map<String, dynamic>;
        final double rating = double.tryParse(st['games']?['rating']?.toString() ?? '') ?? 0.0;
        final int appeared = st['games']?['appearences'] as int? ?? 0;
        if (appeared < 1 || rating == 0.0) continue;
        final player = item['player'] as Map<String, dynamic>;
        all.add({'id': player['id'], 'name': player['name'] ?? '', 'photo': player['photo'] ?? '', 'pos': st['games']?['position'] ?? 'M', 'rating': rating, 'team': st['team']?['name'] ?? '', 'goals': st['goals']?['total'] ?? 0, 'assists': st['goals']?['assists'] ?? 0});
      }
      all.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      final Map<String, List<Map<String, dynamic>>> byPos = {'G': [], 'D': [], 'M': [], 'F': []};
      for (final p in all) {
        final rawPos = p['pos'] as String;
        final pos = rawPos == 'Goalkeeper' ? 'G' : rawPos == 'Defender' ? 'D' : rawPos == 'Midfielder' ? 'M' : rawPos == 'Attacker' ? 'F' : '';
        if (pos.isNotEmpty && byPos.containsKey(pos) && byPos[pos]!.length < 10) byPos[pos]!.add(p);
      }
      return {'best': all.isNotEmpty ? all[0] : <String, dynamic>{}, 'top10': all.take(10).toList(), 'byPos': byPos};
    } catch (e) {
      return {'best': <String, dynamic>{}, 'top10': <Map<String, dynamic>>[], 'byPos': {'G': [], 'D': [], 'M': [], 'F': []}};
    }
  }
  /// Último resultado de [getAlFilo]: si la lista se armó en modo playoffs (para subtítulos en UI).
  static bool ultimoAlFiloEsPlayoffsLiga = false;

  /// True si el calendario de Liga Argentina ya incluye rondas knockout (octavos en adelante).
  static Future<bool> ligaArgentinaHayPlayoffs() async {
    try {
      final todos = await getFixture();
      return _hayPlayoffsLigaArgEnFixtures(todos);
    } catch (_) {
      return false;
    }
  }

  static bool _hayPlayoffsLigaArgEnFixtures(List<Map<String, dynamic>> todos) {
    for (final f in todos) {
      if (_esRondaPlayoffsLigaArg(f['league']?['round'] as String?)) return true;
    }
    return false;
  }

  static bool _esRondaPlayoffsLigaArg(String? round) {
    if (round == null || round.isEmpty) return false;
    final r = round.toLowerCase();
    if (r.contains('regular season') || r.contains('fase regular')) return false;
    return r.contains('round of 16') ||
        r.contains('octavos') ||
        r.contains('1/8') ||
        r.contains('eighth') ||
        r.contains('quarter') ||
        r.contains('cuartos') ||
        r.contains('1/4') ||
        r.contains('semi') ||
        r.contains('final');
  }

  /// Amarillas solo en partidos knockout ya jugados; **nunca** suspensión por amarilla en playoffs.
  static Future<List<Map<String, dynamic>>> _getAlFiloAmarillasSoloPlayoffs(
      List<Map<String, dynamic>> todosFixture) async {
    final playoffFixtures = todosFixture
        .where((f) => _esRondaPlayoffsLigaArg(f['league']?['round'] as String?))
        .toList();
    final jugables = playoffFixtures.where((f) {
      final s = f['fixture']?['status']?['short'] as String? ?? '';
      return s == 'FT' || s == 'AET' || s == 'PEN';
    }).toList();

    final acumulado = <String, Map<String, dynamic>>{};
    var n = 0;
    for (final fixture in jugables) {
      final fixtureId = fixture['fixture']?['id'];
      if (fixtureId == null) continue;
      final homeId = fixture['teams']?['home']?['id'];
      final awayId = fixture['teams']?['away']?['id'];
      final homeName = fixture['teams']?['home']?['name'] as String? ?? '';
      final awayName = fixture['teams']?['away']?['name'] as String? ?? '';
      final homeLogo = fixture['teams']?['home']?['logo'] as String? ?? '';
      final awayLogo = fixture['teams']?['away']?['logo'] as String? ?? '';

      final evResponse = await http.get(
        Uri.parse('$_baseUrl/fixtures/events?fixture=$fixtureId'),
        headers: _headers,
      );
      if (evResponse.statusCode != 200) continue;
      final events = jsonDecode(evResponse.body)['response'] as List? ?? [];
      for (final e in events) {
        if ((e['type'] as String? ?? '') != 'Card') continue;
        final detail = (e['detail'] as String? ?? '').toLowerCase();
        if (!detail.contains('yellow')) continue;
        if (detail.contains('second yellow')) continue;

        final playerName = e['player']?['name'] as String? ?? '';
        if (playerName.isEmpty) continue;
        final playerId = e['player']?['id'];
        final teamId = e['team']?['id'];
        final isHome = teamId != null && homeId != null && teamId == homeId;
        final equipo = isHome ? homeName : awayName;
        final logoEquipo = isHome ? homeLogo : awayLogo;
        final key = '${playerId ?? playerName}-$teamId';

        acumulado.putIfAbsent(
          key,
          () => {
            'nombre': playerName,
            'foto': '',
            'equipo': equipo,
            'logoEquipo': logoEquipo,
            'amarillas': 0,
            'suspension': false,
            'playoffsLiga': true,
          },
        );
        acumulado[key]!['amarillas'] = (acumulado[key]!['amarillas'] as int) + 1;
      }
      n++;
      if (n % 5 == 0) await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final result = acumulado.values
        .where((j) {
          final am = j['amarillas'] as int? ?? 0;
          return am == 4 || am == 9;
        })
        .map((j) => Map<String, dynamic>.from(j))
        .toList();
    result.sort((a, b) => (b['amarillas'] as int).compareTo(a['amarillas'] as int));
    return result;
  }

  // ── AL FILO — jugadores con 4 o 9 amarillas ─────────────────
  static Future<List<Map<String, dynamic>>> getAlFilo() async {
    try {
      final todosFixture = await getFixture();
      final playoffs = _hayPlayoffsLigaArgEnFixtures(todosFixture);
      ultimoAlFiloEsPlayoffsLiga = playoffs;

      if (playoffs) {
        return await _getAlFiloAmarillasSoloPlayoffs(todosFixture);
      }

      final List<Map<String, dynamic>> result = [];
      int page = 1;
      int totalPages = 1;
      while (page <= totalPages && page <= 10) {
        final response = await http.get(
          Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&page=$page'),
          headers: _headers,
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          totalPages = data['paging']?['total'] as int? ?? 1;
          final players = data['response'] as List;
          for (final p in players) {
            final st = (p['statistics'] as List?)?.first as Map<String, dynamic>? ?? {};
            final amarillas = st['cards']?['yellow'] as int? ?? 0;
            if (amarillas == 4 || amarillas == 5 || amarillas == 9 || amarillas == 10) {
              result.add({
                'nombre': p['player']?['name'] ?? '',
                'foto': p['player']?['photo'] ?? '',
                'equipo': st['team']?['name'] ?? '',
                'logoEquipo': st['team']?['logo'] ?? '',
                'amarillas': amarillas,
                'suspension': amarillas == 5 || amarillas == 10,
                'playoffsLiga': false,
              });
            }
          }
        }
        page++;
      }
      result.sort((a, b) => (b['amarillas'] as int).compareTo(a['amarillas'] as int));
      return result;
    } catch (e) {
      ultimoAlFiloEsPlayoffsLiga = false;
      return [];
    }
  }
  // ── EXPULSADOS ÚLTIMA FECHA ──────────────────────────────────
  static Future<List<Map<String, dynamic>>> getExpulsadosUltimaFecha() async {
    try {
      final fixtures = await _getFixturesData();
      final jugados = fixtures.where((f) {
        final status = f['fixture']?['status']?['short'] as String? ?? '';
        return status == 'FT' || status == 'AET' || status == 'PEN';
      }).toList();
      if (jugados.isEmpty) return [];
      jugados.sort((a, b) {
        final da = DateTime.tryParse(a['fixture']?['date'] ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['fixture']?['date'] ?? '') ?? DateTime(2000);
        return db.compareTo(da);
      });
      final ultimaFecha = jugados.first['league']?['round'] as String? ?? '';
      final ultimaFechaFixtures = jugados.where((f) => f['league']?['round'] == ultimaFecha).toList();
      final List<Map<String, dynamic>> expulsados = [];
      for (final fixture in ultimaFechaFixtures) {
        final fixtureId = fixture['fixture']?['id'];
        if (fixtureId == null) continue;
        final evResponse = await http.get(
          Uri.parse('$_baseUrl/fixtures/events?fixture=$fixtureId&type=Card'),
          headers: _headers,
        );
        if (evResponse.statusCode == 200) {
          final data = jsonDecode(evResponse.body);
          final events = data['response'] as List;
          for (final ev in events) {
            final detail = ev['detail'] as String? ?? '';
           if (detail == 'Red Card' || detail == 'Second Yellow card') {
              expulsados.add({
                'nombre': ev['player']?['name'] ?? '',
                'foto': '',
                'equipo': ev['team']?['name'] ?? '',
                'logoEquipo': ev['team']?['logo'] ?? '',
                'minuto': '${ev['time']?['elapsed'] ?? ''}',
              });
            }
          }
        }
      }
      return expulsados;
    } catch (e) {
      return [];
    }
  }

  // ── PERFIL JUGADOR (carrera aproximada vía API) ───────────────────────────
  static Future<Map<String, dynamic>?> getPlayerProfileApi(int playerId) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players/profiles?player=$playerId'),
        headers: _headers,
      );
      if (r.statusCode != 200) return null;
      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = decoded['response'];
      Map<String, dynamic>? normalize(dynamic item) {
        if (item is! Map) return null;
        final m = Map<String, dynamic>.from(item);
        if (m.containsKey('player')) return m;
        return {'player': m};
      }
      if (raw is List && raw.isNotEmpty) {
        return normalize(raw.first);
      }
      if (raw is Map) {
        return normalize(raw);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Pares (teamId, season) devueltos por `players/teams`.
  static Future<List<Map<String, int>>> getPlayerTeamSeasonHistory(int playerId) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players/teams?player=$playerId'),
        headers: _headers,
      );
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body)['response'] as List? ?? [];
      final seen = <String, Map<String, int>>{};
      for (final row in list) {
        final tid = (row['team'] as Map<String, dynamic>?)?['id'] as int?;
        final seasons = row['seasons'] as List? ?? [];
        if (tid == null) continue;
        for (final s in seasons) {
          final y = s is int ? s : int.tryParse('$s') ?? 0;
          if (y <= 0) continue;
          seen['$tid-$y'] = {'team': tid, 'season': y};
        }
      }
      final out = seen.values.toList();
      out.sort((a, b) => (b['season']!).compareTo(a['season']!));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Filas para UI: nombre, escudo y año en cada club (`players/teams`).
  static Future<List<Map<String, dynamic>>> getPlayerClubsHistoryDisplay(
      int playerId) async {
    if (playerId <= 0) return [];
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players/teams?player=$playerId'),
        headers: _headers,
      );
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body)['response'] as List? ?? [];
      final rows = <Map<String, dynamic>>[];
      for (final row in list) {
        if (row is! Map) continue;
        final team = row['team'] as Map<String, dynamic>?;
        if (team == null) continue;
        final nombre = team['name'] as String? ?? '';
        final logo = team['logo'] as String? ?? '';
        final tid = (team['id'] as num?)?.toInt() ?? 0;
        final seasons = row['seasons'] as List? ?? [];
        for (final s in seasons) {
          final y = s is int ? s : int.tryParse('$s') ?? 0;
          if (y <= 0) continue;
          rows.add({
            'teamId': tid,
            'nombre': nombre,
            'logo': logo,
            'anio': y,
          });
        }
      }
      rows.sort((a, b) => (b['anio'] as int).compareTo(a['anio'] as int));
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Equipo de club más reciente del jugador, excluyendo la selección ([excluirTeamId]).
  static Future<Map<String, dynamic>?> getClubActualExcluyendoEquipo(
    int playerId,
    int excluirTeamId,
  ) async {
    if (playerId <= 0) return null;
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players/teams?player=$playerId'),
        headers: _headers,
      );
      if (r.statusCode != 200) return null;
      final list = jsonDecode(r.body)['response'] as List? ?? [];
      var bestYear = 0;
      Map<String, dynamic>? best;
      for (final row in list) {
        if (row is! Map) continue;
        final team = row['team'] as Map<String, dynamic>?;
        if (team == null) continue;
        final tid = team['id'] as int? ?? 0;
        if (tid == excluirTeamId || tid <= 0) continue;
        final seasons = row['seasons'] as List? ?? [];
        for (final s in seasons) {
          final y = s is int ? s : int.tryParse('$s') ?? 0;
          if (y > bestYear) {
            bestYear = y;
            best = {
              'id': tid,
              'nombre': team['name'] as String? ?? '',
              'logo': team['logo'] as String? ?? '',
              'temporada': y,
            };
          }
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchPlayerFullRow(int playerId) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players?id=$playerId'),
        headers: _headers,
      );
      if (r.statusCode != 200) return null;
      final resp = jsonDecode(r.body)['response'] as List?;
      if (resp == null || resp.isEmpty) return null;
      final first = resp.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _ligaStatEsSeleccion(Map<String, dynamic> stat) {
    final league = stat['league'];
    if (league is! Map) return false;
    final country = (league['country'] as String? ?? '').toLowerCase();
    final name = (league['name'] as String? ?? '').toLowerCase();
    if (country == 'world') return true;
    const keys = [
      'world cup',
      'copa america',
      'copa américa',
      'euro championship',
      'uefa nations',
      'nations league',
      'africa cup',
      'asian cup',
      'gold cup',
      'wc qualification',
      'world cup - qualification',
      'olympic',
      'olímpico',
      'friend',
    ];
    for (final k in keys) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  static Map<String, dynamic> _extraerDorsalYSeleccion(
    Map<String, dynamic>? apiRow,
    int? clubTeamId,
  ) {
    var dorsal = 0;
    var tieneSel = false;
    var pjSelTotal = 0;
    var golesSelTotal = 0;
    String? clubStatNombre;
    String? clubStatLogo;
    final detalles = <String>[];
    final stats = apiRow?['statistics'] as List? ?? [];
    Map<String, dynamic>? statClub;
    for (final raw in stats) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (_ligaStatEsSeleccion(m)) {
        tieneSel = true;
        final lname = m['league']?['name'] as String? ?? '';
        final season = m['season']?.toString() ?? '';
        final pj = (m['games']?['appearences'] as num?)?.toInt() ??
            (m['games']?['appearances'] as num?)?.toInt() ??
            0;
        final g = (m['goals']?['total'] as num?)?.toInt() ?? 0;
        pjSelTotal += pj;
        golesSelTotal += g;
        if (lname.isNotEmpty) {
          detalles.add(
              pj > 0 ? '$lname ($season) · $pj PJ' : '$lname ($season)');
        }
      }
      final tid = (m['team']?['id'] as num?)?.toInt();
      if (clubTeamId != null && tid == clubTeamId) {
        statClub = m;
        final teamMap = m['team'] as Map<String, dynamic>?;
        clubStatNombre = teamMap?['name'] as String? ?? clubStatNombre;
        clubStatLogo = teamMap?['logo'] as String? ?? clubStatLogo;
      }
    }
    statClub ??= stats.isNotEmpty && stats.first is Map
        ? Map<String, dynamic>.from(stats.first as Map)
        : null;
    if (statClub != null) {
      final g = statClub['games'] as Map<String, dynamic>?;
      final n = g?['number'];
      dorsal = n is int ? n : int.tryParse('$n') ?? 0;
    }
    return {
      'dorsal': dorsal,
      'tieneSeleccion': tieneSel,
      'seleccionPjTotal': pjSelTotal,
      'seleccionGolesTotal': golesSelTotal,
      'clubStatNombre': clubStatNombre,
      'clubStatLogo': clubStatLogo,
      'seleccionDetalle':
          detalles.isNotEmpty ? detalles.take(5).join('\n') : null,
    };
  }

  static Future<Map<String, int>?> _fetchPlayerSeasonStatsTriple(
    int playerId,
    int teamId,
    int season,
  ) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/players?id=$playerId&team=$teamId&season=$season'),
        headers: _headers,
      );
      if (r.statusCode != 200) return null;
      final resp = jsonDecode(r.body)['response'] as List?;
      if (resp == null || resp.isEmpty) return {'pj': 0, 'g': 0, 'r': 0};
      final stats = resp.first['statistics'] as List?;
      if (stats == null || stats.isEmpty) return {'pj': 0, 'g': 0, 'r': 0};
      final st = stats.first as Map<String, dynamic>;
      final pj = (st['games']?['appearences'] as num?)?.toInt() ?? 0;
      final g = (st['goals']?['total'] as num?)?.toInt() ?? 0;
      final red = (st['cards']?['red'] as num?)?.toInt() ?? 0;
      final yred = (st['cards']?['yellowred'] as num?)?.toInt() ?? 0;
      return {'pj': pj, 'g': g, 'r': red + yred};
    } catch (_) {
      return null;
    }
  }

  /// Agrega PJ / goles / rojas recorriendo historial club+temporada (tope de requests).
  static Future<Map<String, dynamic>> getPlayerCareerSnapshot({
    required int playerId,
    required int clubTeamId,
  }) async {
    final inicio = await Future.wait([
      getPlayerProfileApi(playerId),
      getPlayerTeamSeasonHistory(playerId),
    ]);
    final profileResp = inicio[0] as Map<String, dynamic>?;
    final rawPairs = (inicio[1] as List<Map<String, int>>).toList();

    final player = profileResp?['player'] as Map<String, dynamic>? ?? {};
    final nombre = player['name'] as String? ?? '';
    final foto = player['photo'] as String? ?? '';
    final age = (player['age'] as num?)?.toInt();
    final birthMap = player['birth'];
    final birth = birthMap is Map<String, dynamic> ? birthMap['date'] as String? : null;
    final birthCountry =
        birthMap is Map<String, dynamic> ? birthMap['country'] as String? : null;
    final nacionalidad = player['nationality'] as String?;

    rawPairs.sort((a, b) {
      final ta = a['team']!;
      final tb = b['team']!;
      final pa = ta == clubTeamId ? 1 : 0;
      final pb = tb == clubTeamId ? 1 : 0;
      if (pb != pa) return pb.compareTo(pa);
      return (b['season']!).compareTo(a['season']!);
    });

    const maxRequests = 18;
    const conc = 3;
    var pjCar = 0, gCar = 0, rCar = 0;
    var pjClub = 0, gClub = 0, rClub = 0;
    var muestras = 0;
    var i = 0;
    while (muestras < maxRequests && i < rawPairs.length) {
      final n = conc < rawPairs.length - i ? conc : rawPairs.length - i;
      final statsFutures = <Future<Map<String, int>?>>[];
      for (var k = 0; k < n; k++) {
        final row = rawPairs[i + k];
        statsFutures.add(_fetchPlayerSeasonStatsTriple(playerId, row['team']!, row['season']!));
      }
      final outs = await Future.wait(statsFutures);
      for (var k = 0; k < n; k++) {
        if (muestras >= maxRequests) break;
        final s = outs[k];
        if (s == null) continue;
        muestras++;
        final tid = rawPairs[i + k]['team']!;
        pjCar += s['pj']!;
        gCar += s['g']!;
        rCar += s['r']!;
        if (tid == clubTeamId) {
          pjClub += s['pj']!;
          gClub += s['g']!;
          rClub += s['r']!;
        }
      }
      i += n;
    }

    final tail = await Future.wait([
      _fetchPlayerFullRow(playerId),
      getPlayerClubsHistoryDisplay(playerId),
    ]);
    final apiRow = tail[0] as Map<String, dynamic>?;
    final clubesHistorial = tail[1] as List<Map<String, dynamic>>;
    final extra = _extraerDorsalYSeleccion(apiRow, clubTeamId);

    var clubNombre = (extra['clubStatNombre'] as String?)?.trim() ?? '';
    var clubLogo = (extra['clubStatLogo'] as String?)?.trim() ?? '';
    if (clubNombre.isEmpty && clubTeamId > 0) {
      for (final row in clubesHistorial) {
        if ((row['teamId'] as int?) == clubTeamId) {
          clubNombre = (row['nombre'] as String?)?.trim() ?? '';
          clubLogo = (row['logo'] as String?)?.trim() ?? '';
          break;
        }
      }
    }

    return {
      'nombre': nombre,
      'foto': foto,
      'edad': age,
      'nacimiento': birth,
      'nacionalidad': nacionalidad,
      'paisNacimiento': birthCountry,
      'pjCarrera': pjCar,
      'golesCarrera': gCar,
      'rojasCarrera': rCar,
      'pjClub': pjClub,
      'golesClub': gClub,
      'rojasClub': rClub,
      'temporadasMuestra': muestras,
      'temporadasTotal': rawPairs.length,
      'dorsal': extra['dorsal'] as int,
      'tieneSeleccion': extra['tieneSeleccion'] as bool,
      'seleccionDetalle': extra['seleccionDetalle'] as String?,
      'seleccionPjTotal': extra['seleccionPjTotal'] as int,
      'seleccionGolesTotal': extra['seleccionGolesTotal'] as int,
      'clubActualNombre': clubNombre,
      'clubActualLogo': clubLogo,
      'clubesHistorial': clubesHistorial,
    };
  }
}