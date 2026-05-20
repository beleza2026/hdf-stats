import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../mundial_service.dart';

/// Partido del Mundial con predicción HDF™ calculada.
class PrediccionMundialItem {
  const PrediccionMundialItem({
    required this.fixtureId,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeCountry,
    required this.awayCountry,
    required this.grupoLabel,
    required this.kickoff,
    required this.statusShort,
    required this.isLive,
    required this.isFinished,
    required this.pctLocal,
    required this.pctEmpate,
    required this.pctVisitante,
    required this.predichoKey,
    this.goalsHome,
    this.goalsAway,
    required this.partidoRaw,
  });

  final int fixtureId;
  final int homeId;
  final int awayId;
  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final String homeCountry;
  final String awayCountry;
  final String grupoLabel;
  final DateTime kickoff;
  final String statusShort;
  final bool isLive;
  final bool isFinished;
  final int pctLocal;
  final int pctEmpate;
  final int pctVisitante;
  /// `local` | `empate` | `visitante`
  final String predichoKey;
  final int? goalsHome;
  final int? goalsAway;
  final Map<String, dynamic> partidoRaw;

  String? get resultadoRealKey {
    if (!isFinished || goalsHome == null || goalsAway == null) return null;
    if (goalsHome! > goalsAway!) return 'local';
    if (goalsHome! < goalsAway!) return 'visitante';
    return 'empate';
  }

  bool? get prediccionAcertada {
    final real = resultadoRealKey;
    if (real == null) return null;
    return real == predichoKey;
  }
}

class PrediccionesMundialService {
  PrediccionesMundialService._();

  static const int leagueId = 1;
  static const int season = 2026;
  static const Duration fixturesTtl = Duration(hours: 1);
  static const Duration prediccionesTtl = Duration(hours: 6);

  static List<Map<String, dynamic>>? _fixturesCache;
  static DateTime? _fixturesCacheAt;
  static List<PrediccionMundialItem>? _prediccionesCache;
  static DateTime? _prediccionesCacheAt;
  static String? _prediccionesCacheKey;

  static void clearCache() {
    _fixturesCache = null;
    _fixturesCacheAt = null;
    _prediccionesCache = null;
    _prediccionesCacheAt = null;
    _prediccionesCacheKey = null;
  }

  static Future<List<PrediccionMundialItem>> getPrediccionesVentana48h() async {
    final now = DateTime.now();
    final ventanaKey =
        '${now.year}-${now.month}-${now.day}-${now.hour ~/ 6}';
    if (_prediccionesCache != null &&
        _prediccionesCacheAt != null &&
        _prediccionesCacheKey == ventanaKey &&
        now.difference(_prediccionesCacheAt!) < prediccionesTtl) {
      return List<PrediccionMundialItem>.from(_prediccionesCache!);
    }

    final fixtures = await _fixturesEnVentana48h();
    final out = <PrediccionMundialItem>[];
    for (final p in fixtures) {
      try {
        out.add(await _calcular(p));
      } catch (e) {
        debugPrint('Predicción mundial $e');
      }
    }
    out.sort((a, b) => a.kickoff.compareTo(b.kickoff));

    _prediccionesCache = out;
    _prediccionesCacheAt = now;
    _prediccionesCacheKey = ventanaKey;
    return out;
  }

  static Future<List<Map<String, dynamic>>> _fixturesEnVentana48h() async {
    final now = DateTime.now();
    if (_fixturesCache != null &&
        _fixturesCacheAt != null &&
        now.difference(_fixturesCacheAt!) < fixturesTtl) {
      return List<Map<String, dynamic>>.from(_fixturesCache!);
    }

    final todos = await MundialService.getFixture();
    final desde = now.subtract(const Duration(hours: 48));
    final hasta = now.add(const Duration(hours: 48));

    final filtrados = <Map<String, dynamic>>[];
    for (final p in todos) {
      final fixture = p['fixture'];
      if (fixture is! Map) continue;
      final dt = _kickoffLocal(Map<String, dynamic>.from(fixture));
      if (dt == null) continue;
      if (dt.isBefore(desde) || dt.isAfter(hasta)) continue;
      filtrados.add(p);
    }

    _fixturesCache = filtrados;
    _fixturesCacheAt = now;
    return filtrados;
  }

