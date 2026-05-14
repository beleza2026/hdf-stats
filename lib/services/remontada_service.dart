import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../penales_shootout_helper.dart';

/// Estadísticas de remontada cuando el equipo recibe el primer gol del partido (no en contra / no tanda).
class RemontadaStats {
  /// Mínimo de partidos en los que el rival marcó el 1.er gol para mostrar porcentajes (evita ruido con 1–2 casos).
  static const int minPartidosRecibePrimerGol = 3;

  const RemontadaStats({
    required this.totalPartidosAbajo,
    required this.porcentajeRemontada,
    required this.porcentajeEmpate,
    required this.porcentajeDerrota,
    required this.porcentajeLocalRemontada,
    required this.porcentajeVisitanteRemontada,
    required this.minutoPromedioRemontada,
  });

  final int totalPartidosAbajo;
  final double porcentajeRemontada;
  final double porcentajeEmpate;
  final double porcentajeDerrota;
  final double porcentajeLocalRemontada;
  final double porcentajeVisitanteRemontada;
  /// Minuto del primer gol del equipo luego de ir abajo (solo partidos ganados); 0 si no aplica.
  final double minutoPromedioRemontada;

  static RemontadaStats empty() => const RemontadaStats(
        totalPartidosAbajo: 0,
        porcentajeRemontada: 0,
        porcentajeEmpate: 0,
        porcentajeDerrota: 0,
        porcentajeLocalRemontada: 0,
        porcentajeVisitanteRemontada: 0,
        minutoPromedioRemontada: 0,
      );
}

class RemontadaService {
  RemontadaService._();
  static final RemontadaService instance = RemontadaService._();
  factory RemontadaService() => instance;

  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const Duration _ttl = Duration(hours: 12);
  /// Tope de partidos FT a analizar (cada uno pide eventos; evita rate limit).
  static const int _maxPartidos = 45;
  /// Pocos en paralelo: `/fixtures/events` es sensible a rate limit si se dispara en masa.
  static const int _eventConcurrency = 3;

  static Map<String, String> get _headers => {'x-apisports-key': _apiKey};

  final Map<String, ({RemontadaStats stats, DateTime at})> _cache = {};

  /// Liga Profesional Argentina: acota partidos FT para estadísticas coherentes (evita otros torneos con mismo team id en otros países).
  static const int _ligaProfesionalArgentina = 128;

  String _key(int teamId, int season) => '$teamId:$season:lpf128:v2';

  bool _apiErrorsPresent(dynamic decoded) {
    if (decoded is! Map) return false;
    final e = decoded['errors'];
    if (e == null) return false;
    if (e is Map) return e.isNotEmpty;
    if (e is List) return e.isNotEmpty;
    if (e is String) return e.trim().isNotEmpty;
    return false;
  }

  bool _isGoalEvent(Map<String, dynamic> e) {
    final t = e['type'];
    if (t == 'Goal') return true;
    if (t is String) {
      final s = t.toLowerCase();
      if (s == 'goal' || s.contains('goal')) return true;
    }
    if (t is Map) {
      final short = t['short']?.toString();
      if (short == 'G' || short == 'g') return true;
      final long = t['long']?.toString().toLowerCase() ?? '';
      if (long.contains('goal')) return true;
    }
    return false;
  }

  int _eventMinute(Map<String, dynamic> e) {
    final time = e['time'];
    if (time is! Map) return 0;
    final el = time['elapsed'];
    final ex = time['extra'];
    final a = el is int ? el : (el is num ? el.toInt() : int.tryParse('$el') ?? 0);
    final b = ex is int ? ex : (ex is num ? ex.toInt() : int.tryParse('$ex') ?? 0);
    return a + b;
  }

