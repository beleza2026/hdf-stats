import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_service.dart';

class CopaService {
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const int leagueLibertadores = 13;
  static const int leagueSudamericana = 11;
  /// Copa Argentina — id **130** en API-Sports (515 es Argelia U21, no usar).
  static const int leagueCopaArgentina = 130;

  static const Map<String, String> _headers = {
    'x-apisports-key': _apiKey,
  };

  /// API-Football puede mandar `errors: {}` en respuestas OK.
  static bool _apiErrorsPresent(dynamic decoded) {
    if (decoded is! Map) return false;
    final e = decoded['errors'];
    if (e == null) return false;
    if (e is Map) return e.isNotEmpty;
    if (e is List) return e.isNotEmpty;
    if (e is String) return e.trim().isNotEmpty;
    return false;
  }

  /// Copa Argentina: más temporadas por si la API cambia el año de la edición.
  static List<int> _seasonsFor(int leagueId) {
    if (leagueId == leagueCopaArgentina) {
      return const [2026, 2025, 2024, 2023, 2022];
    }
    return _seasonsCopa;
  }

  static Map<String, dynamic>? _statPreferLiga(Map<String, dynamic> row, int leagueId) {
    final list = row['statistics'] as List?;
    if (list == null || list.isEmpty) return null;
    for (final s in list) {
      if (s is! Map) continue;
      final sm = Map<String, dynamic>.from(s);
      final lid = (sm['league']?['id'] as num?)?.toInt();
      if (lid == leagueId) return sm;
    }
    return Map<String, dynamic>.from(list.first as Map);
  }

  static int _golesDesdeRow(Map<String, dynamic> row, int leagueId) {
    final st = _statPreferLiga(row, leagueId);
    final g = st?['goals'];
    if (g is Map) return (g['total'] as num?)?.toInt() ?? int.tryParse('${g['total']}') ?? 0;
    return 0;
  }

  /// Bloque `statistics` alineado con la liga del torneo (p. ej. Copa Arg. 130).
  static Map<String, dynamic>? statsForLeague(Map<String, dynamic> row, int leagueId) =>
      _statPreferLiga(row, leagueId);

  /// Temporadas a probar en orden (la API a veces usa 2025 u 2026 para la edición vigente).
  static const List<int> _seasonsCopa = [2026, 2025];

