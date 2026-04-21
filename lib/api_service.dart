import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'racha_model.dart';

class ApiService {
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _ligaArgentina = 128;
  static const int _season = 2026;

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

  static void clearCache() {
    _standingsFuture = null;
    _fixturesFuture = null;
    _tiemposFuture = null;
    _rachasCache = null;
    _tablaDTsCache = null;
    _fixturesPrevFuture = null;
  }

  static Future<dynamic> _getStandingsData() {
    _standingsFuture ??= http.get(
      Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
      headers: _headers,
    ).then((r) => r.statusCode == 200 ? jsonDecode(r.body) : null);
    return _standingsFuture!;
  }

  static Future<List> _getFixturesData() {
    _fixturesFuture ??= http.get(
      Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
      headers: _headers,
    ).then((r) => r.statusCode == 200
        ? (jsonDecode(r.body)['response'] as List)
        : <dynamic>[]);
    return _fixturesFuture!;
  }
  // ─────────────────────────────────────────────────────────────────

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
      final data = await _getStandingsData();
      if (data != null) {
        final standings = data['response'][0]['league']['standings'] as List;
        Map<String, List<Map<String, dynamic>>> zonas = {};
        for (int i = 0; i < standings.length && i < 2; i++) {
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
      print('H2H llamada: $homeId vs $awayId');
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
      final List<Map<String, dynamic>> arqueros = [];
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
        // Delay entre lotes para no saturar la API
        if (i + loteSize < teamList.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // 3. Calcular minutos sin goles
      for (var a in arqueros) {
        final stats = a['statistics'][0];
        final conceded = stats['goals']?['conceded'] as int? ?? 0;
        final minutos = stats['games']?['minutes'] as int? ?? 0;
        a['minutosSinGol'] = conceded > 0 ? (minutos / conceded).round() : minutos;
      }

      // 4. Ordenar por menor ratio goles concedidos/partido
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
  static Future<List<Map<String, dynamic>>> getPlayersPartido(String fixtureId) async {
    final url = Uri.parse('$_baseUrl/fixtures/players?fixture=$fixtureId');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    final teams = data['response'] as List;
    List<Map<String, dynamic>> jugadores = [];
    for (var team in teams) {
      final teamName = team['team']['name'] as String;
      final teamId = team['team']['id'] as int;
      final teamLogo = team['team']['logo'] as String? ?? '';
      final players = team['players'] as List;
      for (var p in players) {
        final stats = p['statistics'][0];
        final rating = stats['games']['rating'];
        jugadores.add({
          'id': p['player']['id'],
          'nombre': p['player']['name'],
          'foto': p['player']['photo'],
          'equipo': teamName,
          'equipoId': teamId,
          'equipoLogo': teamLogo,
          'rating': rating != null ? (double.tryParse(rating.toString()) ?? 0.0) : 0.0,
          'tieneRating': rating != null,
          'tiros': stats['shots']['on'] ?? 0,
          'pases': stats['passes']['accuracy'] ?? 0,
          'minutos': stats['games']['minutes'] ?? 0,
          'posicion': stats['games']['position'] ?? '',
          'numero': stats['games']['number'] ?? 0,
          'capitan': stats['games']['captain'] ?? false,
          'suplente': stats['games']['substitute'] ?? false,
          'goles': stats['goals']['total'] ?? 0,
          'asistencias': stats['goals']['assists'] ?? 0,
          'saves': stats['goals']['saves'] ?? 0,
          'amarillas': stats['cards']['yellow'] ?? 0,
          'rojas': stats['cards']['red'] ?? 0,
          'faltas': stats['fouls']['committed'] ?? 0,
        });
      }
    }
    jugadores.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
    return jugadores;
  }

  static Future<List<Map<String, dynamic>>> getUltimos5(int teamId) async {
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

  static Future<List<Map<String, dynamic>>> getPredicciones() async {
    try {
      // 1. Traer fixture completo
      final resFixture = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (resFixture.statusCode != 200) return [];
      final todos = (jsonDecode(resFixture.body)['response'] as List).cast<Map<String, dynamic>>();

      // 2. Filtrar solo Apertura (primera mitad) igual que _buildFixture
      final todosOrdenados = List<Map<String, dynamic>>.from(todos)
        ..sort((a, b) => (a['fixture']['id'] as int).compareTo(b['fixture']['id'] as int));
      final mitad = todosOrdenados.length ~/ 2;
      final apertura = todosOrdenados.take(mitad).toList();

      // 3. Encontrar proxima fecha no jugada del Apertura
      Map<int, List<Map<String, dynamic>>> porFecha = {};
      for (var p in apertura) {
        final st = p['fixture']['status']['short'] as String;
        if (st == 'PST' || st == 'CANC' || st == 'TBD') continue;
        final round = p['league']['round'] as String;
        final num = int.tryParse(round.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        porFecha.putIfAbsent(num, () => []).add(p);
      }
      final fechas = porFecha.keys.toList()..sort();
      int? proximaFecha;
      // Encontrar la última fecha jugada y tomar la siguiente
      int ultimaFechaJugada = 0;
      for (final f in fechas) {
        final partidos = porFecha[f]!;
        final tieneFT = partidos.any((p) {
          final s = p['fixture']['status']['short'] as String;
          return s == 'FT' || s == 'AET' || s == 'PEN';
        });
        if (tieneFT && f > ultimaFechaJugada) ultimaFechaJugada = f;
      }
      // Próxima = primera fecha con número mayor a la última jugada que tenga NS
      for (final f in fechas) {
        if (f <= ultimaFechaJugada) continue;
        final partidos = porFecha[f]!;
        final tieneNS = partidos.any((p) => p['fixture']['status']['short'] == 'NS');
        if (tieneNS) { proximaFecha = f; break; }
      }
      if (proximaFecha == null) return [];
      final partidos = porFecha[proximaFecha]!.where((p) {
        final s = p['fixture']['status']['short'] as String;
        return s == 'NS';
      }).toList();

      // 3. Para cada partido calcular predicción
      final resultados = await Future.wait(partidos.map((p) async {
        final homeId = p['teams']['home']['id'] as int;
        final awayId = p['teams']['away']['id'] as int;
        final homeName = p['teams']['home']['name'] as String;
        final awayName = p['teams']['away']['name'] as String;
        final homeLogo = p['teams']['home']['logo'] as String?;
        final awayLogo = p['teams']['away']['logo'] as String?;
        final fechaHora = p['fixture']['date'] as String?;

        final results = await Future.wait([
          getUltimos5(homeId),
          getUltimos5(awayId),
          getHeadToHead(homeId, awayId),
          getStatsEquipo(homeId),
          getStatsEquipo(awayId),
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
          'homeId': homeId, 'awayId': awayId,
          'homeName': homeName, 'awayName': awayName,
          'homeLogo': homeLogo, 'awayLogo': awayLogo,
          'fechaHora': fechaHora,
          'pctLocal': pctLocal, 'pctEmpate': pctEmpate, 'pctVisit': pctVisit,
          'formaLocal': formaRecLocal, 'formaVisit': formaRecVisit,
          'h2hLocal': h2hLocal, 'h2hEmpate': h2hEmpate, 'h2hVisit': h2hVisit,
          'golesLocalPred': golesLocalPred, 'golesVisitPred': golesVisitPred,
          'fecha': proximaFecha,
        };
      }));

      return resultados;
    } catch (e) {
      return [];
    }
  }

  // Cache para TablaDTs
  static List<Map<String, dynamic>>? _tablaDTsCache;

  static Future<List<Map<String, dynamic>>> getTablaDTs({bool forceRefresh = false}) async {
    if (!forceRefresh && _tablaDTsCache != null) return _tablaDTsCache!;
    try {
      // Fixtures terminados, ordenados cronologicamente (asc)
      final allFixtures = await _getFixturesData();
      final fixtures = allFixtures
          .cast<Map<String, dynamic>>()
          .where((f) {
            final s = f['fixture']['status']['short'] as String? ?? '';
            return s == 'FT' || s == 'AET' || s == 'PEN';
          }).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['fixture']['date'] as String? ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['fixture']['date'] as String? ?? '') ?? DateTime(2000);
          return da.compareTo(db);
        });

      // coachId -> stats acumulados
      final Map<String, Map<String, dynamic>> dts = {};

      // Lotes de 10, pausa de 200ms entre lotes
      const loteSize = 10;
      for (int i = 0; i < fixtures.length; i += loteSize) {
        final lote = fixtures.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((f) async {
          final fxId   = f['fixture']['id'] as int;
          final homeId = f['teams']['home']['id'] as int;
          final awayId = f['teams']['away']['id'] as int;
          final hGoals = f['goals']['home'] as int? ?? 0;
          final aGoals = f['goals']['away'] as int? ?? 0;
          try {
            final res = await http.get(
              Uri.parse('$_baseUrl/fixtures/lineups?fixture=$fxId'),
              headers: _headers,
            );
            if (res.statusCode != 200) return;
            final lineups = (jsonDecode(res.body)['response'] as List)
                .cast<Map<String, dynamic>>();
            for (final lu in lineups) {
              final coach = lu['coach'] as Map<String, dynamic>?;
              if (coach == null) continue;
              final coachId = coach['id']?.toString() ?? '';
              if (coachId.isEmpty) continue;

              final luTeamId = lu['team']?['id'] as int?;
              if (luTeamId == null) continue;
              final isHome   = luTeamId == homeId;
              final teamName = (isHome ? f['teams']['home']['name'] : f['teams']['away']['name']) as String;
              final teamLogo = (isHome ? f['teams']['home']['logo'] : f['teams']['away']['logo']) as String? ?? '';
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
            }
          } catch (_) {}
        }));
        if (i + loteSize < fixtures.length) {
          await Future.delayed(const Duration(milliseconds: 200));
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

        return <String, dynamic>{
          ...dt,
          'puntos':      puntos,
          'pctPuntos':   pctPuntos,
          'rachaActual': rachaActual,
          'ultimos5':    ultimos5,
        };
      }).toList()
        ..sort((a, b) => (b['pctPuntos'] as double).compareTo(a['pctPuntos'] as double));

      _tablaDTsCache = result;
      return result;
    } catch (e) {
      return _tablaDTsCache ?? [];
    }
  }

  /// Carga la carrera completa de un DT bajo demanda (al tocar en la tabla)
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

      return {
        'edad':        coach['age'] ?? 0,
        'nacionalidad': coach['nationality'] ?? '',
        'foto':        coach['photo'] ?? '',
        'aniosExp':    anioInicio > 0 ? (2026 - anioInicio) : 0,
        'totalClubes': career.length,
        'carrera':     career,
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
  static const int _copaArgentina = 515;

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
        final response = await http.get(
          Uri.parse('$_baseUrl/fixtures?league=$_copaArgentina&season=$season'),
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

  static Future<Map<String, List<Map<String, dynamic>>>> getTablaMoral() async {
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
          print('HDF_DEBUG ZONA: groupStr=$groupStr');
          if (!groupStr.contains('apertura')) continue;
          print('DEBUG:'+groupStr); final zona = groupStr.contains('group b') ? 'Zona B' : 'Zona A';
          print('HDF_DEBUG ZONA: zona=$zona equipos=${grupo.length}');
          for (final e in grupo) {
            final id = e['team']['id'].toString();
            equipoZona[id] = zona;
            ptsRealesMap[id] = (e['points'] as num?)?.toInt() ?? 0;
            equipoLogo[id] = e['team']['logo'] as String? ?? '';
          }
        }
      }

      final jugados = allFixtures.where((f) {
        final s = f['fixture']['status']['short'];
        return s == 'FT' || s == 'AET' || s == 'PEN';
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

      if (morales.isEmpty) return {};

      // PASO 4: Construir tabla desde morales (Firestore)
      final Map<String, Map<String, dynamic>> tabla = {};
      for (final entry in morales.entries) {
        final data = entry.value;
        // Usar toString() para manejar tanto String como int en Firestore
        final homeId = data['homeId']?.toString() ?? '';
        final awayId = data['awayId']?.toString() ?? '';
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
        await Future.delayed(const Duration(milliseconds: 200));
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
      // Traer plantel primero para obtener IDs
      final squad = await getPlantelSeleccion(teamId);
      if (squad.isEmpty) return [];
      final List<dynamic> result = [];
      // Procesar solo primeros 10 para no gastar calls
      final top = squad.take(10).toList();
      for (final p in top) {
        final playerId = p['id'] as int?;
        if (playerId == null) continue;
        try {
          final uri = Uri.parse('$_baseUrl/players?id=$playerId&season=2024');
          final res = await http.get(uri, headers: _headers);
          final data = jsonDecode(res.body);
          if (data['response'] != null && (data['response'] as List).isNotEmpty) {
            result.add(data['response'][0]);
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return result;
    } catch (e) { return []; }
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

}