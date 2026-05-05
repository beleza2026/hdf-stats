import 'dart:convert';
import 'package:http/http.dart' as http;

class MundialService {
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _leagueId = 1;
  static const int _season = 2026;

  static Map<String, String> get _headers => {
        'x-apisports-key': _apiKey,
      };

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
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      return items.cast<Map<String, dynamic>>();
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
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      return items.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── GRUPOS ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getGrupos() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_leagueId&season=$_season'),
        headers: _headers,
      );
      final data = json.decode(response.body);
      final List standings = data['response'] ?? [];
      if (standings.isEmpty) return [];
      final List league = standings[0]['league']['standings'] ?? [];
      return league.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
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
      final data = json.decode(response.body);
      final List items = data['response'] ?? [];
      return items.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
  /// Top jugadores por rating — Mundial 2026
  static Future<List<Map<String, dynamic>>> getMejoresJugadores() async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://v3.football.api-sports.io/players?league=1&season=2026&page=1'),
        headers: {'x-apisports-key': apiKey},
      );
      final data = jsonDecode(response.body);
      final jugadores = List<Map<String, dynamic>>.from(data['response'] ?? []);
      jugadores.removeWhere((j) {
        final r = j['statistics']?.first?['games']?['rating'];
        return r == null;
      });
      jugadores.sort((a, b) {
        final ra = double.tryParse(
                a['statistics']?.first?['games']?['rating']?.toString() ?? '') ??
            0.0;
        final rb = double.tryParse(
                b['statistics']?.first?['games']?['rating']?.toString() ?? '') ??
            0.0;
        return rb.compareTo(ra);
      });
      return jugadores.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  /// Top jugadores por rating — Mundial 2026
  static Future<List<Map<String, dynamic>>> getMejoresJugadores() async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://v3.football.api-sports.io/players?league=1&season=2026&page=1'),
        headers: {'x-apisports-key': apiKey},
      );
      final data = jsonDecode(response.body);
      final jugadores = List<Map<String, dynamic>>.from(data['response'] ?? []);
      jugadores.removeWhere((j) {
        final r = j['statistics']?.first?['games']?['rating'];
        return r == null;
      });
      jugadores.sort((a, b) {
        final ra = double.tryParse(
                a['statistics']?.first?['games']?['rating']?.toString() ?? '') ??
            0.0;
        final rb = double.tryParse(
                b['statistics']?.first?['games']?['rating']?.toString() ?? '') ??
            0.0;
        return rb.compareTo(ra);
      });
      return jugadores.take(20).toList();
    } catch (e) {
      return [];
    }
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
}
