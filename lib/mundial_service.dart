import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'services/sportmonks_service.dart';

class MundialService {
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _leagueId = 1;
  static const int _season = 2026;

  /// API-Football suele incluir `errors: {}` en respuestas correctas; solo fallar si hay error real.
  static bool _apiErrorsPresent(dynamic decoded) {
    if (decoded is! Map) return false;
    final e = decoded['errors'];
    if (e == null) return false;
    if (e is Map) return e.isNotEmpty;
    if (e is List) return e.isNotEmpty;
    if (e is String) return e.trim().isNotEmpty;
    return false;
  }

  static Map<String, String> get _headers => {
        'x-apisports-key': _apiKey,
      };

  /// Convierte sub-maps del JSON (p. ej. `games`) a `Map<String, dynamic>`.
  static Map<String, dynamic> childMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  static Map<String, dynamic>? _mapFromStat(dynamic s) {
    if (s is Map<String, dynamic>) return s;
    if (s is Map) return Map<String, dynamic>.from(s);
    return null;
  }

  static int? _leagueIdFromStatMap(Map<String, dynamic> sm) {
    final league = sm['league'];
    if (league is! Map) return null;
    return (league['id'] as num?)?.toInt();
  }

  static int _statInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static int _partidosDesdeGamesMap(Map<String, dynamic> games) {
    final a = _statInt(games['appearences']);
    if (a != 0) return a;
    return _statInt(games['appearances']);
  }

  /// Elige el bloque `statistics` para PJ/goles/tarjetas: prioriza liga Mundial, nombre Copa, equipo selección, o más PJ.
  static Map<String, dynamic>? statisticsMundialLiga1(
    Map<String, dynamic> row, {
    int? priorizarSeleccionId,
  }) {
    final list = row['statistics'] as List?;
    if (list == null || list.isEmpty) return null;
    Map<String, dynamic>? porNombreCopa;
    Map<String, dynamic>? porSeleccion;
    Map<String, dynamic>? maxApBlock;
    var maxAp = -1;

    for (final s in list) {
      final sm = _mapFromStat(s);
      if (sm == null) continue;
      if (_leagueIdFromStatMap(sm) == _leagueId) return sm;
      final league = sm['league'];
      if (league is Map) {
        final name = (league['name'] as String? ?? '').toLowerCase();
        if (name.contains('world cup') || name.contains('copa mundial')) {
          porNombreCopa ??= sm;
        }
      }
      if (priorizarSeleccionId != null && priorizarSeleccionId > 0) {
        final tid = (childMap(sm['team'])['id'] as num?)?.toInt();
        if (tid == priorizarSeleccionId) {
          porSeleccion ??= sm;
        }
      }
      final ap = _partidosDesdeGamesMap(childMap(sm['games']));
      if (ap > maxAp) {
        maxAp = ap;
        maxApBlock = sm;
      }
    }
    return porNombreCopa ??
        porSeleccion ??
        (maxAp > 0 ? maxApBlock : null) ??
        _mapFromStat(list.first);
  }

  /// PJ, goles y expulsiones (roja + doble amarilla) en el torneo actual del endpoint plantel.
  static ({int pj, int goles, int expulsiones}) resumenMundialPlantel(Map<String, dynamic> row) {
    final st = statisticsMundialLiga1(row);
    final games = childMap(st?['games']);
    final goals = childMap(st?['goals']);
    final cards = childMap(st?['cards']);
    final pj = _statInt(games['appearences']) != 0 ? _statInt(games['appearences']) : _statInt(games['appearances']);
    final goles = (goals['total'] as num?)?.toInt() ?? int.tryParse('${goals['total']}') ?? 0;
    final rojas = _statInt(cards['red']);
    final yred = _statInt(cards['yellowred']);
    return (pj: pj, goles: goles, expulsiones: rojas + yred);
  }

  static Map<int, Map<String, dynamic>> indexPlantelPorJugadorId(List<Map<String, dynamic>> plantel) {
    final m = <int, Map<String, dynamic>>{};
    for (final row in plantel) {
      final pl = row['player'];
      final id = pl is Map ? (pl['id'] as num?)?.toInt() : null;
      if (id != null && id > 0) m[id] = row;
    }
    return m;
  }

  static List<Map<String, dynamic>> _fixtureMapsDeResponse(dynamic response) {
    if (response is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final it in response) {
      if (it is Map<String, dynamic>) {
        out.add(it);
      } else if (it is Map) {
        out.add(Map<String, dynamic>.from(it));
      }
    }
    return out;
  }