  int _compareEvents(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _eventMinute(a).compareTo(_eventMinute(b));

  /// Goles del marcador final: primero `goals`, si faltan `score.fulltime` (API-Football).
  (int?, int?) _golesMarcadorFinal(Map<String, dynamic> fx) {
    final g = fx['goals'];
    if (g is Map) {
      final h = g['home'];
      final a = g['away'];
      final ih = h is int ? h : (h is num ? h.toInt() : int.tryParse('$h'));
      final ia = a is int ? a : (a is num ? a.toInt() : int.tryParse('$a'));
      if (ih != null && ia != null) return (ih, ia);
    }
    final ft = fx['score']?['fulltime'];
    if (ft is Map) {
      final h = ft['home'];
      final a = ft['away'];
      final ih = h is int ? h : (h is num ? h.toInt() : int.tryParse('$h'));
      final ia = a is int ? a : (a is num ? a.toInt() : int.tryParse('$a'));
      if (ih != null && ia != null) return (ih, ia);
    }
    return (null, null);
  }

  static int? _toIntId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  int? _teamIdFrom(Map<String, dynamic> m, String side) {
    final teams = m['teams'];
    if (teams is! Map) return null;
    final sideMap = teams[side];
    if (sideMap is! Map) return null;
    return _toIntId(sideMap['id']);
  }

  Future<List<Map<String, dynamic>>> _fetchFtFixturesTeam(int teamId, int season) async {
    final acc = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final uri = Uri.parse(
        '$_baseUrl/fixtures?team=$teamId&league=$_ligaProfesionalArgentina&season=$season&status=FT&timezone=America/Argentina/Buenos_Aires${page > 1 ? '&page=$page' : ''}',
      );
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) break;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) break;
      if (_apiErrorsPresent(decoded)) break;
      final list = decoded['response'] as List? ?? [];
      for (final f in list) {
        if (f is Map<String, dynamic>) acc.add(f);
      }
      final paging = decoded['paging'];
      final totalPages = paging is Map ? (paging['total'] as num?)?.toInt() ?? 1 : 1;
      if (page >= totalPages || list.isEmpty) break;
      page++;
    }
    acc.sort((a, b) {
      final da = DateTime.tryParse(a['fixture']?['date'] as String? ?? '') ?? DateTime(1970);
      final db = DateTime.tryParse(b['fixture']?['date'] as String? ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });
    if (acc.length > _maxPartidos) {
      return acc.sublist(0, _maxPartidos);
    }
    return acc;
  }

  /// Últimos partidos FT del equipo en [anchorSeason] y en la temporada anterior (misma API),
  /// deduplicados por fixture y ordenados del más reciente al más viejo (tope [_maxPartidos]).
  /// Así hay muestra útil aunque en la temporada actual aún haya pocos partidos.
  Future<List<Map<String, dynamic>>> _fetchFtFixturesMerged(int teamId, int anchorSeason) async {
    final prev = anchorSeason - 1;
    final a = await _fetchFtFixturesTeam(teamId, anchorSeason);
    final b = await _fetchFtFixturesTeam(teamId, prev);
    final byId = <int, Map<String, dynamic>>{};
    void take(Map<String, dynamic> f) {
      final idRaw = f['fixture']?['id'];
      final id = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw') ?? 0);
      if (id > 0) byId[id] = f;
    }
    for (final f in b) {
      take(f);
    }
    for (final f in a) {
      take(f);
    }
    final merged = byId.values.toList();
    merged.sort((x, y) {
      final dx = DateTime.tryParse(x['fixture']?['date'] as String? ?? '') ?? DateTime(1970);
      final dy = DateTime.tryParse(y['fixture']?['date'] as String? ?? '') ?? DateTime(1970);
      return dy.compareTo(dx);
    });
    if (merged.length > _maxPartidos) {
      return merged.sublist(0, _maxPartidos);
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _fetchEvents(int fixtureId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 350));
        final res = await http.get(
          Uri.parse('$_baseUrl/fixtures/events?fixture=$fixtureId'),
          headers: _headers,
        );
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic>) continue;
        if (_apiErrorsPresent(decoded)) continue;
        final raw = decoded['response'] as List? ?? [];
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  /// Primer gol del partido (cronológico), ignorando autogoles para definir quién abrió el marcador.
  Map<String, dynamic>? _primerGolNoAutogol(List<Map<String, dynamic>> events, Map<String, dynamic> partidoRoot) {
    final statusShort = PenalesShootoutHelper.statusShortDesdePartido(partidoRoot);
    final sorted = List<Map<String, dynamic>>.from(events)..sort(_compareEvents);
    for (final e in sorted) {
      if (!_isGoalEvent(e)) continue;
      if (PenalesShootoutHelper.esEventoTandaPenales(e, statusShort, partidoRoot)) continue;
      final det = (e['detail'] ?? '').toString();
      if (det == 'Own Goal') continue;
      return e;
    }
    return null;
  }

  int? _goalTeamId(Map<String, dynamic> e) {
    final team = e['team'];
    if (team is! Map) return null;
    return _toIntId(team['id']);
  }

  bool _mismoEventoGol(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (_eventMinute(a) != _eventMinute(b)) return false;
    if (_goalTeamId(a) != _goalTeamId(b)) return false;
    final pa = a['player'];
    final pb = b['player'];
    if (pa is Map && pb is Map) {
      final ia = pa['id'];
      final ib = pb['id'];
      if (ia != null && ib != null) return ia == ib;
    }
    return (a['detail'] ?? '').toString() == (b['detail'] ?? '').toString();
  }

  /// Primer gol del [teamId] después del gol inicial rival (mismo minuto: orden en la lista).
  int? _minutoPrimerGolRemontada(
    List<Map<String, dynamic>> events,
    int teamId,
    Map<String, dynamic> primerGolRival,
    Map<String, dynamic> partidoRoot,
  ) {
    final statusShort = PenalesShootoutHelper.statusShortDesdePartido(partidoRoot);
    final sorted = List<Map<String, dynamic>>.from(events)..sort(_compareEvents);
    var start = -1;
    for (var i = 0; i < sorted.length; i++) {
      if (identical(sorted[i], primerGolRival) || _mismoEventoGol(sorted[i], primerGolRival)) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;
    for (var i = start + 1; i < sorted.length; i++) {
      final e = sorted[i];
      if (!_isGoalEvent(e)) continue;
      if (PenalesShootoutHelper.esEventoTandaPenales(e, statusShort, partidoRoot)) continue;
      final det = (e['detail'] ?? '').toString();
      if (det == 'Own Goal') continue;
      final gt = _goalTeamId(e);
      if (gt == teamId) return _eventMinute(e);
    }
    return null;
  }

  Future<RemontadaStats> getRemontadaStats(int teamId, int season) async {
    if (teamId <= 0 || season <= 0) return RemontadaStats.empty();
    final k = _key(teamId, season);
    final hit = _cache[k];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return hit.stats;
    }

    try {
      final fixtures = await _fetchFtFixturesMerged(teamId, season);
      if (fixtures.isEmpty) {
        final empty = RemontadaStats.empty();
        _cache[k] = (stats: empty, at: DateTime.now());
        return empty;
      }

      final results = <_PartidoRemontada?>[];
      var sinListaEventos = 0;
      for (var i = 0; i < fixtures.length; i += _eventConcurrency) {
        final chunk = fixtures.skip(i).take(_eventConcurrency).toList();
        final partial = await Future.wait(chunk.map((fx) async {
          final fid = _toIntId(fx['fixture']?['id']) ?? 0;
          if (fid <= 0) return null;
          final homeId = _teamIdFrom(fx, 'home');
          final awayId = _teamIdFrom(fx, 'away');
          if (homeId == null || awayId == null) return null;
          final events = await _fetchEvents(fid);
          if (events.isEmpty) {
            sinListaEventos++;
            return null;
          }
          final primer = _primerGolNoAutogol(events, fx);
          if (primer == null) return null;
          final gTeam = _goalTeamId(primer);
          if (gTeam == null || gTeam == teamId) return null;

          final (gh0, ga0) = _golesMarcadorFinal(fx);
          final gh = gh0;
          final ga = ga0;
          if (gh == null || ga == null) return null;

          final esLocal = teamId == homeId;
          final gano = esLocal ? gh > ga : ga > gh;
          final empato = gh == ga;
          int? minRem;
          if (gano) {
            minRem = _minutoPrimerGolRemontada(events, teamId, primer, fx);
          } else if (empato) {
            minRem = _minutoPrimerGolRemontada(events, teamId, primer, fx);
          }

          return _PartidoRemontada(
            esLocal: esLocal,
            gano: gano,
            empato: empato,
            minutoRemontada: minRem,
          );
        }));
        results.addAll(partial);
      }

      var abajo = 0, gano = 0, empate = 0, perdio = 0;
      var localGano = 0, localAbajo = 0, visitGano = 0, visitAbajo = 0;
      final minutos = <int>[];
      for (final r in results) {
        if (r == null) continue;
        abajo++;
        if (r.gano) {
          gano++;
          if (r.minutoRemontada != null) minutos.add(r.minutoRemontada!);
          if (r.esLocal) {
            localGano++;
            localAbajo++;
          } else {
            visitGano++;
            visitAbajo++;
          }
        } else if (r.empato) {
          empate++;
          if (r.esLocal) {
            localAbajo++;
          } else {
            visitAbajo++;
          }
        } else {
          perdio++;
          if (r.esLocal) {
            localAbajo++;
          } else {
            visitAbajo++;
          }
        }
      }

      /// Muchos FT sin lista de eventos + ningún partido contado → suele ser rate limit; no cachear.
      final fracSinEventos = fixtures.isEmpty ? 0.0 : sinListaEventos / fixtures.length;
      if (fixtures.length >= 5 && abajo == 0 && fracSinEventos >= 0.35) {
        debugPrint(
          'RemontadaService: team $teamId — sin muestra útil (eventos vacíos $sinListaEventos/${fixtures.length}), no cacheo.',
        );
        return RemontadaStats.empty();
      }
      double pct(int n) => abajo > 0 ? (n * 100.0 / abajo) : 0.0;
      double pctLocalRem() => localAbajo > 0 ? (localGano * 100.0 / localAbajo) : 0.0;
      double pctVisitRem() => visitAbajo > 0 ? (visitGano * 100.0 / visitAbajo) : 0.0;
      double minProm = 0;
      if (minutos.isNotEmpty) {
        minProm = minutos.reduce((a, b) => a + b) / minutos.length;
      }

      final stats = RemontadaStats(
        totalPartidosAbajo: abajo,
        porcentajeRemontada: double.parse(pct(gano).toStringAsFixed(1)),
        porcentajeEmpate: double.parse(pct(empate).toStringAsFixed(1)),
        porcentajeDerrota: double.parse(pct(perdio).toStringAsFixed(1)),
        porcentajeLocalRemontada: double.parse(pctLocalRem().toStringAsFixed(1)),
        porcentajeVisitanteRemontada: double.parse(pctVisitRem().toStringAsFixed(1)),
        minutoPromedioRemontada: double.parse(minProm.toStringAsFixed(1)),
      );
      _cache[k] = (stats: stats, at: DateTime.now());
      return stats;
    } catch (_) {
      return RemontadaStats.empty();
    }
  }
}

class _PartidoRemontada {
  const _PartidoRemontada({
    required this.esLocal,
    required this.gano,
    required this.empato,
    this.minutoRemontada,
  });

  final bool esLocal;
  final bool gano;
  final bool empato;
  final int? minutoRemontada;
}