  static DateTime? _kickoffLocal(Map<String, dynamic> fixture) {
    final ds = fixture['date'] as String?;
    if (ds != null && ds.isNotEmpty) {
      return DateTime.tryParse(ds)?.toLocal();
    }
    final ts = fixture['timestamp'];
    if (ts is int && ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
    }
    if (ts is num && ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000, isUtc: true).toLocal();
    }
    return null;
  }

  static String _grupoLabel(Map<String, dynamic> partido) {
    final round = partido['league']?['round']?.toString() ?? '';
    final m = RegExp(r'group\s*([a-l])', caseSensitive: false).firstMatch(round);
    if (m != null) return 'GRUPO ${m.group(1)!.toUpperCase()}';
    if (round.toLowerCase().contains('round of 16')) return 'OCTAVOS';
    if (round.toLowerCase().contains('quarter')) return 'CUARTOS';
    if (round.toLowerCase().contains('semi')) return 'SEMIFINAL';
    if (round.toLowerCase().contains('final')) return 'FINAL';
    return round.isNotEmpty ? round.toUpperCase() : 'MUNDIAL';
  }

  static Future<({double winRate, double goalAvg})> _metricasEquipo(int teamId) async {
    final stats = await ApiService.getStatsEquipoTorneo(teamId, leagueId, season);
    final played = (stats['fixtures']?['played']?['total'] as num?)?.toInt() ?? 0;
    if (played >= 3) {
      final wins = (stats['fixtures']?['wins']?['total'] as num?)?.toDouble() ?? 0;
      final gf = (stats['goals']?['for']?['total']?['total'] as num?)?.toDouble() ?? 0;
      return (winRate: wins / played, goalAvg: gf / played);
    }

    final ult = await ApiService.getUltimos5(teamId);
    var wins = 0, gf = 0, n = 0;
    for (final f in ult) {
      final st = f['fixture']?['status']?['short']?.toString() ?? '';
      if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
      final esHome = (f['teams']?['home']?['id'] as num?)?.toInt() == teamId;
      final hg = (f['goals']?['home'] as num?)?.toInt() ?? 0;
      final ag = (f['goals']?['away'] as num?)?.toInt() ?? 0;
      if (esHome) {
        gf += hg;
        if (hg > ag) wins++;
      } else {
        gf += ag;
        if (ag > hg) wins++;
      }
      n++;
      if (n >= 5) break;
    }
    if (n == 0) return (winRate: 0.33, goalAvg: 1.0);
    return (winRate: wins / n, goalAvg: gf / n);
  }

  static Future<({double home, double away, double draw})> _h2hRates(int homeId, int awayId) async {
    final h2h = await ApiService.getHeadToHead(homeId, awayId);
    var winsHome = 0, winsAway = 0, draws = 0, total = 0;
    for (final f in h2h.take(10)) {
      final st = f['fixture']?['status']?['short']?.toString() ?? '';
      if (st != 'FT' && st != 'AET' && st != 'PEN') continue;
      final fHomeId = (f['teams']?['home']?['id'] as num?)?.toInt() ?? 0;
      final hg = (f['goals']?['home'] as num?)?.toInt() ?? 0;
      final ag = (f['goals']?['away'] as num?)?.toInt() ?? 0;
      if (fHomeId == homeId) {
        if (hg > ag) {
          winsHome++;
        } else if (hg == ag) {
          draws++;
        } else {
          winsAway++;
        }
      } else {
        if (ag > hg) {
          winsHome++;
        } else if (hg == ag) {
          draws++;
        } else {
          winsAway++;
        }
      }
      total++;
    }
    if (total == 0) return (home: 0.35, away: 0.35, draw: 0.30);
    return (
      home: winsHome / total,
      away: winsAway / total,
      draw: draws / total,
    );
  }

  static ({int local, int empate, int visitante, String predicho}) _normalizarPct(
    double scoreA,
    double scoreB,
    double scoreEmpate,
  ) {
    final total = scoreA + scoreB + scoreEmpate;
    if (total <= 0) {
      return (local: 34, empate: 33, visitante: 33, predicho: 'local');
    }
    var pA = (scoreA / total * 100).round();
    var pE = (scoreEmpate / total * 100).round();
    var pB = (scoreB / total * 100).round();
    var sum = pA + pE + pB;
    final residuo = 100 - sum;
    if (residuo != 0) {
      if (pA >= pE && pA >= pB) {
        pA += residuo;
      } else if (pB >= pA && pB >= pE) {
        pB += residuo;
      } else {
        pE += residuo;
      }
    }
    String predicho = 'local';
    if (pB > pA && pB >= pE) {
      predicho = 'visitante';
    } else if (pE > pA && pE > pB) {
      predicho = 'empate';
    }
    return (local: pA, empate: pE, visitante: pB, predicho: predicho);
  }

  static Future<PrediccionMundialItem> _calcular(Map<String, dynamic> partido) async {
    final fixture = Map<String, dynamic>.from(partido['fixture'] as Map? ?? {});
    final teams = partido['teams'] as Map? ?? {};
    final home = Map<String, dynamic>.from(teams['home'] as Map? ?? {});
    final away = Map<String, dynamic>.from(teams['away'] as Map? ?? {});
    final goals = partido['goals'] as Map? ?? {};

    final fixtureId = (fixture['id'] as num?)?.toInt() ?? 0;
    final homeId = (home['id'] as num?)?.toInt() ?? 0;
    final awayId = (away['id'] as num?)?.toInt() ?? 0;
    final homeName = home['name'] as String? ?? 'Local';
    final awayName = away['name'] as String? ?? 'Visitante';
    final kickoff = _kickoffLocal(fixture) ?? DateTime.now();
    final status = fixture['status']?['short']?.toString() ?? 'NS';
    final isLive = const {'1H', '2H', 'HT', 'ET', 'P', 'BT', 'LIVE'}.contains(status);
    final isFinished = const {'FT', 'AET', 'PEN'}.contains(status);

    final results = await Future.wait([
      _metricasEquipo(homeId),
      _metricasEquipo(awayId),
      _h2hRates(homeId, awayId),
    ]);
    final metA = results[0] as ({double winRate, double goalAvg});
    final metB = results[1] as ({double winRate, double goalAvg});
    final h2h = results[2] as ({double home, double away, double draw});

    final goalNormA = (metA.goalAvg / 3.0).clamp(0.0, 1.0);
    final goalNormB = (metB.goalAvg / 3.0).clamp(0.0, 1.0);

    var scoreA = metA.winRate * 0.5 + goalNormA * 0.3 + h2h.home * 0.2;
    var scoreB = metB.winRate * 0.5 + goalNormB * 0.3 + h2h.away * 0.2;
    var scoreEmpate = 1 - (scoreA + scoreB).clamp(0.0, 1.0) * 0.6;
    if (scoreEmpate < 0.08) scoreEmpate = 0.08;
    scoreA += 0.03;

    final pct = _normalizarPct(scoreA, scoreB, scoreEmpate);

    return PrediccionMundialItem(
      fixtureId: fixtureId,
      homeId: homeId,
      awayId: awayId,
      homeName: homeName,
      awayName: awayName,
      homeLogo: home['logo'] as String?,
      awayLogo: away['logo'] as String?,
      homeCountry: home['country'] as String? ?? homeName,
      awayCountry: away['country'] as String? ?? awayName,
      grupoLabel: _grupoLabel(partido),
      kickoff: kickoff,
      statusShort: status,
      isLive: isLive,
      isFinished: isFinished,
      pctLocal: pct.local,
      pctEmpate: pct.empate,
      pctVisitante: pct.visitante,
      predichoKey: pct.predicho,
      goalsHome: (goals['home'] as num?)?.toInt(),
      goalsAway: (goals['away'] as num?)?.toInt(),
      partidoRaw: partido,
    );
  }
}
