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

  /// `teams?id=` — logo de federación / selección, nombre, país.
  static Future<Map<String, dynamic>?> getTeamInfo(int teamId) async {
    if (teamId <= 0) return null;
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

  static Future<List<Map<String, dynamic>>> getTrophiesTeam(int teamId) async {
    if (teamId <= 0) return [];
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

  /// Plantel con estadísticas del Mundial actual (liga 1), todas las páginas.
  static Future<List<Map<String, dynamic>>> getPlantelMundialCompleto(int teamId) async {
    if (teamId <= 0) return [];
    final todos = <Map<String, dynamic>>[];
    try {
      var page = 1;
      while (true) {
        final uri = Uri.parse(
            '$_baseUrl/players?league=$_leagueId&season=$_season&team=$teamId&page=$page');
        final res = await http.get(uri, headers: _headers);
        if (res.statusCode != 200) break;
        final data = json.decode(res.body);
        final players = (data['response'] as List? ?? []).cast<Map<String, dynamic>>();
        todos.addAll(players);
        final totalPages = data['paging']?['total'] as int? ?? 1;
        if (page >= totalPages) break;
        page++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } catch (_) {}
    return todos;
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
  static Future<Map<String, dynamic>> getResumenHistoricoMundial(int teamId) async {
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
    final golesPorJugador = <int, int>{};
    final appsPorJugador = <int, int>{};
    final nombres = <int, String>{};
    final fotos = <int, String>{};

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

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final tops = await _topscorersMundialTemporada(season);
        for (final row in tops) {
          final statsList = row['statistics'] as List?;
          if (statsList == null || statsList.isEmpty) continue;
          final st0 = statsList[0] as Map<String, dynamic>;
          final tid = st0['team']?['id'] as int?;
          if (tid != teamId) continue;
          final pl = row['player'] as Map<String, dynamic>?;
          final pid = pl?['id'] as int?;
          if (pid == null) continue;
          nombres[pid] = pl?['name'] as String? ?? '';
          fotos[pid] = pl?['photo'] as String? ?? '';
          final g = (st0['goals']?['total'] as num?)?.toInt() ?? 0;
          final ap = (st0['games']?['appearences'] as num?)?.toInt() ??
              (st0['games']?['appearances'] as num?)?.toInt() ??
              0;
          golesPorJugador[pid] = (golesPorJugador[pid] ?? 0) + g;
          appsPorJugador[pid] = (appsPorJugador[pid] ?? 0) + ap;
        }
      }

      if (golesPorJugador.isNotEmpty) {
        final bestG = golesPorJugador.entries.reduce((a, b) => a.value >= b.value ? a : b);
        out['goleadorHistoricoNombre'] = nombres[bestG.key] ?? '';
        out['goleadorHistoricoGoles'] = bestG.value;
        out['goleadorHistoricoFoto'] = fotos[bestG.key] ?? '';
      }
      if (appsPorJugador.isNotEmpty) {
        final bestA = appsPorJugador.entries.reduce((a, b) => a.value >= b.value ? a : b);
        out['masPresenciasNombre'] = nombres[bestA.key] ?? '';
        out['masPresenciasPartidos'] = bestA.value;
        out['masPresenciasFoto'] = fotos[bestA.key] ?? '';
      }

      out['partidosJugados'] = pj;
      out['finalesJugadas'] = finales;
      out['mejorPuestoTexto'] = mejorTxt;
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
}