  // ── HOY ──────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPartidosHoy() async {
    final hoy = DateTime.now().toLocal();
    final fecha =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$_leagueId&season=$_season&date=$fecha&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      if (_apiErrorsPresent(data)) return [];
      return _fixtureMapsDeResponse(data['response']);
    } catch (_) {
      return [];
    }
  }

  // ── FIXTURE ───────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getFixture() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$_leagueId&season=$_season&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      if (_apiErrorsPresent(data)) return [];
      return _fixtureMapsDeResponse(data['response']);
    } catch (_) {
      return [];
    }
  }

  // ── GRUPOS ────────────────────────────────────────────────────────────────
  /// Cada elemento es un grupo: lista de filas de tabla (equipo, puntos, etc.).
  /// La API devuelve `league.standings` como **lista de listas**, no como lista de mapas.
  static Future<List<List<Map<String, dynamic>>>> getGrupos() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_leagueId&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      if (_apiErrorsPresent(data)) return [];
      final List standings = data['response'] ?? [];
      if (standings.isEmpty) return [];
      final leagueRaw = standings[0]['league']?['standings'];
      if (leagueRaw is! List) return [];
      final out = <List<Map<String, dynamic>>>[];
      for (final groupRaw in leagueRaw) {
        if (groupRaw is! List) continue;
        final g = <Map<String, dynamic>>[];
        for (final row in groupRaw) {
          if (row is Map<String, dynamic>) {
            g.add(row);
          } else if (row is Map) {
            g.add(Map<String, dynamic>.from(row));
          }
        }
        if (g.isNotEmpty) out.add(g);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Inicio aproximado de la fase de grupos del Mundial 2026 (UTC).
  static final DateTime mundial2026InicioUtc = DateTime.utc(2026, 6, 11, 14, 0);

  /// A partir de esta fecha asumimos planteles definitivos publicados (fin de mayo 2026).
  static final DateTime mundialPlantelDefinitivoDesde = DateTime(2026, 5, 31);

  static bool get plantelesMundialSonDefinitivos =>
      DateTime.now().isAfter(mundialPlantelDefinitivoDesde);

  static String mensajeEstadoPlantelMundial() {
    if (plantelesMundialSonDefinitivos) {
      return 'Plantel: se muestran dorsal, datos de jugador y club actual. Si la federación actualiza la lista, usá Actualizar plantel.';
    }
    return 'Lista provisional: las convocatorias definitivas se esperan a fin de mayo. Los dorsales y datos pueden cambiar — tocá Actualizar plantel cuando estén oficiales.';
  }

  static Future<void> refrescarCachePlantelMundial() async {
    SportmonksService.invalidateMundialPlantelCache();
    _favoritosTituloCache = null;
    _favoritosTituloCacheAt = null;
  }

  /// `true` solo si ya pasó la fecha de inicio del torneo **y** hay al menos un FT
  /// con fecha real en ventana jun–ago 2026 (evita datos fantasma / otras temporadas de la API).
  static Future<bool> debeMostrarTablaGoleadoresMundial() async {
    final ahora = DateTime.now().toUtc();
    if (ahora.isBefore(mundial2026InicioUtc)) return false;
    return tienePartidoMundialFtVerificado(ahora);
  }

  static bool esAntesDelInicioMundial2026Utc() =>
      DateTime.now().toUtc().isBefore(mundial2026InicioUtc);

  static Future<bool> tienePartidoMundialFtVerificado(DateTime ahoraUtc) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$_leagueId&season=$_season&status=FT&last=40'),
        headers: _headers,
      );
      if (response.statusCode != 200) return false;
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      for (final raw in items) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final fixture = m['fixture'];
        if (fixture is! Map) continue;
        final st = fixture['status'];
        if (st is! Map) continue;
        if ((st['short'] as String?) != 'FT') continue;
        final dateStr = fixture['date'] as String?;
        final dt = DateTime.tryParse(dateStr ?? '')?.toUtc();
        if (dt == null) continue;
        if (dt.isAfter(ahoraUtc)) continue;
        if (dt.year == 2026 && dt.month >= 6 && dt.month <= 8) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── GOLEADORES ────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getGoleadores() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/players/topscorers?league=$_leagueId&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      if (_apiErrorsPresent(data)) return [];
      return _fixtureMapsDeResponse(data['response']);
    } catch (_) {
      return [];
    }
  }

  /// Normaliza una fila del endpoint topscorers (estructuras variables de la API).
  static Map<String, dynamic>? parseEntradaGoleadorMundial(Map<String, dynamic> item) {
    final pl = childMap(item['player']);
    var st = statisticsMundialLiga1(item);
    if (st == null) {
      final rawSt = item['statistics'];
      if (rawSt is Map) {
        st = Map<String, dynamic>.from(rawSt);
      } else if (rawSt is List && rawSt.isNotEmpty) {
        for (final s in rawSt) {
          final sm = _mapFromStat(s);
          if (sm == null) continue;
          if (_leagueIdFromStatMap(sm) == _leagueId) {
            st = sm;
            break;
          }
          st ??= sm;
        }
      }
    }
    final goals = childMap(st?['goals']);
    final goles = _statInt(goals['total']);
    final asist = _statInt(goals['assists']);
    final nombre = (pl['name'] ?? item['name'] ?? '').toString().trim();
    if (nombre.isEmpty) return null;
    final team = childMap(st?['team']);
    return {
      'nombre': nombre,
      'goles': goles,
      'asistencias': asist,
      'foto': (pl['photo'] as String?) ?? '',
      'equipo': (team['name'] as String?) ?? '',
      'logoEquipo': (team['logo'] as String?) ?? '',
      'raw': item,
    };
  }

  /// Ranking de goleadores del torneo actual (misma lógica que pestaña Goleadores).
  static Future<List<Map<String, dynamic>>> getGoleadoresTorneoRanking({
    bool soloConGoles = true,
  }) async {
    final data = await getGoleadores();
    final out = <Map<String, dynamic>>[];
    for (final item in data) {
      final row = parseEntradaGoleadorMundial(item);
      if (row == null) continue;
      if (soloConGoles && (row['goles'] as int? ?? 0) <= 0) continue;
      final st = statisticsMundialLiga1(item);
      if (st != null) {
        final league = st['league'];
        if (league is Map) {
          final lid = (league['id'] as num?)?.toInt();
          if (lid != null && lid != _leagueId) continue;
        }
      }
      out.add(row);
    }
    out.sort((a, b) {
      final g = (b['goles'] as int).compareTo(a['goles'] as int);
      if (g != 0) return g;
      return (b['asistencias'] as int).compareTo(a['asistencias'] as int);
    });
    return out;
  }

  // ── PRONÓSTICOS (PREMIUM) ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getPronostico(int fixtureId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/predictions?fixture=$fixtureId'),
        headers: _headers,
      );
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      if (items.isEmpty) return null;
      return items[0] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Próximos partidos para pronósticos
  static Future<List<Map<String, dynamic>>> getProximosPartidos() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$_leagueId&season=$_season&status=NS&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      final partidos = items.cast<Map<String, dynamic>>();
      partidos.sort((a, b) {
        final fechaA =
            DateTime.tryParse(a['fixture']?['date'] ?? '') ?? DateTime.now();
        final fechaB =
            DateTime.tryParse(b['fixture']?['date'] ?? '') ?? DateTime.now();
        return fechaA.compareTo(fechaB);
      });
      return partidos.take(16).toList();
    } catch (_) {
      return [];
    }
  }

  // ── MEJORES JUGADORES (PREMIUM) ───────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMejoresJugadores(
      {int pagina = 1}) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/players?league=$_leagueId&season=$_season&page=$pagina'),
        headers: _headers,
      );
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      final jugadores = items.cast<Map<String, dynamic>>();
      // Filtrar jugadores con rating y ordenar
      final conRating = jugadores.where((j) {
        final stats = (j['statistics'] as List?)?.firstWhere(
            (s) => s['league']?['id'] == _leagueId,
            orElse: () => null);
        final rating = double.tryParse(
                stats?['games']?['rating']?.toString() ?? '') ??
            0.0;
        return rating > 0;
      }).toList();
      conRating.sort((a, b) {
        final statsA = (a['statistics'] as List?)?.firstWhere(
            (s) => s['league']?['id'] == _leagueId,
            orElse: () => null);
        final statsB = (b['statistics'] as List?)?.firstWhere(
            (s) => s['league']?['id'] == _leagueId,
            orElse: () => null);
        final ratingA =
            double.tryParse(statsA?['games']?['rating']?.toString() ?? '') ??
                0.0;
        final ratingB =
            double.tryParse(statsB?['games']?['rating']?.toString() ?? '') ??
                0.0;
        return ratingB.compareTo(ratingA);
      });
      return conRating;
    } catch (_) {
      return [];
    }
  }

  /// Misma lógica que [ApiService.getPreviewEquipo] pero para Mundial (liga 1, temporada 2026).
  static Future<Map<String, dynamic>> getPreviewEquipoMundial(int teamId) async {
    if (teamId <= 0) {
      return {'rating': <Map<String, dynamic>>[], 'goles': <Map<String, dynamic>>[], 'promedioEdad': 0.0};
    }
    try {
      final uri = Uri.parse(
          '$_baseUrl/players?league=$_leagueId&season=$_season&team=$teamId&page=1');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) {
        return {'rating': <Map<String, dynamic>>[], 'goles': <Map<String, dynamic>>[], 'promedioEdad': 0.0};
      }
      final players =
          (json.decode(res.body)['response'] as List? ?? []).cast<Map<String, dynamic>>();
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
      final promedioEdad =
          edades.isNotEmpty ? edades.reduce((a, b) => a + b) / edades.length : 0.0;
      final porRating = List<Map<String, dynamic>>.from(conStats)
        ..removeWhere((p) => (p['rating'] as double) == 0.0)
        ..sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      final porGoles = List<Map<String, dynamic>>.from(conStats)
        ..removeWhere((p) => (p['goles'] as int) == 0)
        ..sort((a, b) => (b['goles'] as int).compareTo(a['goles'] as int));
      return {
        'rating': porRating.take(3).toList(),
        'goles': porGoles.take(3).toList(),
        'promedioEdad': promedioEdad,
      };
    } catch (_) {
      return {'rating': <Map<String, dynamic>>[], 'goles': <Map<String, dynamic>>[], 'promedioEdad': 0.0};
    }
  }

  static bool _esTrofeoMundial(String? league) {
    final l = (league ?? '').toLowerCase();
    return l.contains('world cup') || l.contains('copa mundial');
  }

  /// Única fuente de verdad para títulos mundiales (evita errores API/SM tipo México campeón).
  static const Map<int, List<int>> _titulosMundialFifaPorApiId = {
    26: [2022, 1986, 1978],
    6: [2002, 1994, 1970, 1962, 1958],
    2: [2018, 1998],
    25: [2014, 1990, 1974, 1954],
    9: [2010],
    768: [2006, 1982, 1938, 1934],
    10: [1966],
    7: [1950, 1930],
  };

  static List<int> _titulosFifaParaEquipo(int apiTeamId, String teamName) {
    final direct = _titulosMundialFifaPorApiId[apiTeamId];
    if (direct != null) return direct;
    final alt = _apiIdPorPaisKey[_normPaisKey(teamName)];
    if (alt != null) return _titulosMundialFifaPorApiId[alt] ?? const [];
    return const [];
  }

  /// Palmarés FIFA de referencia (cuando API/SM vienen incompletos).
  static const Map<int, ({List<int> titulos, List<String> destacados, String? foto})>
      _palmaresReferenciaPorApiId = {
    26: (
      titulos: [2022, 1986, 1978],
      destacados: [
        'Campeón del Mundo: 1978, 1986, 2022',
        'Finalista: 1990, 2014',
        'Mejor participación histórica: campeón (3 títulos)',
      ],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b4/Argentina_2022_FIFA_World_Cup_champions.jpg/1280px-Argentina_2022_FIFA_World_Cup_champions.jpg',
    ),
    6: (
      titulos: [2002, 1994, 1970, 1962, 1958],
      destacados: [
        'Campeón del Mundo: 1958, 1962, 1970, 1994, 2002',
        'Finalista: 1950, 1998',
        'Récord: máximo ganador del Mundial (5 títulos)',
      ],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/9/99/Brazilian_national_team_2018.jpg/1280px-Brazilian_national_team_2018.jpg',
    ),
    2: (
      titulos: [2018, 1998],
      destacados: ['Campeón del Mundo: 1998, 2018', 'Finalista: 2006', 'Subcampeón: 2022'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2e/France_national_football_team_2018.jpg/1280px-France_national_football_team_2018.jpg',
    ),
    25: (
      titulos: [2014, 1990, 1974, 1954],
      destacados: ['Campeón del Mundo: 1954, 1974, 1990, 2014', 'Finalista: 1966, 1982, 1986, 2002'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/German_national_team_2010.jpg/1280px-German_national_team_2010.jpg',
    ),
    9: (
      titulos: [2010],
      destacados: ['Campeón del Mundo: 2010', 'Finalista: 2023'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/Spain_national_football_team_2010.jpg/1280px-Spain_national_football_team_2010.jpg',
    ),
    768: (
      titulos: [2006, 1982, 1938, 1934],
      destacados: ['Campeón del Mundo: 1934, 1938, 1982, 2006', 'Finalista: 1970, 1994'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0a/Italy_national_football_team_2012.jpg/1280px-Italy_national_football_team_2012.jpg',
    ),
    10: (
      titulos: [1966],
      destacados: ['Campeón del Mundo: 1966', 'Semifinalista: 1990, 2018'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/England_national_football_team_2018.jpg/1280px-England_national_football_team_2018.jpg',
    ),
    7: (
      titulos: [1950, 1930],
      destacados: ['Campeón del Mundo: 1930, 1950', '4.º puesto: 1954, 1970, 2010'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0e/Uruguay_national_football_team_2018.jpg/1280px-Uruguay_national_football_team_2018.jpg',
    ),
    16: (
      titulos: [],
      destacados: [
        'Cuartos de final: 1970 y 1986 (como sede)',
        'Octavos de final en varias ediciones',
        'Nunca campeón del Mundial',
      ],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/Mexico_national_football_team_2018.jpg/1280px-Mexico_national_football_team_2018.jpg',
    ),
    2673: (
      titulos: [],
      destacados: ['Subcampeón: 2018', 'Semifinalista: 1998'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Croatia_national_football_team_2018.jpg/1280px-Croatia_national_football_team_2018.jpg',
    ),
    27: (
      titulos: [],
      destacados: ['Semifinalista: 1966', '3.er puesto: 1966', 'Mejor puesto: semifinal'],
      foto:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5c/Portugal_national_football_team_2018.jpg/1280px-Portugal_national_football_team_2018.jpg',
    ),
    1119: (
      titulos: [],
      destacados: ['Subcampeón: 1974, 2010', '3.er puesto: 2014', 'Finalista: 2010'],
      foto: null,
    ),
    2384: (
      titulos: [],
      destacados: ['3.er puesto: 1930', 'Cuartos de final en varias ediciones', 'Nunca campeón del Mundial'],
      foto: null,
    ),
    1: (
      titulos: [],
      destacados: ['3.er puesto: 2018', 'Cuartos de final en varias ediciones'],
      foto: null,
    ),
    1132: (
      titulos: [],
      destacados: ['Cuartos de final: 2014', 'Nunca campeón del Mundial'],
      foto: null,
    ),
    12: (
      titulos: [],
      destacados: ['Cuartos de final en varias ediciones', 'Nunca campeón del Mundial'],
      foto: null,
    ),
    17: (
      titulos: [],
      destacados: ['4.º puesto: 2002', 'Semifinalista: 2002'],
      foto: null,
    ),
    31: (
      titulos: [],
      destacados: ['Semifinalista: 2022', 'Cuartos de final: 2022'],
      foto: null,
    ),
    1567: (
      titulos: [],
      destacados: ['Nunca superó fase de grupos en debut 2022'],
      foto: null,
    ),
  };

  /// Banner de selección: foto de referencia, Sportmonks o escudo HD API-Football.
  static String? bannerSeleccionUrl(
    int apiTeamId, {
    String? logo,
    String? refFoto,
    String? sportmonksFoto,
  }) {
    for (final raw in [refFoto, sportmonksFoto, logo]) {
      final u = raw?.trim();
      if (u != null && u.isNotEmpty && !_pareceUrlVenue(u)) return u;
    }
    if (apiTeamId > 0) {
      return 'https://media.api-sports.io/football/teams/$apiTeamId.png';
    }
    return null;
  }

  static bool _pareceUrlVenue(String url) {
    final u = url.toLowerCase();
    return u.contains('/venues/') || u.contains('venue') && u.contains('stadium');
  }

  static bool esEscudoApiSports(String url) {
    final u = url.toLowerCase();
    return u.contains('media.api-sports.io/football/teams/');
  }

  /// Foto para tarjetas de partido / encabezado (referencia FIFA + escudo API).
  static String? fotoSeleccionParaTarjeta(
    int teamId, {
    String? logo,
    String? teamName,
  }) {
    final ref = _palmaresReferenciaPorApiId[teamId] ??
        (teamName != null && teamName.trim().isNotEmpty
            ? _palmaresRef(teamId, teamName.trim())
            : null);
    return bannerSeleccionUrl(teamId, logo: logo, refFoto: ref?.foto);
  }

  /// Foto de estadio Mundial: API venues + Wikimedia por nombre.
  static Future<String?> venueFotoMundial(int? venueId, {String? venueName, String? city}) async {
    if (venueId != null && venueId > 0) {
      final api = await ApiService.getVenueFoto(venueId);
      if (api != null && api.trim().isNotEmpty) return api.trim();
    }
    return _venueFotoMundialPorNombre(venueName, city);
  }

  static String? _venueFotoMundialPorNombre(String? name, String? city) {
    final n = '${name ?? ''} ${city ?? ''}'.toLowerCase();
    if (n.trim().isEmpty) return null;
    const fallbacks = <String, String>{
      'azteca':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Estadio_Azteca_2015.jpg/1280px-Estadio_Azteca_2015.jpg',
      'akron':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4f/Estadio_Akron_Guadalajara.jpg/1280px-Estadio_Akron_Guadalajara.jpg',
      'bbva':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Estadio_BBVA.jpg/1280px-Estadio_BBVA.jpg',
      'metlife':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/MetLife_Stadium_Exterior.jpg/1280px-MetLife_Stadium_Exterior.jpg',
      'att stadium':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5c/AT%26T_Stadium_2013.jpg/1280px-AT%26T_Stadium_2013.jpg',
      'mercedes':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2e/Mercedes-Benz_Stadium_2017.jpg/1280px-Mercedes-Benz_Stadium_2017.jpg',
      'hard rock':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2d/Hard_Rock_Stadium_2012.jpg/1280px-Hard_Rock_Stadium_2012.jpg',
      'lumen':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Lumen_Field_2011.jpg/1280px-Lumen_Field_2011.jpg',
      'levis':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0c/Levi%27s_Stadium_exterior.jpg/1280px-Levi%27s_Stadium_exterior.jpg',
      'sofi':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4b/SoFi_Stadium_2021.jpg/1280px-SoFi_Stadium_2021.jpg',
      'arrowhead':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7a/Arrowhead_Stadium_2012.jpg/1280px-Arrowhead_Stadium_2012.jpg',
      'bmo':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/BMO_Field_2016.jpg/1280px-BMO_Field_2016.jpg',
      'bc place':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/BC_Place_2011.jpg/1280px-BC_Place_2011.jpg',
    };
    for (final entry in fallbacks.entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String _normPaisKey(String s) {
    var t = s.toLowerCase().trim();
    if (t.contains('argentin')) return 'argentina';
    if (t.contains('brasil') || t == 'brazil') return 'brazil';
    if (t.contains('franc')) return 'france';
    if (t.contains('aleman') || t.contains('german')) return 'germany';
    if (t.contains('espa')) return 'spain';
    if (t.contains('ital')) return 'italy';
    if (t.contains('inglat') || t.contains('england')) return 'england';
    if (t.contains('uruguay')) return 'uruguay';
    if (t.contains('mexic')) return 'mexico';
    if (t.contains('croacia') || t.contains('croat')) return 'croatia';
    if (t.contains('portug')) return 'portugal';
    if (t.contains('holand') || t.contains('nether')) return 'netherlands';
    if (t.contains('usa') || t.contains('united states')) return 'usa';
    if (t.contains('colomb')) return 'colombia';
    if (t.contains('japan')) return 'japan';
    if (t.contains('korea')) return 'south korea';
    if (t.contains('marruec') || t.contains('morocc')) return 'morocco';
    if (t.contains('belg')) return 'belgium';
    return t;
  }

  /// Réords históricos en Copas del Mundo (FIFA / fuentes oficiales). Evita errores de API (ej. Neymar ≠ más presencias de Brasil).
  static const Map<int, ({String goleador, int goles, String presencias, int apps})>
      _historicoMundialFifaPorApiId = {
    6: (goleador: 'Ronaldo', goles: 15, presencias: 'Cafu', apps: 20),
    26: (goleador: 'Lionel Messi', goles: 13, presencias: 'Lionel Messi', apps: 26),
    25: (goleador: 'Miroslav Klose', goles: 16, presencias: 'Lothar Matthäus', apps: 25),
    2: (goleador: 'Kylian Mbappé', goles: 12, presencias: 'Hugo Lloris', apps: 20),
    9: (goleador: 'David Villa', goles: 9, presencias: 'Iker Casillas', apps: 17),
    768: (goleador: 'Paolo Rossi', goles: 9, presencias: 'Gianluigi Buffon', apps: 19),
    10: (goleador: 'Gary Lineker', goles: 10, presencias: 'Peter Shilton', apps: 17),
    7: (goleador: 'Óscar Míguez', goles: 8, presencias: 'Diego Godín', apps: 16),
    27: (goleador: 'Cristiano Ronaldo', goles: 8, presencias: 'Cristiano Ronaldo', apps: 22),
    1119: (goleador: 'Robin van Persie', goles: 6, presencias: 'Edwin van der Sar', apps: 21),
    16: (goleador: 'Javier Hernández', goles: 4, presencias: 'Rafael Márquez', apps: 16),
    2673: (goleador: 'Davor Šuker', goles: 6, presencias: 'Luka Modrić', apps: 19),
    2384: (goleador: 'Clint Dempsey', goles: 5, presencias: 'Cobi Jones', apps: 11),
    1132: (goleador: 'James Rodríguez', goles: 6, presencias: 'Faryd Mondragón', apps: 16),
    12: (goleador: 'Kunishige Kamamoto', goles: 4, presencias: 'Eiji Kawashima', apps: 12),
    17: (goleador: 'Park Ji-sung', goles: 2, presencias: 'Hong Myung-bo', apps: 16),
    31: (goleador: 'Salaheddine Chtaibi', goles: 2, presencias: 'Noureddine Naybet', apps: 13),
    1: (goleador: 'Romelu Lukaku', goles: 5, presencias: 'Jan Vertonghen', apps: 16),
    1567: (goleador: 'Almoez Ali', goles: 1, presencias: 'Hassan Al-Haydos', apps: 7),
  };

  static ({String goleador, int goles, String presencias, int apps})? _historicoMundialRef(
    int apiTeamId,
    String teamName,
  ) {
    final direct = _historicoMundialFifaPorApiId[apiTeamId];
    if (direct != null) return direct;
    final alt = _apiIdPorPaisKey[_normPaisKey(teamName)];
    if (alt != null) return _historicoMundialFifaPorApiId[alt];
    return null;
  }

  static const Map<String, int> _apiIdPorPaisKey = {
    'argentina': 26,
    'brazil': 6,
    'france': 2,
    'germany': 25,
    'spain': 9,
    'italy': 768,
    'england': 10,
    'uruguay': 7,
    'croatia': 2673,
    'mexico': 16,
    'portugal': 27,
    'netherlands': 1119,
    'holland': 1119,
    'usa': 2384,
    'united states': 2384,
    'colombia': 1132,
    'japan': 12,
    'south korea': 17,
    'korea republic': 17,
    'morocco': 31,
    'belgium': 1,
    'qatar': 1567,
  };

  static ({List<int> titulos, List<String> destacados, String? foto})? _palmaresRef(
    int apiTeamId,
    String teamName,
  ) {
    final direct = _palmaresReferenciaPorApiId[apiTeamId];
    if (direct != null) return direct;
    final alt = _apiIdPorPaisKey[_normPaisKey(teamName)];
    if (alt != null) return _palmaresReferenciaPorApiId[alt];
    return null;
  }

  static int _rankPuesto(String place) {
    final p = place.toLowerCase();
    if (p.contains('winner') || p == '1' || p.contains('1st') || p.contains('first')) return 100;
    if (p.contains('2nd') || p.contains('second') || p.contains('runner')) return 80;
    if (p.contains('3rd') || p.contains('third')) return 60;
    if (p.contains('semi')) return 50;
    return 5;
  }

  /// Ficha unificada: Sportmonks + API-Football + referencia FIFA.
  static Future<Map<String, dynamic>> getSeleccionPaisProfile(
    int teamId, {
    required String teamName,
  }) async {
    final hint = teamName.trim();
    final ref = _palmaresReferenciaPorApiId[teamId] ?? _palmaresRef(teamId, hint);
    final titulosFifa = _titulosFifaParaEquipo(teamId, hint);

    Map<String, dynamic>? info;
    String? seleccionFotoSm;
    final titulosSet = <int>{...titulosFifa};
    final destacadas = <String>[];
    var mejorPuesto = titulosFifa.isNotEmpty ? 'Campeón del Mundo' : '-';
    var mejorRank = titulosFifa.isNotEmpty ? 100 : 0;

    if (ref != null) {
      for (final d in ref.destacados) {
        if (!destacadas.contains(d)) destacadas.add(d);
      }
    }

    void absorbTrofeos(List<Map<String, dynamic>> trofeos) {
      for (final t in trofeos) {
        final league = t['league'] as String? ?? '';
        if (league.isNotEmpty && !_esTrofeoMundial(league)) continue;
        final place = t['place']?.toString() ?? '';
        final r = _rankPuesto(place);
        if (r >= 100) continue;
        if (r > mejorRank) {
          mejorRank = r;
          mejorPuesto = _traducirPuestoTrofeo(place);
        }
        final y = int.tryParse(t['season']?.toString() ?? '') ?? 0;
        if (y > 0 && r >= 50) {
          final linea = '${_traducirPuestoTrofeo(place)} · $y';
          if (!destacadas.contains(linea)) destacadas.add(linea);
        }
      }
    }

    if (SportmonksService.hasConfiguredToken && hint.isNotEmpty) {
      final sm = await SportmonksService().fetchMundialSeleccionProfile(teamId, hint);
      if (sm != null) {
        final smInfo = sm['info'];
        if (smInfo is Map) info = Map<String, dynamic>.from(smInfo);
        seleccionFotoSm = sm['seleccionFotoUrl'] as String?;
        for (final d in sm['participacionesDestacadas'] as List? ?? []) {
          final s = d.toString().trim();
          if (s.isNotEmpty && !destacadas.contains(s)) destacadas.add(s);
        }
        final mp = sm['mejorPuestoTexto'] as String?;
        if (titulosFifa.isEmpty &&
            mp != null &&
            mp.trim().isNotEmpty &&
            mp != '-' &&
            !mp.toLowerCase().contains('campeón') &&
            !mp.toLowerCase().contains('campeon')) {
          mejorPuesto = mp;
        }
        absorbTrofeos(List<Map<String, dynamic>>.from(sm['trofeosSm'] as List? ?? []));
      }
    }

    final apiTrofeos = await getTrophiesTeam(teamId, teamName: hint);
    absorbTrofeos(apiTrofeos);

    info ??= await getTeamInfo(teamId, teamName: hint);
    info ??= {
      'id': teamId,
      'name': hint,
      'logo': '',
      'country': hint,
      'national': true,
    };

    final logo = (info['logo'] as String?)?.trim() ?? '';
    final seleccionFoto = bannerSeleccionUrl(
      teamId,
      logo: logo.isNotEmpty ? logo : null,
      refFoto: ref?.foto,
      sportmonksFoto: seleccionFotoSm,
    );

    final titulos = titulosSet.toList()..sort((a, b) => b.compareTo(a));
    final titulosStr = titulos.map((y) => '$y').toList();

    final historico = await getResumenHistoricoMundial(teamId, teamName: hint);
    if (mejorPuesto == '-' || mejorPuesto.isEmpty) {
      final ht = historico['mejorPuestoTexto'] as String?;
      if (ht != null && ht.trim().isNotEmpty && ht != '-') {
        final htLow = ht.toLowerCase();
        final esCampeonFalso = titulosFifa.isEmpty &&
            (htLow.contains('campeón') || htLow.contains('campeon') || htLow.contains('winner'));
        if (!esCampeonFalso) mejorPuesto = ht;
      }
    }
    if (titulosFifa.isEmpty) {
      final mpLow = mejorPuesto.toLowerCase();
      if (mpLow.contains('campeón') || mpLow.contains('campeon') || mpLow.contains('winner')) {
        mejorPuesto = ref != null && ref.destacados.isNotEmpty
            ? ref.destacados.first
            : 'Sin título mundial';
      }
    }

    return {
      'info': info,
      'seleccionFotoUrl': seleccionFoto,
      'titulosMundial': titulosStr,
      'participacionesDestacadas': destacadas.take(10).toList(),
      'mejorPuestoTexto': mejorPuesto,
      'historico': historico,
    };
  }

  static String _normPlayerNameKey(String s) {
    var t = s.toLowerCase().trim();
    const from = 'áàäâãåéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaaeeeeiiiioooooouuuunc';
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Cruza nombres del plantel Sportmonks con ids API-Football (club actual / carrera).
  static Future<List<Map<String, dynamic>>> _enriquecerPlantelConIdsApi(
    List<Map<String, dynamic>> plantelSm,
    int nationalTeamId,
  ) async {
    if (plantelSm.isEmpty || nationalTeamId <= 0) return plantelSm;

    final apiRows = await _getPlantelMundialSoloApiFootball(nationalTeamId);
    final byKey = <String, int>{};
    for (final row in apiRows) {
      final pl = row['player'];
      if (pl is! Map) continue;
      final id = (pl['id'] as num?)?.toInt() ?? 0;
      final name = (pl['name'] as String?)?.trim() ?? '';
      if (id <= 0 || name.isEmpty) continue;
      byKey[_normPlayerNameKey(name)] = id;
      final parts = name.split(' ').where((p) => p.length > 1).toList();
      if (parts.length >= 2) {
        byKey[_normPlayerNameKey(parts.last)] = id;
      }
    }

    final apiById = <int, Map<String, dynamic>>{};
    for (final row in apiRows) {
      final id = _playerIdPlantel(row);
      if (id != null && id > 0) apiById[id] = row;
    }

    final out = <Map<String, dynamic>>[];
    for (final row in plantelSm) {
      final copy = Map<String, dynamic>.from(row);
      final plRaw = copy['player'];
      if (plRaw is! Map) {
        out.add(copy);
        continue;
      }
      final pl = Map<String, dynamic>.from(plRaw);
      final name = (pl['name'] as String?)?.trim() ?? '';
      var apiId = byKey[_normPlayerNameKey(name)];
      if (apiId == null && name.isNotEmpty) {
        final parts = name.split(' ').where((p) => p.length > 1).toList();
        if (parts.isNotEmpty) {
          apiId = byKey[_normPlayerNameKey(parts.last)];
        }
      }
      if (apiId == null && name.isNotEmpty) {
        apiId = await ApiService.findApiFootballPlayerId(
          name,
          preferTeamId: nationalTeamId,
        );
      }
      if (apiId != null && apiId > 0) {
        pl['id'] = apiId;
        final apiRow = apiById[apiId];
        if (apiRow != null) {
          _fusionarDatosJugadorPlantel(copy, pl, apiRow, nationalTeamId);
        }
      }
      copy['player'] = pl;
      out.add(copy);
    }
    return out;
  }

  static void _fusionarDatosJugadorPlantel(
    Map<String, dynamic> copy,
    Map<String, dynamic> pl,
    Map<String, dynamic> apiRow,
    int nationalTeamId,
  ) {
    final apiPl = childMap(apiRow['player']);
    void tomar(String key) {
      final v = apiPl[key];
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      if (pl[key] == null || (pl[key] is String && (pl[key] as String).isEmpty)) {
        pl[key] = v;
      }
    }

    tomar('photo');
    tomar('age');
    tomar('height');
    tomar('weight');
    tomar('nationality');
    if ((pl['number'] as num?)?.toInt() == 0) {
      final n = apiPl['number'];
      if (n != null) pl['number'] = n;
    }

    final stSm = statisticsMundialLiga1(copy, priorizarSeleccionId: nationalTeamId);
    final stApi = statisticsMundialLiga1(apiRow, priorizarSeleccionId: nationalTeamId);
    if (stSm != null && stApi != null) {
      final gSm = childMap(stSm['games']);
      final gApi = childMap(stApi['games']);
      final pjSm = _partidosDesdeGamesMap(gSm);
      final pjApi = _partidosDesdeGamesMap(gApi);
      if (pjSm == 0 && pjApi > 0) {
        copy['statistics'] = apiRow['statistics'];
      } else {
        final goalsSm = childMap(stSm['goals']);
        final goalsApi = childMap(stApi['goals']);
        if (_statInt(goalsSm['assists']) == 0 && _statInt(goalsApi['assists']) > 0) {
          goalsSm['assists'] = goalsApi['assists'];
        }
        if (_statInt(goalsSm['total']) == 0 && _statInt(goalsApi['total']) > 0) {
          goalsSm['total'] = goalsApi['total'];
        }
        final dorsalApi = gApi['number'];
        if (_statInt(gSm['number']) == 0 && dorsalApi != null) {
          gSm['number'] = dorsalApi;
        }
        if ((gSm['position'] as String? ?? '').isEmpty && (gApi['position'] as String? ?? '').isNotEmpty) {
          gSm['position'] = gApi['position'];
        }
        if (gApi['rating'] != null && gSm['rating'] == null) {
          gSm['rating'] = gApi['rating'];
        }
      }
    }
  }

  /// `teams?id=` — logo de federación / selección, nombre, país.
  static Future<Map<String, dynamic>?> getTeamInfo(
    int teamId, {
    String? teamName,
  }) async {
    if (teamId <= 0) return null;
    final hint = teamName?.trim() ?? '';
    if (SportmonksService.hasConfiguredToken && hint.isNotEmpty) {
      final sm = await SportmonksService().fetchMundialTeamInfoApiFormat(teamId, hint);
      if (sm != null) return sm;
    }
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/teams?id=$teamId'),
        headers: _headers,
      );
      if (res.statusCode != 200) return null;
      final list = json.decode(res.body)['response'] as List? ?? [];
      if (list.isEmpty) return null;
      final row = list[0] as Map<String, dynamic>;
      final team = row['team'] as Map<String, dynamic>? ?? row;
      return {
        'id': team['id'],
        'name': team['name'] ?? '',
        'logo': team['logo'] ?? '',
        'country': team['country'] ?? '',
        'national': team['national'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getTrophiesTeam(
    int teamId, {
    String? teamName,
  }) async {
    if (teamId <= 0) return [];
    final hint = teamName?.trim() ?? '';
    if (SportmonksService.hasConfiguredToken && hint.isNotEmpty) {
      final sm = await SportmonksService().fetchMundialSeleccionProfile(teamId, hint);
      final raw = sm?['trofeosSm'];
      if (raw is List && raw.isNotEmpty) {
        return raw.cast<Map<String, dynamic>>();
      }
    }
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/trophies?team=$teamId'),
        headers: _headers,
      );
      if (res.statusCode != 200) return [];
      final list = json.decode(res.body)['response'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static int? _playerIdPlantel(Map<String, dynamic> r) {
    final pl = r['player'];
    if (pl is Map) return (pl['id'] as num?)?.toInt();
    return null;
  }

  static Future<List<Map<String, dynamic>>> _playersPaginated({
    required int teamId,
    int? leagueId,
    required int season,
  }) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final q = leagueId != null
          ? 'league=$leagueId&season=$season&team=$teamId&page=$page'
          : 'team=$teamId&season=$season&page=$page';
      final res = await http.get(Uri.parse('$_baseUrl/players?$q'), headers: _headers);
      if (res.statusCode != 200) break;
      final data = json.decode(res.body);
      if (_apiErrorsPresent(data)) break;
      final raw = data['response'] as List? ?? [];
      for (final p in raw) {
        if (p is Map<String, dynamic>) {
          out.add(p);
        } else if (p is Map) {
          out.add(Map<String, dynamic>.from(p));
        }
      }
      final pg = data['paging'];
      final totalPages = pg is Map ? (pg['total'] as num?)?.toInt() ?? 1 : 1;
      if (page >= totalPages) break;
      page++;
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _squadsSoloFaltantes(
    int teamId,
    Set<int> ya,
  ) async {
    final extra = <Map<String, dynamic>>[];
    try {
      final res = await http.get(Uri.parse('$_baseUrl/players/squads?team=$teamId'), headers: _headers);
      if (res.statusCode != 200) return extra;
      final data = json.decode(res.body);
      if (_apiErrorsPresent(data)) return extra;
      final resp = data['response'];
      if (resp is! List || resp.isEmpty) return extra;
      final block0 = resp[0];
      if (block0 is! Map) return extra;
      final players = block0['players'] as List?;
      if (players == null) return extra;
      for (final pl in players) {
        if (pl is! Map) continue;
        final m = Map<String, dynamic>.from(pl);
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id <= 0 || ya.contains(id)) continue;
        final numRaw = m['number'];
        final dorsal = numRaw is num ? numRaw.toInt() : int.tryParse('$numRaw');
        extra.add({
          'player': {
            'id': id,
            'name': m['name'],
            'photo': m['photo'],
            'age': m['age'],
            'nationality': m['nationality'],
            'number': dorsal,
          },
          'statistics': <dynamic>[],
        });
      }
    } catch (_) {}
    return extra;
  }

  /// Plantel: Sportmonks (Mundial) → API-Football; enriquece ids API para club/carrera.
  static Future<List<Map<String, dynamic>>> getPlantelMundialCompleto(
    int teamId, {
    String? teamName,
    bool forzarActualizacion = false,
  }) async {
    if (teamId <= 0) return [];
    if (forzarActualizacion) await refrescarCachePlantelMundial();
    final hint = teamName?.trim() ?? '';
    if (SportmonksService.hasConfiguredToken && hint.isNotEmpty) {
      final sm = await SportmonksService().fetchMundialPlantelApiFormat(teamId, hint);
      if (sm != null && sm.isNotEmpty) {
        return _enriquecerPlantelConIdsApi(sm, teamId);
      }
    }
    return _getPlantelMundialSoloApiFootball(teamId);
  }

  static String etiquetaPosicionPlantel(String? pos) {
    final p = (pos ?? '').toUpperCase();
    if (p == 'G') return 'Arquero';
    if (p == 'D') return 'Defensor';
    if (p == 'M') return 'Mediocampo';
    if (p == 'F') return 'Delantero';
    return pos ?? '';
  }

  /// Solo API-Football (respaldo y cruce de ids).
  static Future<List<Map<String, dynamic>>> _getPlantelMundialSoloApiFootball(int teamId) async {
    if (teamId <= 0) return [];
    final porId = <int, Map<String, dynamic>>{};
    void poner(List<Map<String, dynamic>> list) {
      for (final r in list) {
        final id = _playerIdPlantel(r);
        if (id != null && id > 0) porId[id] = r;
      }
    }

    poner(await _playersPaginated(teamId: teamId, leagueId: _leagueId, season: _season));
    if (porId.isEmpty) {
      poner(await _playersPaginated(teamId: teamId, leagueId: _leagueId, season: 2025));
    }
    if (porId.isEmpty) {
      poner(await _playersPaginated(teamId: teamId, leagueId: null, season: _season));
    }
    if (porId.isEmpty) {
      poner(await _playersPaginated(teamId: teamId, leagueId: null, season: 2025));
    }

    for (final e in await _squadsSoloFaltantes(teamId, porId.keys.toSet())) {
      final id = _playerIdPlantel(e);
      if (id != null && id > 0) {
        porId.putIfAbsent(id, () => e);
      }
    }

    return porId.values.toList();
  }

  static Future<List<Map<String, dynamic>>> _fixturesMundialTemporada(
      int teamId, int season) async {
    if (teamId <= 0) return [];
    try {
      final res = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?team=$teamId&league=$_leagueId&season=$season'),
        headers: _headers,
      );
      if (res.statusCode != 200) return [];
      final list = json.decode(res.body)['response'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _topscorersMundialTemporada(
      int season) async {
    try {
      final res = await http.get(
        Uri.parse(
            '$_baseUrl/players/topscorers?league=$_leagueId&season=$season'),
        headers: _headers,
      );
      if (res.statusCode != 200) return [];
      final list = json.decode(res.body)['response'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Resumen histórico en Copas del Mundo (varias temporadas API).
  static Future<Map<String, dynamic>> getResumenHistoricoMundial(
    int teamId, {
    String? teamName,
  }) async {
    final out = <String, dynamic>{
      'partidosJugados': 0,
      'finalesJugadas': 0,
      'mejorPuestoTexto': '-',
      'goleadorHistoricoNombre': '',
      'goleadorHistoricoGoles': 0,
      'goleadorHistoricoFoto': '',
      'masPresenciasNombre': '',
      'masPresenciasPartidos': 0,
      'masPresenciasFoto': '',
    };
    if (teamId <= 0) return out;

    const seasons = [2026, 2022, 2018, 2014, 2010];
    var pj = 0;
    var finales = 0;
    final ref = _historicoMundialRef(teamId, teamName ?? '');
    if (ref != null) {
      out['goleadorHistoricoNombre'] = ref.goleador;
      out['goleadorHistoricoGoles'] = ref.goles;
      out['masPresenciasNombre'] = ref.presencias;
      out['masPresenciasPartidos'] = ref.apps;
      out['historicoFuente'] = 'fifa';
    } else {
      out['historicoFuente'] = 'none';
    }

    int rankPuesto(String place) {
      final p = place.toLowerCase();
      if (p.contains('winner') || p == '1') return 100;
      if (p.contains('2nd') || p.contains('second') || p.contains('runner')) return 80;
      if (p.contains('3rd') || p.contains('third')) return 60;
      if (p.contains('semi')) return 50;
      if (p.contains('quarter') || p.contains('1/4')) return 40;
      if (p.contains('16') || p.contains('1/8')) return 30;
      if (p.contains('group')) return 10;
      return 5;
    }

    var mejorRank = 0;
    var mejorTxt = '-';

    try {
      final trofeos = await getTrophiesTeam(teamId);
      for (final t in trofeos) {
        final league = t['league'] as String? ?? '';
        if (!_esTrofeoMundial(league)) continue;
        final place = t['place']?.toString() ?? '';
        final r = rankPuesto(place);
        if (r > mejorRank) {
          mejorRank = r;
          mejorTxt = _traducirPuestoTrofeo(place);
        }
      }

      for (final season in seasons) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final fixes = await _fixturesMundialTemporada(teamId, season);
        for (final f in fixes) {
          final st = f['fixture']?['status']?['short'] as String? ?? '';
          if (!const {'FT', 'AET', 'PEN'}.contains(st)) continue;
          pj++;
          final round = (f['league']?['round'] as String? ?? '').toLowerCase();
          // Evitar "quarter-finals", "semi-finals", etc. (contienen la palabra "final").
          final esFinal = round.contains('final') &&
              !round.contains('quarter') &&
              !round.contains('semi') &&
              !round.contains('1/8') &&
              !round.contains('16') &&
              !round.contains('group') &&
              !round.contains('3rd') &&
              !round.contains('third place');
          if (esFinal) finales++;
        }

      }

      out['partidosJugados'] = pj;
      out['finalesJugadas'] = finales;
      var mejorFinal = mejorTxt;
      if (_titulosFifaParaEquipo(teamId, teamName ?? '').isEmpty) {
        final low = mejorFinal.toLowerCase();
        if (low.contains('campeón') || low.contains('campeon') || low.contains('winner')) {
          mejorFinal = '-';
          var rankSinCampeon = 0;
          for (final t in await getTrophiesTeam(teamId, teamName: teamName)) {
            final league = t['league'] as String? ?? '';
            if (!_esTrofeoMundial(league)) continue;
            final place = t['place']?.toString() ?? '';
            final r = rankPuesto(place);
            if (r >= 100) continue;
            if (r > rankSinCampeon) {
              rankSinCampeon = r;
              mejorFinal = _traducirPuestoTrofeo(place);
            }
          }
        }
      }
      out['mejorPuestoTexto'] = mejorFinal;
    } catch (_) {}

    return out;
  }

  static String _traducirPuestoTrofeo(String place) {
    final p = place.toLowerCase();
    if (p.contains('winner') || p == '1') return 'Campeón';
    if (p.contains('2nd') || p.contains('second') || p.contains('runner')) return 'Subcampeón';
    if (p.contains('3rd') || p.contains('third')) return '3.er lugar';
    if (p.contains('semi')) return 'Semifinal';
    if (p.contains('quarter') || p.contains('1/4')) return 'Cuartos de final';
    if (p.contains('16') || p.contains('1/8')) return 'Octavos de final';
    if (p.contains('group')) return 'Fase de grupos';
    return place;
  }

  /// Títulos de Copa del Mundo (con años).
  static List<String> titulosMundialDesdeTrofeos(List<Map<String, dynamic>> trofeos) {
    final titulos = <String>[];
    for (final t in trofeos) {
      if (!_esTrofeoMundial(t['league'] as String?)) continue;
      final place = (t['place']?.toString() ?? '').toLowerCase();
      final esCampeon = place.contains('winner') ||
          place == '1' ||
          place.contains('1st') ||
          place.contains('first');
      if (!esCampeon) continue;
      final season = t['season']?.toString() ?? '';
      if (season.isNotEmpty) titulos.add(season);
    }
    titulos.sort((a, b) => b.compareTo(a));
    return titulos;
  }

  static int contarTitulosMundial(List<Map<String, dynamic>> trofeos) =>
      titulosMundialDesdeTrofeos(trofeos).length;

  // ── PREMIUM: sedes, récords torneo, capas plantel ─────────────────────────

  /// Sedes principales Mundial 2026 (referencia; partidos reales vienen del fixture API).
  static const List<Map<String, dynamic>> sedesMundial2026 = [
    {'nombre': 'MetLife Stadium', 'ciudad': 'East Rutherford, NJ', 'pais': '🇺🇸 USA', 'cap': 82500, 'nota': 'Final'},
    {'nombre': 'SoFi Stadium', 'ciudad': 'Inglewood, CA', 'pais': '🇺🇸 USA', 'cap': 70240, 'nota': ''},
    {'nombre': 'AT&T Stadium', 'ciudad': 'Arlington, TX', 'pais': '🇺🇸 USA', 'cap': 80000, 'nota': ''},
    {'nombre': 'Mercedes-Benz Stadium', 'ciudad': 'Atlanta, GA', 'pais': '🇺🇸 USA', 'cap': 71000, 'nota': ''},
    {'nombre': 'Hard Rock Stadium', 'ciudad': 'Miami, FL', 'pais': '🇺🇸 USA', 'cap': 65326, 'nota': ''},
    {'nombre': 'Lincoln Financial Field', 'ciudad': 'Philadelphia, PA', 'pais': '🇺🇸 USA', 'cap': 69596, 'nota': ''},
    {'nombre': 'Levi\'s Stadium', 'ciudad': 'Santa Clara, CA', 'pais': '🇺🇸 USA', 'cap': 68500, 'nota': ''},
    {'nombre': 'Lumen Field', 'ciudad': 'Seattle, WA', 'pais': '🇺🇸 USA', 'cap': 69000, 'nota': ''},
    {'nombre': 'Arrowhead Stadium', 'ciudad': 'Kansas City, MO', 'pais': '🇺🇸 USA', 'cap': 76416, 'nota': ''},
    {'nombre': 'Estadio Azteca', 'ciudad': 'Ciudad de México', 'pais': '🇲🇽 México', 'cap': 87523, 'nota': 'Altitud ~2.200 m'},
    {'nombre': 'Estadio BBVA', 'ciudad': 'Monterrey', 'pais': '🇲🇽 México', 'cap': 53500, 'nota': ''},
    {'nombre': 'Estadio Akron', 'ciudad': 'Guadalajara', 'pais': '🇲🇽 México', 'cap': 49850, 'nota': ''},
    {'nombre': 'BMO Field', 'ciudad': 'Toronto', 'pais': '🇨🇦 Canadá', 'cap': 30000, 'nota': ''},
    {'nombre': 'BC Place', 'ciudad': 'Vancouver', 'pais': '🇨🇦 Canadá', 'cap': 54500, 'nota': ''},
  ];

  /// Récords del torneo en curso (API liga 1 · 2026).
  static Future<Map<String, dynamic>> getRecordesTorneoEnCurso() async {
    final out = <String, dynamic>{
      'partidosJugados': 0,
      'totalGoles': 0,
      'goleadorNombre': '',
      'goleadorGoles': 0,
      'goleadorFoto': '',
      'partidoMasGoles': '',
      'partidoMasGolesTotal': 0,
      'topGoleadores': <Map<String, dynamic>>[],
    };
    try {
      final fixes = await getFixture();
      var totalGoles = 0;
      var pj = 0;
      var maxGoles = 0;
      var maxPartido = '';
      for (final f in fixes) {
        final st = f['fixture']?['status']?['short'] as String? ?? '';
        if (!const {'FT', 'AET', 'PEN'}.contains(st)) continue;
        pj++;
        final hg = (f['goals']?['home'] as num?)?.toInt() ?? 0;
        final ag = (f['goals']?['away'] as num?)?.toInt() ?? 0;
        totalGoles += hg + ag;
        if (hg + ag > maxGoles) {
          maxGoles = hg + ag;
          final hn = f['teams']?['home']?['name'] ?? '';
          final an = f['teams']?['away']?['name'] ?? '';
          maxPartido = '$hn $hg-$ag $an';
        }
      }
      out['partidosJugados'] = pj;
      out['totalGoles'] = totalGoles;
      out['partidoMasGoles'] = maxPartido;
      out['partidoMasGolesTotal'] = maxGoles;
      if (pj > 0) {
        final topList = await getGoleadoresTorneoRanking();
        out['topGoleadores'] = topList;
        out['goleadoresDisponibles'] = topList.isNotEmpty;
      }
    } catch (_) {}
    return out;
  }

  /// Distribución del plantel por liga de club (statistics) y resumen de edad.
  static Map<String, dynamic> analisisCapasPlantel(List<Map<String, dynamic>> plantel) {
    final porLiga = <String, int>{};
    var conClub = 0;
    var sumEdad = 0;
    var nEdad = 0;
    var titularesPotenciales = 0;

    for (final row in plantel) {
      final pl = childMap(row['player']);
      final edad = (pl['age'] as num?)?.toInt();
      if (edad != null && edad > 0) {
        sumEdad += edad;
        nEdad++;
      }
      final st = statisticsMundialLiga1(row);
      final games = childMap(st?['games']);
      final pj = _partidosDesdeGamesMap(games);
      if (pj > 0) titularesPotenciales++;

      final team = childMap(st?['team']);
      final league = childMap(st?['league']);
      var etiqueta = league['name'] as String? ?? '';
      if (etiqueta.isEmpty) etiqueta = team['name'] as String? ?? 'Sin club';
      if (etiqueta.trim().isEmpty) etiqueta = 'Otro';
      porLiga[etiqueta] = (porLiga[etiqueta] ?? 0) + 1;
      if (team.isNotEmpty) conClub++;
    }

    final ligasOrdenadas = porLiga.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'porLiga': ligasOrdenadas.map((e) => {'liga': e.key, 'cant': e.value}).toList(),
      'jugadores': plantel.length,
      'conEstadisticaClub': conClub,
      'edadPromedio': nEdad > 0 ? (sumEdad / nEdad).round() : 0,
      'conPJEnMundial': titularesPotenciales,
    };
  }

  static List<Map<String, dynamic>> partidosDeEquipo(
    List<Map<String, dynamic>> fixture,
    int teamId,
  ) {
    if (teamId <= 0) return fixture;
    return fixture.where((p) {
      final h = (p['teams']?['home']?['id'] as num?)?.toInt();
      final a = (p['teams']?['away']?['id'] as num?)?.toInt();
      return h == teamId || a == teamId;
    }).toList();
  }

  static List<Map<String, dynamic>> filtrarFixture({
    required List<Map<String, dynamic>> partidos,
    int? soloEquipoId,
    bool soloEnVivo = false,
    bool soloEliminatoria = false,
  }) {
    return partidos.where((p) {
      if (soloEquipoId != null && soloEquipoId > 0) {
        final h = (p['teams']?['home']?['id'] as num?)?.toInt();
        final a = (p['teams']?['away']?['id'] as num?)?.toInt();
        if (h != soloEquipoId && a != soloEquipoId) return false;
      }
      final st = p['fixture']?['status']?['short'] as String? ?? '';
      if (soloEnVivo && !const {'1H', '2H', 'HT', 'ET', 'P'}.contains(st)) return false;
      if (soloEliminatoria) {
        final r = (p['league']?['round'] as String? ?? '').toLowerCase();
        if (r.contains('group')) return false;
      }
      return true;
    }).toList();
  }

  // ── Índice HDF · favoritos al título (forma en el torneo) ─────────────────

  static Map<String, dynamic>? _favoritosTituloCache;
  static DateTime? _favoritosTituloCacheAt;
  static const Duration _favoritosTituloTtl = Duration(minutes: 12);
  static final Map<int, Map<String, dynamic>?> _statsFixtureCache = {};

  static double _norm01(double v, double max) => max <= 0 ? 0 : (v / max).clamp(0.0, 1.0);

  static double _indiceHdfEquipo({
    required int pts,
    required int pj,
    required int gf,
    required int ga,
    required double posProm,
    required double tirosProm,
    required double cornersProm,
    required int pjStats,
  }) {
    final partidos = pj > 0 ? pj : (pjStats > 0 ? pjStats : 0);
    if (partidos <= 0) return 0;
    final ppg = pts / partidos;
    final gpg = gf / partidos;
    final gdpg = (gf - ga) / partidos;
    final cPts = _norm01(ppg, 3);
    final cGf = _norm01(gpg, 2.5);
    final cGd = _norm01(gdpg + 0.5, 2.5);
    final cPos = _norm01(posProm, 100);
    final cTir = pjStats > 0 ? _norm01(tirosProm, 9) : 0.5;
    final cCor = pjStats > 0 ? _norm01(cornersProm, 8) : 0.5;
    return 100 *
        (0.34 * cPts + 0.12 * cGf + 0.14 * cGd + 0.18 * cPos + 0.14 * cTir + 0.08 * cCor);
  }

  static void _acumularStatsPartido(
    Map<int, Map<String, dynamic>> equipos,
    Map<String, dynamic>? statsResp,
  ) {
    final list = statsResp?['response'];
    if (list is! List || list.length < 2) return;
    for (final raw in list) {
      if (raw is! Map) continue;
      final block = Map<String, dynamic>.from(raw);
      final tid = (block['team']?['id'] as num?)?.toInt() ?? 0;
      if (tid <= 0) continue;
      final agg = equipos.putIfAbsent(tid, () => {
            'id': tid,
            'nombre': block['team']?['name'] ?? '',
            'logo': block['team']?['logo'] ?? '',
            'pts': 0,
            'pj': 0,
            'gf': 0,
            'ga': 0,
            'posSum': 0.0,
            'shotsSum': 0.0,
            'cornerSum': 0.0,
            'statPj': 0,
          });
      final stats = block['statistics'] as List? ?? [];
      double pos = 0, shots = 0, corners = 0;
      for (final s in stats) {
        if (s is! Map) continue;
        final tipo = s['type'] as String? ?? '';
        final val = s['value'];
        if (tipo == 'Ball Possession') {
          pos = double.tryParse(val?.toString().replaceAll('%', '') ?? '') ?? 0;
        } else if (tipo == 'Shots on Goal') {
          shots = double.tryParse(val?.toString() ?? '') ?? 0;
        } else if (tipo == 'Corner Kicks') {
          corners = double.tryParse(val?.toString() ?? '') ?? 0;
        }
      }
      agg['posSum'] = (agg['posSum'] as double) + pos;
      agg['shotsSum'] = (agg['shotsSum'] as double) + shots;
      agg['cornerSum'] = (agg['cornerSum'] as double) + corners;
      agg['statPj'] = (agg['statPj'] as int) + 1;
    }
  }

  /// Ranking de poder en el torneo (pts, goles, posesión, tiros, córners). Cache 12 min.
  static Future<Map<String, dynamic>> getProyeccionFavoritosTitulo({
    int? destacarLocalId,
    int? destacarVisitanteId,
    int topN = 8,
  }) async {
    final now = DateTime.now();
    if (_favoritosTituloCache != null &&
        _favoritosTituloCacheAt != null &&
        now.difference(_favoritosTituloCacheAt!) < _favoritosTituloTtl) {
      return _favoritosTituloCache!;
    }

    final equipos = <int, Map<String, dynamic>>{};

    try {
      final grupos = await getGrupos();
      for (final g in grupos) {
        for (final row in g) {
          final team = childMap(row['team']);
          final id = (team['id'] as num?)?.toInt() ?? 0;
          if (id <= 0) continue;
          final all = childMap(row['all']);
          final goals = childMap(all['goals']);
          equipos[id] = {
            'id': id,
            'nombre': team['name'] ?? '',
            'logo': team['logo'] ?? '',
            'pts': row['points'] as int? ?? 0,
            'pj': all['played'] as int? ?? 0,
            'gf': goals['for'] as int? ?? _statInt(goals['for']),
            'ga': goals['against'] as int? ?? _statInt(goals['against']),
            'posSum': 0.0,
            'shotsSum': 0.0,
            'cornerSum': 0.0,
            'statPj': 0,
          };
        }
      }

      final fixes = await getFixture();
      final ft = fixes.where((p) {
        final st = p['fixture']?['status']?['short'] as String? ?? '';
        return const {'FT', 'AET', 'PEN'}.contains(st);
      }).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['fixture']?['date'] as String? ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['fixture']?['date'] as String? ?? '') ?? DateTime(2000);
          return db.compareTo(da);
        });

      var statsLeidos = 0;
      for (final p in ft.take(28)) {
        final fid = (p['fixture']?['id'] as num?)?.toInt();
        if (fid == null || fid <= 0) continue;
        Map<String, dynamic>? st = _statsFixtureCache[fid];
        if (st == null && !_statsFixtureCache.containsKey(fid)) {
          st = await ApiService.getEstadisticasPartido(fid);
          _statsFixtureCache[fid] = st;
          await Future<void>.delayed(const Duration(milliseconds: 70));
        }
        _acumularStatsPartido(equipos, st);
        if (st != null) statsLeidos++;
      }

      final ranking = <Map<String, dynamic>>[];
      for (final e in equipos.values) {
        final pj = e['pj'] as int;
        final statPj = e['statPj'] as int;
        final posProm = statPj > 0 ? (e['posSum'] as double) / statPj : 0.0;
        final tirosProm = statPj > 0 ? (e['shotsSum'] as double) / statPj : 0.0;
        final corProm = statPj > 0 ? (e['cornerSum'] as double) / statPj : 0.0;
        final indice = _indiceHdfEquipo(
          pts: e['pts'] as int,
          pj: pj,
          gf: e['gf'] as int,
          ga: e['ga'] as int,
          posProm: posProm,
          tirosProm: tirosProm,
          cornersProm: corProm,
          pjStats: statPj,
        );
        if (indice <= 0 && pj == 0) {
          if (ft.isNotEmpty) continue;
          final pre = (e['pts'] as int) * 10 + (e['gf'] as int) - (e['ga'] as int);
          if (pre <= 0) continue;
          ranking.add({
            'id': e['id'],
            'nombre': e['nombre'],
            'logo': e['logo'],
            'indice': pre,
            'pts': e['pts'],
            'pj': pj,
            'gf': e['gf'],
            'ga': e['ga'],
            'posProm': 0,
            'tirosProm': '—',
            'cornersProm': '—',
          });
          continue;
        }
        ranking.add({
          'id': e['id'],
          'nombre': e['nombre'],
          'logo': e['logo'],
          'indice': indice.round(),
          'pts': e['pts'],
          'pj': pj,
          'gf': e['gf'],
          'ga': e['ga'],
          'posProm': posProm.round(),
          'tirosProm': tirosProm.toStringAsFixed(1),
          'cornersProm': corProm.toStringAsFixed(1),
        });
      }
      ranking.sort((a, b) => (b['indice'] as int).compareTo(a['indice'] as int));

      final sumIndice = ranking.fold<double>(0, (s, r) => s + (r['indice'] as int));
      for (final r in ranking) {
        final pct = sumIndice > 0 ? ((r['indice'] as int) / sumIndice * 100) : 0.0;
        r['pctTitulo'] = pct.toStringAsFixed(1);
      }

      Map<String, dynamic>? detalleEquipo(int? tid) {
        if (tid == null || tid <= 0) return null;
        final idx = ranking.indexWhere((r) => r['id'] == tid);
        if (idx < 0) return null;
        final r = ranking[idx];
        return {...r, 'puesto': idx + 1};
      }

      final out = {
        'ranking': ranking.take(topN).toList(),
        'rankingCompleto': ranking,
        'local': detalleEquipo(destacarLocalId),
        'visitante': detalleEquipo(destacarVisitanteId),
        'partidosFt': ft.length,
        'partidosConStats': statsLeidos,
        'hayDatos': ranking.isNotEmpty,
        'esPreliminar': ft.isEmpty && ranking.isNotEmpty,
      };
      _favoritosTituloCache = out;
      _favoritosTituloCacheAt = now;
      return out;
    } catch (_) {
      return {
        'ranking': <Map<String, dynamic>>[],
        'rankingCompleto': <Map<String, dynamic>>[],
        'local': null,
        'visitante': null,
        'hayDatos': false,
        'partidosFt': 0,
        'partidosConStats': 0,
      };
    }
  }
}
