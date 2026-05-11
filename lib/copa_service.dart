import 'package:http/http.dart' as http;
import 'dart:convert';

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

  /// Temporadas a probar en orden (la API a veces usa 2025 u 2026 para la edición vigente).
  static const List<int> _seasonsCopa = [2026, 2025];

  // HOY — Conmebol: solo partidos con algún equipo argentino. Copa Arg.: todos los del día.
  static Future<List<Map<String, dynamic>>> getPartidosHoy(int leagueId) async {
    final hoy = DateTime.now().toLocal();
    final fecha =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    for (final season in _seasonsCopa) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/fixtures?league=$leagueId&season=$season&date=$fecha&timezone=America/Argentina/Buenos_Aires'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        final list = fixtures
            .map((f) => f as Map<String, dynamic>)
            .where((f) {
              if (leagueId == leagueCopaArgentina) return true;
              final homeCountry =
                  f['teams']?['home']?['country'] as String? ?? '';
              final awayCountry =
                  f['teams']?['away']?['country'] as String? ?? '';
              return homeCountry == 'Argentina' || awayCountry == 'Argentina';
            })
            .toList();
        if (list.isNotEmpty) return list;
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
      final errs = data['errors'];
      if (errs is Map && errs.isNotEmpty) break;
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
    for (final season in _seasonsCopa) {
      try {
        final list = await _fixturesAllPages(leagueId, season);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [];
  }

  // TABLA DE GRUPOS
  static Future<List<Map<String, dynamic>>> getGrupos(int leagueId) async {
    for (final season in _seasonsCopa) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/standings?league=$leagueId&season=$season'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final standings = data['response'] as List;
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
    if (leagueId == leagueCopaArgentina) {
      // Una sola temporada vigente: la primera con datos (2026 antes que 2025).
      // Antes se elegía la lista con más filas → mezclaba ediciones y sumaba de más en la percepción del usuario.
      for (final season in _seasonsCopa) {
        try {
          final response = await http.get(
            Uri.parse(
                '$_baseUrl/players/topscorers?league=$leagueId&season=$season'),
            headers: _headers,
          );
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          final players = data['response'] as List;
          if (players.isEmpty) continue;
          final list =
              players.map((p) => p as Map<String, dynamic>).toList();
          list.sort((a, b) {
            int g(Map<String, dynamic> x) {
              final st = x['statistics'];
              if (st is! List || st.isEmpty) return 0;
              return (st.first['goals']?['total'] as num?)?.toInt() ?? 0;
            }
            return g(b).compareTo(g(a));
          });
          return list;
        } catch (_) {}
      }
      return [];
    }
    for (final season in _seasonsCopa) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/players/topscorers?league=$leagueId&season=$season'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        if (players.isEmpty) continue;
        return players.map((p) => p as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    return [];
  }

  // EQUIPOS ARGENTINOS en el torneo (para plantel)
  static Future<List<Map<String, dynamic>>> getEquiposArgentinos(
      int leagueId) async {
    for (final season in _seasonsCopa) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/teams?league=$leagueId&season=$season&country=Argentina'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final teams = data['response'] as List;
        if (teams.isEmpty) continue;
        return teams.map((t) => t as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    return [];
  }

  // PLANTEL + STATS de un equipo en el torneo
  static Future<List<Map<String, dynamic>>> getPlantelStats(
      int leagueId, int teamId, {int pagina = 1}) async {
    for (final season in _seasonsCopa) {
      try {
        final response = await http.get(
          Uri.parse(
              '$_baseUrl/players?league=$leagueId&season=$season&team=$teamId&page=$pagina'),
          headers: _headers,
        );
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        if (players.isEmpty) continue;
        return players.map((p) => p as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    return [];
  }
}
