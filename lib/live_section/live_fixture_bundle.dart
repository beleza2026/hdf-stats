import 'package:flutter/material.dart';

import '../api_service.dart';

/// Respuesta agregada de eventos, estadísticas, alineaciones, jugadores y detalle de fixture.
class LiveFixtureBundle {
  LiveFixtureBundle({
    required this.events,
    required this.lineups,
    required this.players,
    this.statisticsRaw,
    this.detalle,
    this.fetchedAt,
  });

  final Map<String, dynamic>? statisticsRaw;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> lineups;
  final List<Map<String, dynamic>> players;
  final Map<String, dynamic>? detalle;
  final DateTime? fetchedAt;

  /// Mapas `type` → `value` por bando (índice 0 = local API, 1 = visitante).
  static Map<String, Map<String, dynamic>> statMapsFromResponse(Map<String, dynamic>? stats) {
    final home = <String, dynamic>{};
    final away = <String, dynamic>{};
    if (stats == null) return {'home': home, 'away': away};
    final resp = stats['response'];
    if (resp is! List || resp.length < 2) return {'home': home, 'away': away};
    for (final s in (resp[0]['statistics'] as List?) ?? []) {
      if (s is Map<String, dynamic>) home[s['type'] as String? ?? ''] = s['value'];
    }
    for (final s in (resp[1]['statistics'] as List?) ?? []) {
      if (s is Map<String, dynamic>) away[s['type'] as String? ?? ''] = s['value'];
    }
    return {'home': home, 'away': away};
  }

  static Future<LiveFixtureBundle> fetch(int fixtureId) async {
    final results = await Future.wait<dynamic>([
      ApiService.getEstadisticasPartido(fixtureId),
      ApiService.getEventosPartido(fixtureId),
      ApiService.getLineupsPartido(fixtureId),
      ApiService.getPlayersPartido(fixtureId.toString()),
      ApiService.getDetallePartido(fixtureId),
    ]);
    return LiveFixtureBundle(
      statisticsRaw: results[0] as Map<String, dynamic>?,
      events: List<Map<String, dynamic>>.from(results[1] as List? ?? []),
      lineups: List<Map<String, dynamic>>.from(results[2] as List? ?? []),
      players: List<Map<String, dynamic>>.from(results[3] as List? ?? []),
      detalle: results[4] as Map<String, dynamic>?,
      fetchedAt: DateTime.now(),
    );
  }
}

Color? parseApiHexColor(dynamic raw) {
  if (raw == null) return null;
  var s = raw.toString().trim();
  if (s.isEmpty) return null;
  if (!s.startsWith('#')) s = '#$s';
  try {
    var hex = s.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    return Color(int.parse(hex, radix: 16));
  } catch (_) {
    return null;
  }
}

Color? teamPrimaryColor(Map<String, dynamic>? team) {
  if (team == null) return null;
  final colors = team['colors'];
  if (colors is! Map<String, dynamic>) return null;
  final player = colors['player'];
  if (player is Map<String, dynamic>) {
    final c = parseApiHexColor(player['primary']);
    if (c != null) return c;
  }
  return null;
}

String liveCleanPlayerName(String name) {
  return String.fromCharCodes(name.runes.where((r) => r <= 0xFFFF)).trim();
}

int? fixtureIdFromPartido(Map<String, dynamic> partido) {
  final id = partido['fixture']?['id'];
  if (id is int) return id;
  if (id is num) return id.toInt();
  return int.tryParse('$id');
}

Map<String, dynamic> mergedPartidoSnapshot(Map<String, dynamic> lista, Map<String, dynamic>? detalle) {
  if (detalle == null) return Map<String, dynamic>.from(lista);
  final out = Map<String, dynamic>.from(lista);
  out['goals'] = detalle['goals'] ?? out['goals'];
  out['score'] = detalle['score'] ?? out['score'];
  out['teams'] = detalle['teams'] ?? out['teams'];
  out['fixture'] = detalle['fixture'] ?? out['fixture'];
  return out;
}

/// Texto corto del estado del partido en español.
String estadoPartidoCortoEs(String short) {
  switch (short) {
    case '1H':
      return '1.er tiempo';
    case '2H':
      return '2.do tiempo';
    case 'HT':
      return 'Entretiempo';
    case 'ET':
      return 'Prórroga';
    case 'BT':
      return 'Descanso (prór.)';
    case 'PEN':
      return 'Penales';
    case 'INT':
      return 'Interrumpido';
    case 'LIVE':
      return 'En juego';
    case 'FT':
      return 'Finalizado';
    default:
      return short.isEmpty ? '—' : short;
  }
}

/// Avance 0–1 del reloj de partido para la barra.
double progresoPartido(String short, int elapsed) {
  switch (short) {
    case '1H':
      return (elapsed / 45).clamp(0.0, 1.0);
    case 'HT':
      return 0.5;
    case '2H':
      return (elapsed / 95).clamp(0.0, 1.0);
    case 'ET':
    case 'BT':
      return (elapsed / 120).clamp(0.0, 1.0);
    case 'PEN':
      return 1.0;
    default:
      if (elapsed <= 0) return 0.08;
      return (elapsed / 95).clamp(0.0, 1.0);
  }
}

Map<String, int?> golesPorPeriodoDesdeScore(Map<String, dynamic>? score) {
  int? h(Map? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  if (score is! Map<String, dynamic>) {
    return {'1tL': null, '1tV': null, '2tL': null, '2tV': null, 'etL': null, 'etV': null, 'penL': null, 'penV': null};
  }
  final ht = score['halftime'] as Map?;
  final ft = score['fulltime'] as Map?;
  final et = score['extratime'] as Map?;
  final pen = score['penalty'] as Map?;
  return {
    '1tL': h(ht, 'home'),
    '1tV': h(ht, 'away'),
    '2tL': h(ft, 'home'),
    '2tV': h(ft, 'away'),
    'etL': h(et, 'home'),
    'etV': h(et, 'away'),
    'penL': h(pen, 'home'),
    'penV': h(pen, 'away'),
  };
}

Map<int, double> ratingsPorJugadorId(List<Map<String, dynamic>> players) {
  final m = <int, double>{};
  for (final p in players) {
    final id = p['id'];
    final pid = id is int ? id : (id is num ? id.toInt() : int.tryParse('$id') ?? 0);
    if (pid <= 0) continue;
    if (p['tieneRating'] == true) {
      final r = p['rating'];
      if (r is double) m[pid] = r;
      if (r is num) m[pid] = r.toDouble();
    }
  }
  return m;
}
