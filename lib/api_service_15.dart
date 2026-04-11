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
static Future<Map<String, List<Map<String, dynamic>>>> getTablasTiempos() async {
    try {
      final resFixtures = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      final resTablas = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (resFixtures.statusCode == 200 && resTablas.statusCode == 200) {
        final dataFixtures = jsonDecode(resFixtures.body);
        final dataTablas = jsonDecode(resTablas.body);
        final fixtures = dataFixtures['response'] as List;
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
          final ht = f['score']['halftime'];
          final ft = f['score']['fulltime'];
          if (ht == null || ht['home'] == null || ht['away'] == null) continue;
          if (ft == null || ft['home'] == null || ft['away'] == null) continue;
          final homeId = f['teams']['home']['id'] as int;
          final awayId = f['teams']['away']['id'] as int;
          final zona = idZona[homeId] ?? idZona[awayId];
          if (zona == null) continue;
          if (idZona[homeId] != idZona[awayId]) continue;
          initEquipo(zona, homeId);
          initEquipo(zona, awayId);

          final htHome = ht['home'] as int;
          final htAway = ht['away'] as int;
          final ftHome = ft['home'] as int;
          final ftAway = ft['away'] as int;
          final stHome = ftHome - htHome;
          final stAway = ftAway - htAway;

          // 1er tiempo
          zonas[zona]![homeId]!['pj1'] += 1;
          zonas[zona]![awayId]!['pj1'] += 1;
          if (htHome > htAway) {
            zonas[zona]![homeId]!['g1'] += 1; zonas[zona]![homeId]!['pts1'] += 3;
            zonas[zona]![awayId]!['p1'] += 1;
          } else if (htHome == htAway) {
            zonas[zona]![homeId]!['e1'] += 1; zonas[zona]![homeId]!['pts1'] += 1;
            zonas[zona]![awayId]!['e1'] += 1; zonas[zona]![awayId]!['pts1'] += 1;
          } else {
            zonas[zona]![awayId]!['g1'] += 1; zonas[zona]![awayId]!['pts1'] += 3;
            zonas[zona]![homeId]!['p1'] += 1;
          }

          // 2do tiempo
          zonas[zona]![homeId]!['pj2'] += 1;
          zonas[zona]![awayId]!['pj2'] += 1;
          if (stHome > stAway) {
            zonas[zona]![homeId]!['g2'] += 1; zonas[zona]![homeId]!['pts2'] += 3;
            zonas[zona]![awayId]!['p2'] += 1;
          } else if (stHome == stAway) {
            zonas[zona]![homeId]!['e2'] += 1; zonas[zona]![homeId]!['pts2'] += 1;
            zonas[zona]![awayId]!['e2'] += 1; zonas[zona]![awayId]!['pts2'] += 1;
          } else {
            zonas[zona]![awayId]!['g2'] += 1; zonas[zona]![awayId]!['pts2'] += 3;
            zonas[zona]![homeId]!['p2'] += 1;
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
      final resStandings = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (resStandings.statusCode != 200) return [];
      final standingsData = jsonDecode(resStandings.body);
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
      // 1. Traer fixture para calcular partidos jugados por equipo automaticamente
      final resFixture = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      int maxPartidos = 1;
      if (resFixture.statusCode == 200) {
        final dataF = jsonDecode(resFixture.body);
        final fixtures = dataF['response'] as List;
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

      // Traer foto del Ã¡rbitro (una sola vez por Ã¡rbitro)
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

        // Calcular equipo mÃ¡s beneficiado y perjudicado
        final equipoStats = a['equipoStats'] as Map<int, Map<String, dynamic>>;
        String equipoBeneficiado = '-';
        String equipoPerjudicado = '-';
        int maxScore = -999, minScore = 999;
        for (var eq in equipoStats.values) {
          final p = eq['partidos'] as int;
          if (p == 0) continue;
          final score = (eq['penales'] as int) * 3 - (eq['amarillas'] as int) - (eq['rojas'] as int) * 3;
          if (score > maxScore) { maxScore = score; equipoBeneficiado = eq['nombre'] as String; }
          if (score < minScore) { minScore = score; equipoPerjudicado = eq['nombre'] as String; }
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
      // Encontrar la Ãºltima fecha jugada y tomar la siguiente
      int ultimaFechaJugada = 0;
      for (final f in fechas) {
        final partidos = porFecha[f]!;
        final tieneFT = partidos.any((p) {
          final s = p['fixture']['status']['short'] as String;
          return s == 'FT' || s == 'AET' || s == 'PEN';
        });
        if (tieneFT && f > ultimaFechaJugada) ultimaFechaJugada = f;
      }
      // PrÃ³xima = primera fecha con nÃºmero mayor a la Ãºltima jugada que tenga NS
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

      // 3. Para cada partido calcular predicciÃ³n
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

        // â”€â”€ ALGORITMO v2: 40% FORMA CONDICIÃ“N + 35% TORNEO + 25% H2H â”€â”€

        // â€” BLOQUE A: Forma reciente en CONDICIÃ“N (local como local, visitante como visitante) â€”
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

        // â€” BLOQUE B: Stats torneo en condiciÃ³n â€”
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

        // â€” BLOQUE C: H2H histÃ³rico (Ãºltimos 10) â€”
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

        // â€” MIX FINAL: 40% forma condiciÃ³n + 35% torneo + 25% H2H â€”
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

        // â€” MARCADOR PREDICHO â€”
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

        // Ajuste por forma reciente (Â±0.3 goles mÃ¡ximo)
        final ajusteGolesL = ((formaLocalNorm - 0.5) * 0.6).clamp(-0.3, 0.3);
        final ajusteGolesV = ((formaVisitNorm - 0.5) * 0.6).clamp(-0.3, 0.3);
        golesLocalEsp = (golesLocalEsp + ajusteGolesL + 0.1).clamp(0.3, 3.5);
        golesVisitEsp = (golesVisitEsp + ajusteGolesV).clamp(0.2, 2.8);

        final golesLocalPred = golesLocalEsp.round().clamp(0, 4);
        final golesVisitPred = golesVisitEsp.round().clamp(0, 3);

        // Forma reciente para display (bolitas W/D/L â€” Ãºltimos 5 general)
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

  static Future<List<Map<String, dynamic>>> getTablaDTs() async {
    try {
      // 1. Traer todos los fixtures y filtrar FT en cÃ³digo (status=FT no funciona en todos los planes)
      final resFixtures = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (resFixtures.statusCode != 200) return [];
      final todosFixtures = (jsonDecode(resFixtures.body)['response'] as List).cast<Map<String, dynamic>>();
      final fixtures = todosFixtures.where((f) {
        final status = f['fixture']['status']['short'] as String? ?? '';
        return status == 'FT' || status == 'AET' || status == 'PEN';
      }).toList();

      // 2. Traer lineups en lotes de 20 en paralelo
      final Map<String, Map<String, dynamic>> dts = {};

      void registrarDT(Map<String, dynamic> coach, String equipoNombre, int equipoId, bool gano, bool empato) {
        final id = coach['id']?.toString() ?? '';
        if (id.isEmpty) return;
        dts.putIfAbsent(id, () => ({
          'id': id,
          'nombre': coach['name'] ?? '',
          'foto': coach['photo'],
          'equipo': equipoNombre,
          'equipoId': equipoId,
          'partidos': 0, 'victorias': 0, 'empates': 0, 'derrotas': 0,
          'racha': <String>[],
        }));
        dts[id]!['partidos'] += 1;
        if (gano) { dts[id]!['victorias'] += 1; (dts[id]!['racha'] as List).add('W'); }
        else if (empato) { dts[id]!['empates'] += 1; (dts[id]!['racha'] as List).add('D'); }
        else { dts[id]!['derrotas'] += 1; (dts[id]!['racha'] as List).add('L'); }
        // Actualizar equipo actual (Ãºltimo partido)
        dts[id]!['equipo'] = equipoNombre;
        dts[id]!['equipoId'] = equipoId;
      }

      const loteSize = 20;
      for (int i = 0; i < fixtures.length; i += loteSize) {
        final lote = fixtures.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((f) async {
          final fixtureId = f['fixture']['id'];
          final homeGoals = f['goals']['home'] as int? ?? 0;
          final awayGoals = f['goals']['away'] as int? ?? 0;
          final homeId = f['teams']['home']['id'] as int;
          final awayId = f['teams']['away']['id'] as int;
          final homeName = f['teams']['home']['name'] as String;
          final awayName = f['teams']['away']['name'] as String;
          try {
            final res = await http.get(
              Uri.parse('$_baseUrl/fixtures/lineups?fixture=$fixtureId'),
              headers: _headers,
            );
            if (res.statusCode != 200) return;
            final lineups = (jsonDecode(res.body)['response'] as List).cast<Map<String, dynamic>>();
            for (var lineup in lineups) {
              final coach = lineup['coach'] as Map<String, dynamic>?;
              if (coach == null) continue;
              final isHome = lineup['team']?['id'] == homeId;
              final teamName = isHome ? homeName : awayName;
              final teamId = isHome ? homeId : awayId;
              final gano = isHome ? homeGoals > awayGoals : awayGoals > homeGoals;
              final empato = homeGoals == awayGoals;
              registrarDT(coach, teamName, teamId, gano, empato);
            }
          } catch (e) {}
        }));
      }

      // 3. Calcular stats finales
      final result = dts.values.map((dt) {
        final partidos = dt['partidos'] as int;
        final victorias = dt['victorias'] as int;
        final empates = dt['empates'] as int;
        final puntos = victorias * 3 + empates;
        final puntosMaximos = partidos * 3;
        final pctPuntos = puntosMaximos > 0 ? (puntos / puntosMaximos * 100) : 0.0;
        final rachaLista = (dt['racha'] as List).cast<String>();
        // Racha actual: Ãºltimos resultados consecutivos iguales al Ãºltimo
        String rachaActual = '';
        if (rachaLista.isNotEmpty) {
          final ultimo = rachaLista.last;
          int count = 0;
          for (int i = rachaLista.length - 1; i >= 0; i--) {
            if (rachaLista[i] == ultimo) count++;
            else break;
          }
          rachaActual = '$count$ultimo';
        }
        return {
          ...dt,
          'puntos': puntos,
          'pctPuntos': pctPuntos,
          'rachaActual': rachaActual,
          'ultimos5': rachaLista.length >= 5 ? rachaLista.sublist(rachaLista.length - 5) : rachaLista,
        };
      }).toList();

      // 4. Enriquecer con datos personales del DT (edad, nacionalidad, carrera)
      await Future.wait(result.map((dt) async {
        try {
          final res = await http.get(
            Uri.parse('$_baseUrl/coachs?id=${dt['id']}'),
            headers: _headers,
          );
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body)['response'] as List;
          if (data.isEmpty) return;
          final coach = data[0];
          final career = (coach['career'] as List?) ?? [];
          // AÃ±os de experiencia: desde el primer club hasta hoy
          String primerAnio = '';
          String ultimoClubAnterior = '';
          if (career.isNotEmpty) {
            final primero = career.last; // career viene de mÃ¡s reciente a mÃ¡s antiguo
            primerAnio = (primero['start'] as String? ?? '').substring(0, 4);
            // Ãšltimo club anterior al actual
            if (career.length > 1) {
              ultimoClubAnterior = career[1]['team']?['name'] as String? ?? '';
            }
          }
          final anioInicio = int.tryParse(primerAnio) ?? 0;
          final aniosExp = anioInicio > 0 ? (2026 - anioInicio) : 0;
          dt['edad'] = coach['age'] ?? 0;
          dt['nacionalidad'] = coach['nationality'] ?? '';
          dt['aniosExp'] = aniosExp;
          dt['clubAnterior'] = ultimoClubAnterior;
          dt['totalClubes'] = career.length;
        } catch (e) {}
      }));

      result.sort((a, b) => (b['pctPuntos'] as double).compareTo(a['pctPuntos'] as double));
      return result;
    } catch (e) {
      return [];
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

      final prompt = 'Sos el analista de HDF Stats, una app argentina de fÃºtbol. AnalizÃ¡ este partido EN VIVO con tono futbolero rioplatense, directo y apasionado. MÃ¡ximo 3 oraciones cortas.\n\nPartido: $local $resultado $visitante (min $minuto)\nPosesiÃ³n: $local $posLocal â€” $visitante $posVisit\nTiros al arco: $local $tirosLocal â€” $visitante $tirosVisit\nTarjetas: $local ${amarillasLocal}ðŸŸ¡ ${rojasLocal}ðŸ”´ â€” $visitante ${amarillasVisit}ðŸŸ¡ ${rojasVisit}ðŸ”´\nÃšltimos eventos:\n$ultimosEventos\n\nDescribÃ­ quÃ© estÃ¡ pasando: quiÃ©n domina, momentum, peligro o algo llamativo. UsÃ¡ emojis de fÃºtbol. Sin asteriscos ni markdown.';

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
        return (data['content'] as List?)?.first?['text'] as String? ?? 'Sin anÃ¡lisis disponible.';
      }
      return 'Sin anÃ¡lisis disponible.';
    } catch (e) {
      return 'Sin anÃ¡lisis disponible.';
    }
  }
  static const int _copaArgentina = 515;

  // Equipos de la liga para onboarding
  static Future<List<Map<String, dynamic>>> getEquiposLiga() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
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
  static Future<Map<String, List<Map<String, dynamic>>>> getTablaMoral() async {
    try {
      // 1. Traer standings para zonas y puntos reales
      final standResp = await http.get(
        Uri.parse('$_baseUrl/standings?league=$_ligaArgentina&season=$_season'),
        headers: _headers,
      );
      if (standResp.statusCode != 200) return {};
      final standData = jsonDecode(standResp.body);
      final standings = standData['response'][0]['league']['standings'] as List;

      final Map<String, String> equipoZona = {};
      final Map<String, int> ptsRealesMap = {};
      for (int i = 0; i < standings.length && i < 2; i++) {
        final zonaLabel = i == 0 ? 'Zona A' : 'Zona B';
        for (final e in (standings[i] as List)) {
          final id = e['team']['id'].toString();
          equipoZona[id] = zonaLabel;
          ptsRealesMap[id] = (e['points'] as num?)?.toInt() ?? 0;
        }
      }

      // 2. Traer fixtures jugados
      final fixtureResp = await http.get(
        Uri.parse('$_baseUrl/fixtures?league=$_ligaArgentina&season=$_season&timezone=America/Argentina/Buenos_Aires'),
        headers: _headers,
      );
      if (fixtureResp.statusCode != 200) return {};
      final fixtures = (jsonDecode(fixtureResp.body)['response'] as List).where((f) {
        final s = f['fixture']['status']['short'];
        return s == 'FT' || s == 'AET' || s == 'PEN';
      }).toList();

      final Map<String, Map<String, dynamic>> tablaMoral = {};

      for (final fixture in fixtures) {
        final fId = fixture['fixture']['id'] as int;
        final homeId = fixture['teams']['home']['id'].toString();
        final awayId = fixture['teams']['away']['id'].toString();
        final homeName = fixture['teams']['home']['name'] as String;
        final awayName = fixture['teams']['away']['name'] as String;
        final homeLogo = fixture['teams']['home']['logo'] as String? ?? '';
        final awayLogo = fixture['teams']['away']['logo'] as String? ?? '';
        final glLocal = (fixture['goals']['home'] as num?)?.toInt() ?? 0;
        final glVisit = (fixture['goals']['away'] as num?)?.toInt() ?? 0;

        // Inicializar equipos
        tablaMoral.putIfAbsent(homeId, () => {
          'nombre': homeName, 'logo': homeLogo,
          'zona': equipoZona[homeId] ?? 'Zona A',
          'pj': 0, 'g': 0, 'e': 0, 'p': 0, 'gf': 0, 'gc': 0, 'pts': 0,
          'ptsReal': ptsRealesMap[homeId] ?? 0,
        });
        tablaMoral.putIfAbsent(awayId, () => {
          'nombre': awayName, 'logo': awayLogo,
          'zona': equipoZona[awayId] ?? 'Zona B',
          'pj': 0, 'g': 0, 'e': 0, 'p': 0, 'gf': 0, 'gc': 0, 'pts': 0,
          'ptsReal': ptsRealesMap[awayId] ?? 0,
        });

        // Calcular Resultado Moral con estadisticas
        int moralL = glLocal, moralV = glVisit;
        try {
          final statsResp = await http.get(
            Uri.parse('$_baseUrl/fixtures/statistics?fixture=$fId'),
            headers: _headers,
          );
          if (statsResp.statusCode == 200) {
            final statsList = jsonDecode(statsResp.body)['response'] as List;
            if (statsList.length >= 2) {
              double posLocal = 50, posVisit = 50;
              int tirosLocal = 0, tirosVisit = 0, cornersLocal = 0, cornersVisit = 0;
              for (final s in (statsList[0]['statistics'] as List)) {
                final v = s['value']?.toString() ?? '0';
                if (s['type'] == 'Ball Possession') posLocal = double.tryParse(v.replaceAll('%', '')) ?? 50;
                if (s['type'] == 'Shots on Goal') tirosLocal = int.tryParse(v) ?? 0;
                if (s['type'] == 'Corner Kicks') cornersLocal = int.tryParse(v) ?? 0;
              }
              for (final s in (statsList[1]['statistics'] as List)) {
                final v = s['value']?.toString() ?? '0';
                if (s['type'] == 'Ball Possession') posVisit = double.tryParse(v.replaceAll('%', '')) ?? 50;
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

        // Acumular
        tablaMoral[homeId]!['pj'] = (tablaMoral[homeId]!['pj'] as int) + 1;
        tablaMoral[awayId]!['pj'] = (tablaMoral[awayId]!['pj'] as int) + 1;
        tablaMoral[homeId]!['gf'] = (tablaMoral[homeId]!['gf'] as int) + moralL;
        tablaMoral[homeId]!['gc'] = (tablaMoral[homeId]!['gc'] as int) + moralV;
        tablaMoral[awayId]!['gf'] = (tablaMoral[awayId]!['gf'] as int) + moralV;
        tablaMoral[awayId]!['gc'] = (tablaMoral[awayId]!['gc'] as int) + moralL;
        if (moralL > moralV) {
          tablaMoral[homeId]!['g'] = (tablaMoral[homeId]!['g'] as int) + 1;
          tablaMoral[homeId]!['pts'] = (tablaMoral[homeId]!['pts'] as int) + 3;
          tablaMoral[awayId]!['p'] = (tablaMoral[awayId]!['p'] as int) + 1;
        } else if (moralV > moralL) {
          tablaMoral[awayId]!['g'] = (tablaMoral[awayId]!['g'] as int) + 1;
          tablaMoral[awayId]!['pts'] = (tablaMoral[awayId]!['pts'] as int) + 3;
          tablaMoral[homeId]!['p'] = (tablaMoral[homeId]!['p'] as int) + 1;
        } else {
          tablaMoral[homeId]!['e'] = (tablaMoral[homeId]!['e'] as int) + 1;
          tablaMoral[homeId]!['pts'] = (tablaMoral[homeId]!['pts'] as int) + 1;
          tablaMoral[awayId]!['e'] = (tablaMoral[awayId]!['e'] as int) + 1;
          tablaMoral[awayId]!['pts'] = (tablaMoral[awayId]!['pts'] as int) + 1;
        }
      }

      // Agrupar por zona y ordenar
      final Map<String, List<Map<String, dynamic>>> resultado = {
        'Zona A': [],
        'Zona B': [],
      };
      for (final entry in tablaMoral.entries) {
        final eq = {...entry.value, 'id': entry.key};
        final zona = eq['zona'] as String;
        if (resultado.containsKey(zona)) {
          resultado[zona]!.add(eq);
        } else {
          resultado['Zona A']!.add(eq);
        }
      }
      for (final zona in resultado.keys) {
        resultado[zona]!.sort((a, b) {
          final diff = (b['pts'] as int).compareTo(a['pts'] as int);
          if (diff != 0) return diff;
          return ((b['gf'] as int) - (b['gc'] as int)).compareTo((a['gf'] as int) - (a['gc'] as int));
        });
      }
      return resultado;
    } catch (e) {
      return {};
    }
  }


}



