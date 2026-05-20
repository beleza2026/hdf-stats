import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fila del ranking de posesión promedio — Mundial 2026.
class PosesionMundialEquipo {
  const PosesionMundialEquipo({
    required this.teamId,
    required this.nombre,
    required this.logo,
    required this.country,
    required this.promedioPosesion,
    required this.partidos,
    required this.goles,
    required this.diferenciaGoles,
  });

  final int teamId;
  final String nombre;
  final String logo;
  final String country;
  final double promedioPosesion;
  final int partidos;
  final int goles;
  final int diferenciaGoles;
}

class PosesionMundialService {
  PosesionMundialService._();

  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _leagueId = 1;
  static const int _season = 2026;
  static const Duration cacheTtl = Duration(hours: 3);

  static final Map<String, String> _headers = {'x-apisports-key': _apiKey};

  static List<PosesionMundialEquipo>? _cache;
  static DateTime? _cacheAt;

  static void clearCache() {
    _cache = null;
    _cacheAt = null;
  }

  static double? _parseBallPossession(Map<String, dynamic> block) {
    final stats = block['statistics'] as List? ?? [];
    for (final s in stats) {
      if (s is! Map) continue;
      if (s['type'] == 'Ball Possession') {
        final v = s['value']?.toString().replaceAll('%', '').trim() ?? '';
        return double.tryParse(v);
      }
    }
    return null;
  }

  /// Ranking de posesión (solo equipos con al menos un % registrado).
  static Future<List<PosesionMundialEquipo>> getRanking({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < cacheTtl) {
      return List<PosesionMundialEquipo>.from(_cache!);
    }

    try {
      final resFix = await http.get(
        Uri.parse(
          '$_baseUrl/fixtures?league=$_leagueId&season=$_season&status=FT&timezone=America/Argentina/Buenos_Aires',
        ),
        headers: _headers,
      );
      if (resFix.statusCode != 200) return _cache ?? [];

      final body = jsonDecode(resFix.body);
      final jugados = (body['response'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final acum = <int, Map<String, dynamic>>{};

      void ensureTeam(int tid, String nombre, String logo, String country) {
        acum.putIfAbsent(
          tid,
          () => {
            'nombre': nombre,
            'logo': logo,
            'country': country,
            'posSum': 0.0,
            'posN': 0,
            'pj': 0,
            'gf': 0,
            'gc': 0,
          },
        );
        acum[tid]!['nombre'] = nombre;
        acum[tid]!['logo'] = logo;
        acum[tid]!['country'] = country;
      }

      for (final f in jugados) {
        final teams = f['teams'] as Map? ?? {};
        final home = teams['home'] as Map? ?? {};
        final away = teams['away'] as Map? ?? {};
        final goals = f['goals'] as Map? ?? {};
        final homeId = (home['id'] as num?)?.toInt();
        final awayId = (away['id'] as num?)?.toInt();
        if (homeId == null || awayId == null) continue;

        final homeName = home['name'] as String? ?? '';
        final awayName = away['name'] as String? ?? '';
        final homeLogo = home['logo'] as String? ?? '';
        final awayLogo = away['logo'] as String? ?? '';
        final homeCountry = home['country'] as String? ?? homeName;
        final awayCountry = away['country'] as String? ?? awayName;
        final gh = (goals['home'] as num?)?.toInt() ?? 0;
        final ga = (goals['away'] as num?)?.toInt() ?? 0;

        ensureTeam(homeId, homeName, homeLogo, homeCountry);
        ensureTeam(awayId, awayName, awayLogo, awayCountry);
        acum[homeId]!['pj'] = (acum[homeId]!['pj'] as int) + 1;
        acum[awayId]!['pj'] = (acum[awayId]!['pj'] as int) + 1;
        acum[homeId]!['gf'] = (acum[homeId]!['gf'] as int) + gh;
        acum[homeId]!['gc'] = (acum[homeId]!['gc'] as int) + ga;
        acum[awayId]!['gf'] = (acum[awayId]!['gf'] as int) + ga;
        acum[awayId]!['gc'] = (acum[awayId]!['gc'] as int) + gh;
      }

      const loteSize = 8;
      for (var i = 0; i < jugados.length; i += loteSize) {
        final lote = jugados.skip(i).take(loteSize).toList();
        await Future.wait(lote.map((f) async {
          final fxId = (f['fixture']?['id'] as num?)?.toInt();
          if (fxId == null) return;
          try {
            final res = await http.get(
              Uri.parse('$_baseUrl/fixtures/statistics?fixture=$fxId'),
              headers: _headers,
            );
            if (res.statusCode != 200) return;
            final blocks = (jsonDecode(res.body)['response'] as List? ?? [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            for (final block in blocks) {
              final team = block['team'] as Map? ?? {};
              final tid = (team['id'] as num?)?.toInt();
              if (tid == null) continue;
              final pct = _parseBallPossession(block);
              if (pct == null) continue;
              if (!acum.containsKey(tid)) {
                ensureTeam(
                  tid,
                  team['name'] as String? ?? '',
                  team['logo'] as String? ?? '',
                  team['country'] as String? ?? '',
                );
              }
              acum[tid]!['posSum'] = (acum[tid]!['posSum'] as double) + pct;
              acum[tid]!['posN'] = (acum[tid]!['posN'] as int) + 1;
            }
          } catch (_) {}
        }));
        if (i + loteSize < jugados.length) {
          await Future.delayed(const Duration(milliseconds: 220));
        }
      }

      final rows = <PosesionMundialEquipo>[];
      for (final e in acum.entries) {
        final posN = e.value['posN'] as int;
        if (posN == 0) continue;
        final prom = (e.value['posSum'] as double) / posN;
        final gf = e.value['gf'] as int;
        final gc = e.value['gc'] as int;
        rows.add(
          PosesionMundialEquipo(
            teamId: e.key,
            nombre: e.value['nombre'] as String,
            logo: e.value['logo'] as String,
            country: e.value['country'] as String,
            promedioPosesion: double.parse(prom.toStringAsFixed(1)),
            partidos: e.value['pj'] as int,
            goles: gf,
            diferenciaGoles: gf - gc,
          ),
        );
      }
      rows.sort((a, b) => b.promedioPosesion.compareTo(a.promedioPosesion));

      _cache = rows;
      _cacheAt = now;
      return rows;
    } catch (_) {
      return _cache ?? [];
    }
  }
}
