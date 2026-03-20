import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _ligaArgentina = 128;
  static const int _season = 2026;

  static Map<String, String> get _headers => {
    'x-apisports-key': _apiKey,
  };

  static Future<List<Map<String, dynamic>>> getPartidosHoy() async {
    final hoy = DateTime.now();
    final fecha = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&date=$fecha'),
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

  static Future<Map<String, List<Map<String, dynamic>>>> getTablas() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final standings = data['response'][0]['league']['standings'] as List;
        Map<String, List<Map<String, dynamic>>> zonas = {};
        for (int i = 0; i < standings.length; i++) {
          final zona = standings[i] as List;
          zonas['Zona ${String.fromCharCode(65 + i)}'] =
              zona.map((e) => e as Map<String, dynamic>).toList();
        }
        return zonas;
      }
      return {};
    } catch (e) {
      return {};
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
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List;
        final lista = fixtures.map((f) => f as Map<String, dynamic>).toList();
        if (lista.isEmpty) return [];
        final primerLeagueId = lista[0]['league']['id'];
        return lista.where((f) => f['league']['id'] == primerLeagueId).toList();
      }
      return [];
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

  static Future<List<Map<String, dynamic>>> getArqueros() async {
    try {
      // Usar endpoint de topassists para jugadores con más atajadas
      // La API no tiene endpoint directo de arqueros, usamos players con filtro
      final response = await http.get(
        Uri.parse('$_baseUrl/players?league=$_ligaArgentina&season=$_season&position=Goalkeeper'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final players = data['response'] as List;
        final arqueros = players.map((p) => p as Map<String, dynamic>).toList();
        // Ordenar por menos goles concedidos
        arqueros.sort((a, b) {
          final ga = a['statistics'][0]['goals']['conceded'] as int? ?? 999;
          final gb = b['statistics'][0]['goals']['conceded'] as int? ?? 999;
          return ga.compareTo(gb);
        });
        return arqueros;
      }
      return [];
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
  }static Future<List<Map<String, dynamic>>> getLineupsPartido(int fixtureId) async {
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
}