  // HOY — Conmebol: todos los partidos del día (sin filtro grupo/ronda/país). Copa Arg.: todos del día.
  static Future<List<Map<String, dynamic>>> getPartidosHoy(int leagueId) async {
    if (leagueId == leagueLibertadores || leagueId == leagueSudamericana) {
      return ApiService.getPartidosHoyConmebol(leagueId);
    }
    final hoy = DateTime.now().toLocal();
    final fecha =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    for (final season in _seasonsFor(leagueId)) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/fixtures?league=$leagueId&season=$season&date=$fecha&timezone=America/Argentina/Buenos_Aires'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (_apiErrorsPresent(data)) continue;
        final fixtures = data['response'] as List? ?? [];
        final list = fixtures.map((f) => f as Map<String, dynamic>).toList();
        if (list.isNotEmpty) {
          list.sort((a, b) {
            final da = DateTime.tryParse(a['fixture']?['date']?.toString() ?? '');
            final db = DateTime.tryParse(b['fixture']?['date']?.toString() ?? '');
            return (da ?? DateTime(2100)).compareTo(db ?? DateTime(2100));
          });
          return list;
        }
      } catch (_) {}
    }
    return [];
  }

  /// En este plan de API-Sports, `&page=1` con timezone devuelve error y 0 resultados; el primer GET va **sin** `page`.
  /// Si hay más de una página y la API acepta `page>=2`, se piden las siguientes.
  static Future<List<Map<String, dynamic>>> _fixturesAllPages(
      int leagueId, int season) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final uri = page == 1
          ? Uri.parse(
              '$_baseUrl/fixtures?league=$leagueId&season=$season&timezone=America/Argentina/Buenos_Aires')
          : Uri.parse(
              '$_baseUrl/fixtures?league=$leagueId&season=$season&timezone=America/Argentina/Buenos_Aires&page=$page');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) break;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (_apiErrorsPresent(data)) break;
      final fixtures = data['response'] as List? ?? [];
      for (final f in fixtures) {
        out.add(f as Map<String, dynamic>);
      }
      final paging = data['paging'];
      final totalPages = paging is Map
          ? (paging['total'] as num?)?.toInt() ?? 1
          : 1;
      if (page >= totalPages || fixtures.isEmpty) break;
      page++;
    }
    return out;
  }

  // FIXTURE completo del torneo (todas las páginas)
  static Future<List<Map<String, dynamic>>> getFixture(int leagueId) async {
    for (final season in _seasonsFor(leagueId)) {
      try {
        final list = await _fixturesAllPages(leagueId, season);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [];
  }

  // TABLA DE GRUPOS
  static Future<List<Map<String, dynamic>>> getGrupos(int leagueId) async {
    for (final season in _seasonsFor(leagueId)) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/standings?league=$leagueId&season=$season'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (_apiErrorsPresent(data)) continue;
        final standings = data['response'] as List? ?? [];
        if (standings.isEmpty) continue;
        final league = standings[0]['league'];
        final grupos = league['standings'] as List;
        return grupos.map((g) => {'grupo': g}).toList();
      } catch (_) {}
    }
    return [];
  }

  // GOLEADORES
  static Future<List<Map<String, dynamic>>> getGoleadores(int leagueId) async {
    for (final season in _seasonsFor(leagueId)) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/players/topscorers?league=$leagueId&season=$season'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (_apiErrorsPresent(data)) continue;
        final players = data['response'] as List? ?? [];
        if (players.isEmpty) continue;
        final list = players.map((p) => p as Map<String, dynamic>).toList();
        list.sort((a, b) => _golesDesdeRow(b, leagueId).compareTo(_golesDesdeRow(a, leagueId)));
        return list;
      } catch (_) {}
    }
    return [];
  }

  // EQUIPOS del torneo (Copa Arg.: sin filtro país primero — la API a veces devuelve 0 con country=Argentina)
  static Future<List<Map<String, dynamic>>> getEquiposArgentinos(
      int leagueId) async {
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    void addAll(List<dynamic> raw) {
      for (final t in raw) {
        if (t is! Map) continue;
        final m = Map<String, dynamic>.from(t);
        final team = m['team'] is Map ? Map<String, dynamic>.from(m['team'] as Map) : null;
        if (team == null) continue;
        final id = (team['id'] as num?)?.toInt() ?? 0;
        if (id <= 0 || !seen.add(id)) continue;
        out.add(m);
      }
    }

    for (final season in _seasonsFor(leagueId)) {
      try {
        var response = await http.get(
          Uri.parse('$_baseUrl/teams?league=$leagueId&season=$season'),
          headers: _headers,
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (!_apiErrorsPresent(data)) {
            addAll(data['response'] as List? ?? []);
          }
        }
        if (leagueId == leagueCopaArgentina && out.isEmpty) {
          response = await http.get(
            Uri.parse(
                '$_baseUrl/teams?league=$leagueId&season=$season&country=Argentina'),
            headers: _headers,
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (!_apiErrorsPresent(data)) {
              addAll(data['response'] as List? ?? []);
            }
          }
        }
      } catch (_) {}
      if (out.isNotEmpty) return out;
    }
    return [];
  }

  // PLANTEL + STATS de un equipo en el torneo
  static Future<List<Map<String, dynamic>>> getPlantelStats(
      int leagueId, int teamId, {int pagina = 1}) async {
    for (final season in _seasonsFor(leagueId)) {
      try {
        final base = '$_baseUrl/players?league=$leagueId&season=$season&team=$teamId';
        final urls = pagina <= 1 ? <String>[base, '$base&page=1'] : <String>['$base&page=$pagina'];
        for (final url in urls) {
          final response = await http.get(Uri.parse(url), headers: _headers);
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          if (_apiErrorsPresent(data)) continue;
          final players = data['response'] as List? ?? [];
          if (players.isNotEmpty) {
            return players.map((p) => p as Map<String, dynamic>).toList();
          }
        }
      } catch (_) {}
    }
    if (leagueId == leagueCopaArgentina && pagina == 1) {
      return _plantelDesdeSquads(teamId);
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _plantelDesdeSquads(int teamId) async {
    if (teamId <= 0) return [];
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/squads?team=$teamId'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      if (_apiErrorsPresent(data)) return [];
      final resp = data['response'] as List? ?? [];
      if (resp.isEmpty) return [];
      final block0 = resp.first;
      if (block0 is! Map) return [];
      final players = block0['players'] as List? ?? [];
      final out = <Map<String, dynamic>>[];
      for (final pl in players) {
        if (pl is! Map) continue;
        final m = Map<String, dynamic>.from(pl);
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final posRaw = m['position'];
        final pos = posRaw is String ? posRaw : null;
        out.add({
          'player': {
            'id': id,
            'name': m['name'],
            'photo': m['photo'],
            'nationality': m['nationality'],
          },
          'statistics': [
            {
              'team': {'id': teamId},
              'games': {
                'position': pos,
                'appearences': 0,
                'appearances': 0,
              },
              'goals': {'total': 0, 'assists': 0},
            },
          ],
        });
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
