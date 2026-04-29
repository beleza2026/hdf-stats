import 'package:http/http.dart' as http;
import 'dart:convert';

class CopaService {
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const int _season = 2026;
static const int _seasonCopas = 2025;
  static const int leagueLibertadores = 13;
  static const int leagueSudamericana = 14;

  static const Map<String, String> _headers = {
    'x-apisports-key': _apiKey,
  };

  // HOY — solo partidos con equipos argentinos
  static Future<List<Map<String, dynamic>>> getPartidosHoy(int leagueId) async {
    final hoy = DateTime.now().toLocal();
    final fecha =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$leagueId&season=$_season&date=$fecha&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        // Filtrar partidos donde alguno de los equipos es argentino
        return fixtures
            .map((f) => f as Map<String, dynamic>)
            .where((f) {
              final homeCountry =
                  f['teams']?['home']?['country'] as String? ?? '';
              final awayCountry =
                  f['teams']?['away']?['country'] as String? ?? '';
              return homeCountry == 'Argentina' || awayCountry == 'Argentina';
            })
            .toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // FIXTURE completo del torneo
  static Future<List<Map<String, dynamic>>> getFixture(int leagueId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/fixtures?league=$leagueId&season=$_season&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        return fixtures.map((f) => f as Map<String, dynamic>).toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // TABLA DE GRUPOS
  static Future<List<Map<String, dynamic>>> getGrupos(int leagueId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/standings?league=$leagueId&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final standings = data['response'] as List;
        if (standings.isEmpty) return [];
        final league = standings[0]['league'];
        final grupos = league['standings'] as List;
        return grupos.map((g) => {'grupo': g}).toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // GOLEADORES
  static Future<List<Map<String, dynamic>>> getGoleadores(int leagueId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/players/topscorers?league=$leagueId&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        return players.map((p) => p as Map<String, dynamic>).toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // EQUIPOS ARGENTINOS en el torneo (para plantel)
  static Future<List<Map<String, dynamic>>> getEquiposArgentinos(
      int leagueId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/teams?league=$leagueId&season=$_season&country=Argentina'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final teams = data['response'] as List;
        return teams.map((t) => t as Map<String, dynamic>).toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  // PLANTEL + STATS de un equipo en el torneo
  static Future<List<Map<String, dynamic>>> getPlantelStats(
      int leagueId, int teamId, {int pagina = 1}) async {
    try {
      final response = await http.get(
        Uri.parse(
           '$_baseUrl/players?league=$leagueId&season=$_seasonCopas&team=$teamId&page=$pagina'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        return players.map((p) => p as Map<String, dynamic>).toList();
      }
    } catch (e) {
      // ignore
    }
    return [];
  }
}
