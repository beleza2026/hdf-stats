import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// --- Modelos públicos (bloque mercado) ------------------------------------

/// Estado del contrato respecto a la fecha de fin (badge de color en UI).
enum SportmonksContractStatus {
  unknown,
  expired,
  expiresUnderSixMonths,
  expiresUnderTwelveMonths,
  ok,
}

extension SportmonksContractStatusUi on SportmonksContractStatus {
  Color get badgeColor {
    switch (this) {
      case SportmonksContractStatus.expired:
      case SportmonksContractStatus.expiresUnderSixMonths:
        return const Color(0xFFFF5252);
      case SportmonksContractStatus.expiresUnderTwelveMonths:
        return const Color(0xFFFFCA28);
      case SportmonksContractStatus.ok:
        return const Color(0xFF00C853);
      case SportmonksContractStatus.unknown:
        return Colors.white38;
    }
  }

  String get badgeShortLabel {
    switch (this) {
      case SportmonksContractStatus.expired:
        return 'Vencido';
      case SportmonksContractStatus.expiresUnderSixMonths:
        return '<6m';
      case SportmonksContractStatus.expiresUnderTwelveMonths:
        return '6–12m';
      case SportmonksContractStatus.ok:
        return '>12m';
      case SportmonksContractStatus.unknown:
        return '—';
    }
  }
}

/// Promedio de edad y valor total de plantel (Sportmonks `squads/teams` + `include=player`).
class SportmonksSquadInfo {
  const SportmonksSquadInfo({
    this.averageAge,
    this.totalMarketValueEuros,
  });

  final double? averageAge;
  final num? totalMarketValueEuros;

  bool get hasAnyData =>
      averageAge != null || (totalMarketValueEuros != null && totalMarketValueEuros! > 0);
}

/// Una línea de transferencia para listados compactos.
class SportmonksTransferLine {
  const SportmonksTransferLine({
    required this.year,
    required this.fromClub,
    required this.toClub,
    required this.amountFormatted,
  });

  final int? year;
  final String fromClub;
  final String toClub;
  /// Texto ya formateado (ej. monto o "—").
  final String amountFormatted;
}

/// Datos de mercado del **primer** jugador devuelto por la búsqueda Sportmonks.
class SportmonksPlayerMarketData {
  const SportmonksPlayerMarketData({
    required this.sportmonksPlayerId,
    required this.displayName,
    this.marketValue,
    required this.marketValueFormatted,
    this.contractUntil,
    required this.contractUntilFormatted,
    required this.contractStatus,
    required this.transfers,
  });

  final String sportmonksPlayerId;
  final String displayName;
  /// Si es `null`, la UI **no** muestra la fila de valor de mercado.
  final num? marketValue;
  final String marketValueFormatted;
  final DateTime? contractUntil;
  /// Ej. `Jun 2026` (inglés, mes corto).
  final String contractUntilFormatted;
  final SportmonksContractStatus contractStatus;
  /// Recientes primero; la UI de detalle usa la primera como «última transferencia».
  final List<SportmonksTransferLine> transfers;

  /// Hay al menos un dato para mostrar en la sección MERCADO (valor, contrato o transferencias).
  bool get hasMercadoContent =>
      marketValue != null || contractUntil != null || transfers.isNotEmpty;
}

/// Resultado de [SportmonksService.searchPlayerByName].
class SportmonksPlayerMarketSnapshot {
  const SportmonksPlayerMarketSnapshot({this.data, this.errorMessage});

  final SportmonksPlayerMarketData? data;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null && data != null;
}

/// Una fila de jugador lesionado (LPF) desde Sportmonks `sidelined` activo.
class SportmonksInjuryRow {
  const SportmonksInjuryRow({
    required this.playerName,
    required this.teamName,
    this.playerPhotoUrl,
    this.category,
    this.typeLabel,
    this.startDate,
    this.endDate,
    this.gamesMissed,
  });

  final String playerName;
  final String teamName;
  final String? playerPhotoUrl;
  final String? category;
  final String? typeLabel;
  final String? startDate;
  final String? endDate;
  final int? gamesMissed;
}

/// Datos de club desde Sportmonks (`teams/{id}?include=venue`).
class SportmonksClubProfile {
  const SportmonksClubProfile({
    this.sportmonksTeamId,
    this.name,
    this.logoUrl,
    this.venueName,
    this.venueImageUrl,
    this.venueCity,
    this.venueCapacity,
    this.foundedYear,
  });

  final int? sportmonksTeamId;
  final String? name;
  final String? logoUrl;
  final String? venueName;
  final String? venueImageUrl;
  final String? venueCity;
  final int? venueCapacity;
  final int? foundedYear;

  bool get hasVenueImage =>
      venueImageUrl != null && venueImageUrl!.trim().isNotEmpty;
}

/// Listado de lesionados LPF vía Sportmonks ([SportmonksService.getLigaProfesionalArgentinaInjuries]).
class SportmonksLpfInjuriesSnapshot {
  const SportmonksLpfInjuriesSnapshot({
    required this.rows,
    this.errorMessage,
    this.resolvedSeasonId,
  });

  final List<SportmonksInjuryRow> rows;
  final String? errorMessage;
  /// Temporada Sportmonks usada para `teams/seasons/{id}` (útil si forzás ID con dart-define).
  final int? resolvedSeasonId;

  bool get isSuccess => errorMessage == null;
}

/// Cliente [Sportmonks Football API v3](https://docs.sportmonks.com/v3/welcome/welcome).
///
/// Token: compilación con **una** de estas opciones:
/// - `--dart-define=SPORTMONKS_API_TOKEN=tu_token`
/// - `--dart-define-from-file=dart_defines.json` (copiá `dart_defines.example.json` → `dart_defines.json`; está en `.gitignore`)
///
/// Base opcional: `--dart-define=SPORTMONKS_API_BASE_URL=https://api.sportmonks.com/v3/football`
///
/// Lesionados LPF: opcional `--dart-define=SPORTMONKS_LPF_SEASON_ID=…` (ID de temporada en Sportmonks).
/// Si no se define, se intenta `leagues/search` + `currentSeason` para la liga en Argentina.
class SportmonksService {
  SportmonksService();

  static const String _defaultBase = 'https://api.sportmonks.com/v3/football';
  static const Duration _lpfInjuriesTtl = Duration(minutes: 12);

  static String _normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) s = _defaultBase;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static final String _baseUrl = _normalizeBase(const String.fromEnvironment(
    'SPORTMONKS_API_BASE_URL',
    defaultValue: _defaultBase,
  ));

  static String? _pickToken() {
    const t = String.fromEnvironment('SPORTMONKS_API_TOKEN', defaultValue: '');
    final s = t.trim();
    return s.isEmpty ? null : s;
  }

  static String get apiBaseUrlDisplay => _baseUrl;

  static const Duration _timeoutSearch = Duration(seconds: 45);
  /// Perfil con includes anidados suele tardar más que la búsqueda.
  static const Duration _timeoutProfile = Duration(seconds: 75);
  static const _jsonHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'HDFStats/1.0 (Flutter)',
  };

  static Map<String, String> _headersWithAuth(String token) => {
        ..._jsonHeaders,
        'Authorization': token.trim(),
      };

  static String _userFacingHttpError(int status) {
    switch (status) {
      case 401:
        return 'Sportmonks 401: token inválido o no enviado. Revisá dart_defines.json / dart-define y hacé un run completo (no solo hot reload).';
      case 403:
        return 'Sportmonks 403: tu plan no incluye este dato (jugador, contrato o transferencias).';
      case 429:
        return 'Sportmonks 429: límite de consultas por hora. Esperá unos minutos.';
      default:
        return 'Sportmonks HTTP $status';
    }
  }

  /// Respuesta tipo error de Sportmonks (`message` sin `data`).
  static bool _apiErrorsPresent(Map<String, dynamic>? root) {
    if (root == null) return true;
    if (root['message'] != null && root['data'] == null) return true;
    return false;
  }

  static final Map<String, dynamic> _cache = {};
  static final Map<String, SportmonksSquadInfo?> _squadInfoCache = {};
  static SportmonksLpfInjuriesSnapshot? _lpfInjuriesMem;
  static DateTime? _lpfInjuriesMemAt;
  /// API-Football team id (liga 128) → Sportmonks team id (LPF temporada actual).
  static Map<int, int>? _apiFootballToSportmonksTeam;

  static String _cacheKey(String kind, String id) => '$kind:${id.trim()}';

  static Map<String, dynamic> _snapshot(Map<String, dynamic> m) =>
      Map<String, dynamic>.from(m);

  static bool _isRetryableNetworkError(Object e) {
    final s = e.toString();
    return s.contains('connection abort') ||
        s.contains('Connection closed') ||
        s.contains('Connection reset') ||
        s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('HandshakeException') ||
        s.contains('Network is unreachable');
  }

  static Future<http.Response> _httpGet(Uri uri, {required String token, Duration? timeout}) async {
    final limit = timeout ?? _timeoutSearch;
    final headers = _headersWithAuth(token);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        var res = await http.get(uri, headers: headers).timeout(limit);
        if (res.statusCode == 401) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          res = await http.get(uri, headers: headers).timeout(limit);
        }
        return res;
      } on TimeoutException {
        if (attempt == 0) {
          await Future<void>.delayed(Duration(milliseconds: 800 + 400 * attempt));
          continue;
        }
        rethrow;
      } catch (e) {
        if (_isRetryableNetworkError(e) && attempt == 0) {
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw TimeoutException('GET $uri');
  }

  static dynamic _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k];
    }
    return null;
  }

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    return v.toString();
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static Map<String, dynamic>? _unwrapPlayer(dynamic data) {
    if (data == null) return null;
    if (data is List && data.isNotEmpty) {
      return _asMap(data.first);
    }
    return _asMap(data);
  }

  static String _eurosConPuntos(int euros) {
    final neg = euros < 0;
    final s = (neg ? -euros : euros).toString();
    if (s.length <= 3) return neg ? '-$s' : s;
    final lead = s.length % 3;
    final buf = StringBuffer();
    var i = 0;
    if (lead > 0) {
      buf.write(s.substring(0, lead));
      i = lead;
    }
    while (i < s.length) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3 > s.length ? s.length : i + 3));
      i += 3;
    }
    final r = buf.toString();
    return neg ? '-$r' : r;
  }

  static num? _asNumLoose(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return num.tryParse(s.replaceAll(RegExp(r'[^\d.\-]'), ''));
  }

  /// Valor de mercado en la fila de búsqueda / jugador (varía según plan Sportmonks).
  static num? _extractMarketValueRaw(Map<String, dynamic> picked) {
    final direct = _pick(picked, [
      'market_value',
      'market_value_in_eur',
      'value',
      'price',
      'worth',
    ]);
    var n = _asNumLoose(direct);
    if (n != null && n > 0) return n;
    final det = _asMap(picked['details']);
    if (det != null) {
      n = _asNumLoose(_pick(det, ['market_value', 'value', 'price']));
      if (n != null && n > 0) return n;
    }
    return null;
  }

  static String _trimOneDecimal(double x) {
    final t = x.toStringAsFixed(1);
    return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
  }

  /// Formato compacto tipo `€12.5M` / `€900K` (asume importe en **euros** enteros salvo magnitud).
  static String formatMarketValueCompactEur(num n) {
    if (n <= 0) return '—';
    final x = n.toDouble();
    if (x >= 1_000_000) {
      return '€${_trimOneDecimal(x / 1e6)}M';
    }
    if (x >= 100_000) {
      return '€${_trimOneDecimal(x / 1e6)}M';
    }
    if (x >= 10_000) {
      return '€${_trimOneDecimal(x / 1e3)}K';
    }
    return '€ ${_eurosConPuntos(n.round())}';
  }

  static String formatMarketValueEuroDisplay(dynamic raw) {
    if (raw == null) return '—';
    if (raw is int) return '€ ${_eurosConPuntos(raw)}';
    if (raw is num) return '€ ${_eurosConPuntos(raw.round())}';
    final s = raw.toString().trim();
    if (s.isEmpty) return '—';
    if (s.contains('€')) {
      return s.replaceFirst(RegExp(r'^€\s*'), '€ ');
    }
    final onlyDigits = int.tryParse(s.replaceAll(RegExp(r'[^\d]'), ''));
    if (onlyDigits != null && onlyDigits > 0) return '€ ${_eurosConPuntos(onlyDigits)}';
    return s;
  }

  static DateTime? _parseIsoDate(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final d = DateTime.tryParse(t);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  static const List<String> _monthEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String formatContractMonthYear(DateTime? d) {
    if (d == null) return '—';
    return '${_monthEn[d.month - 1]} ${d.year}';
  }

  static SportmonksContractStatus contractStatusFromEndDate(DateTime? end) {
    if (end == null) return SportmonksContractStatus.unknown;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(today).inDays;
    if (days < 0) return SportmonksContractStatus.expired;
    if (days < 183) return SportmonksContractStatus.expiresUnderSixMonths;
    if (days < 365) return SportmonksContractStatus.expiresUnderTwelveMonths;
    return SportmonksContractStatus.ok;
  }

  static String? _teamNameFrom(dynamic teamObj) {
    final m = _asMap(teamObj);
    if (m == null) return null;
    return _asString(_pick(m, ['name', 'display_name', 'short_code']));
  }

  static String? _transferSideTeamName(Map<String, dynamic> t, List<String> keys) {
    for (final k in keys) {
      if (!t.containsKey(k)) continue;
      final n = _teamNameFrom(t[k]);
      if (n != null) return n;
      final m = _asMap(t[k]);
      if (m != null) {
        final n2 = _teamNameFrom(m);
        if (n2 != null) return n2;
      }
    }
    return null;
  }

  static int? _parseIntLoose(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// `team_id` de cada fila en `player.teams` (orden conservado, sin duplicados).
  static List<int> _teamIdsFromPlayerTeams(List<dynamic> teams) {
    final out = <int>[];
    final seen = <int>{};
    for (final t in teams) {
      final m = _asMap(t);
      if (m == null) continue;
      final tid = _parseIntLoose(m['team_id']);
      if (tid == null || seen.contains(tid)) continue;
      seen.add(tid);
      out.add(tid);
    }
    return out;
  }

  static List<Map<String, dynamic>> _sortTransferMapsDesc(List<dynamic> list) {
    final rows = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      rows.add(Map<String, dynamic>.from(item));
    }
    rows.sort((a, b) {
      final da = _parseIsoDate(_asString(a['date']));
      final db = _parseIsoDate(_asString(b['date']));
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return rows;
  }

  /// Busca la fila de plantel del jugador y devuelve `end` si existe (misma heurística que en `teams`).
  static String? _findEndInSquadRowsForPlayer(List<Map<String, dynamic>> rows, String playerId) {
    if (rows.isEmpty) return null;
    final pivot = <Map<String, dynamic>>[];
    for (final m in rows) {
      if (m['player_id']?.toString() != playerId) continue;
      final end = m['end'];
      if (end == null) continue;
      pivot.add({'end': end});
    }
    return _pickContractEndFromTeams(pivot);
  }

  /// `GET /squads/teams/{teamId}`: a veces trae `end` aunque `player.teams` venga vacío o sin `end`.
  static Future<String?> _fetchSquadContractEndForPlayer(String playerId, int teamId, String token) async {
    final key = _cacheKey('squadTeam', '$teamId');
    final cached = _cache[key];
    if (cached is List) {
      final rows = <Map<String, dynamic>>[];
      for (final e in cached) {
        if (e is Map<String, dynamic>) {
          rows.add(e);
        } else if (e is Map) {
          rows.add(Map<String, dynamic>.from(e));
        }
      }
      return _findEndInSquadRowsForPlayer(rows, playerId);
    }

    final uri = Uri.parse('$_baseUrl/squads/teams/$teamId').replace(queryParameters: {
      'api_token': token.trim(),
    });
    final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
    if (res.statusCode != 200) return null;
    final root = _asMap(json.decode(res.body));
    if (root == null) return null;
    if (root['message'] != null && root['data'] == null) return null;
    final data = root['data'];
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      for (final e in data) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    } else {
      return null;
    }
    _cache[key] = rows;
    return _findEndInSquadRowsForPlayer(rows, playerId);
  }

  /// Hasta [maxSquadRequests] GET de plantel: primero clubes en `player.teams`, luego `to_team_id` de transferencias recientes.
  static Future<String?> _trySquadContractFallback(
    String playerId,
    String token,
    List<int> teamIdsFromPlayerTeams,
    List<Map<String, dynamic>> transfersDesc, {
    int maxSquadRequests = 4,
  }) async {
    var requests = 0;
    final triedTeams = <int>{};

    Future<String?> probe(int teamId) async {
      if (triedTeams.contains(teamId)) return null;
      if (requests >= maxSquadRequests) return null;
      triedTeams.add(teamId);
      requests++;
      return _fetchSquadContractEndForPlayer(playerId, teamId, token);
    }

    for (final tid in teamIdsFromPlayerTeams) {
      final end = await probe(tid);
      if (end != null) return end;
    }
    for (final t in transfersDesc) {
      if (requests >= maxSquadRequests) break;
      final tid = _parseIntLoose(t['to_team_id']);
      if (tid == null) continue;
      final end = await probe(tid);
      if (end != null) return end;
    }
    return null;
  }

  static String? _pickContractEndFromTeams(List<dynamic>? teams) {
    if (teams == null || teams.isEmpty) return null;
    final candidates = <({DateTime? end, String raw})>[];
    for (final t in teams) {
      final m = _asMap(t);
      if (m == null) continue;
      final raw = _asString(m['end']);
      if (raw == null) continue;
      final d = DateTime.tryParse(raw);
      candidates.add((end: d, raw: raw));
    }
    if (candidates.isEmpty) return null;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    String? bestFutureRaw;
    DateTime? bestFutureDay;
    for (final c in candidates) {
      if (c.end == null) continue;
      final end = c.end!;
      final ed = DateTime(end.year, end.month, end.day);
      if (!ed.isBefore(todayDay)) {
        if (bestFutureDay == null || ed.isAfter(bestFutureDay)) {
          bestFutureDay = ed;
          bestFutureRaw = c.raw;
        }
      }
    }
    if (bestFutureRaw != null) return bestFutureRaw;
    candidates.sort((a, b) {
      if (a.end == null) return 1;
      if (b.end == null) return -1;
      return b.end!.compareTo(a.end!);
    });
    return candidates.first.raw;
  }

  static Future<Map<String, dynamic>> _searchPlayersFirstPage(String name, String token) async {
    final q = name.trim();
    if (q.isEmpty) {
      return {'ok': false, 'error': 'nombre vacío'};
    }
    final enc = Uri.encodeComponent(q);
    final key = _cacheKey('search', enc);
    if (_cache.containsKey(key)) return _snapshot(_cache[key]! as Map<String, dynamic>);

    final uri = Uri.parse('$_baseUrl/players/search/$enc').replace(queryParameters: {
      'api_token': token.trim(),
      'per_page': '15',
    });
    final res = await _httpGet(uri, token: token);
    if (res.statusCode != 200) {
      return {
        'ok': false,
        'error': _userFacingHttpError(res.statusCode),
        'statusCode': res.statusCode,
      };
    }
    final decoded = json.decode(res.body);
    final root = _asMap(decoded);
    final data = root == null ? null : root['data'];
    final rawList = <Map<String, dynamic>>[];
    if (data is List) {
      for (final e in data) {
        if (e is Map) rawList.add(Map<String, dynamic>.from(e));
      }
    }
    final out = <String, dynamic>{'ok': true, 'query': q, 'players': rawList};
    _cache[key] = out;
    return _snapshot(out);
  }

  /// Apellido u otro fragmento si el nombre viene abreviado ("S. Driussi" → "Driussi").
  static String? _searchFallbackQuery(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    if (RegExp(r'^[A-Za-zÁÉÍÓÚáéíóúÑñ]\.$').hasMatch(parts.first)) {
      return parts.sublist(1).join(' ');
    }
    return null;
  }

  /// Elige el jugador cuyo nombre coincide mejor con [wantedName]; si no hay match, el primero.
  static Map<String, dynamic>? _pickBestPlayerRow(List<Map<String, dynamic>> players, String wantedName) {
    if (players.isEmpty) return null;
    final target = wantedName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final r in players) {
      final n = (_asString(_pick(r, ['display_name', 'name', 'common_name'])) ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (n.isNotEmpty && (n == target || n.contains(target) || target.contains(n))) {
        return r;
      }
    }
    return players.first;
  }

  /// Contrato vía `teams.team` y, si hace falta, hints `teamIdsHint` para fallback por plantel.
  static Future<Map<String, dynamic>> _fetchPlayerContractBundle(String id, String token) async {
    final key = _cacheKey('playerTeams', id);
    if (_cache.containsKey(key)) return _snapshot(_cache[key]! as Map<String, dynamic>);

    final uri = Uri.parse('$_baseUrl/players/$id').replace(queryParameters: {
      'api_token': token.trim(),
      'include': 'teams.team',
    });
    final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
    if (res.statusCode != 200) {
      return {
        'ok': false,
        'error': _userFacingHttpError(res.statusCode),
        'statusCode': res.statusCode,
      };
    }
    final decoded = json.decode(res.body);
    final root = _asMap(decoded);
    final player = _unwrapPlayer(root == null ? null : root['data']);
    if (player == null) {
      return {'ok': false, 'error': 'JSON: sin jugador'};
    }
    final teams = player['teams'];
    final contratoHasta = teams is List ? _pickContractEndFromTeams(teams) : null;
    final teamIdsHint = teams is List ? _teamIdsFromPlayerTeams(teams) : <int>[];
    final mapped = <String, dynamic>{
      'ok': true,
      'id': id,
      'contratoHasta': contratoHasta,
      'teamIdsHint': teamIdsHint,
    };
    _cache[key] = mapped;
    return _snapshot(mapped);
  }

  /// Transferencias por endpoint dedicado (paginado).
  static Future<Map<String, dynamic>> _fetchTransfersByPlayer(String id, String token) async {
    final key = _cacheKey('transfersPlayer', id);
    if (_cache.containsKey(key)) return _snapshot(_cache[key]! as Map<String, dynamic>);

    final allRaw = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;
    while (hasMore && page <= 15) {
      final uri = Uri.parse('$_baseUrl/transfers/players/$id').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'fromTeam;toTeam',
        'per_page': '50',
        'page': '$page',
        'order': 'desc',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) {
        if (allRaw.isEmpty) {
          return {
            'ok': false,
            'error': _userFacingHttpError(res.statusCode),
            'statusCode': res.statusCode,
            'lines': <SportmonksTransferLine>[],
            'sortedRaw': <Map<String, dynamic>>[],
          };
        }
        break;
      }
      final root = _asMap(json.decode(res.body));
      final data = root?['data'];
      if (data is List) {
        for (final e in data) {
          final m = _asMap(e);
          if (m != null) allRaw.add(m);
        }
      }
      hasMore = _paginationHasMore(root);
      page++;
    }

    final sortedRaw = _sortTransferMapsDesc(allRaw);
    final lines = _buildTransferLinesFromSortedMaps(sortedRaw);
    final mapped = <String, dynamic>{
      'ok': true,
      'lines': lines,
      'sortedRaw': sortedRaw,
    };
    _cache[key] = mapped;
    return _snapshot(mapped);
  }

  static List<SportmonksTransferLine> _buildTransferLinesFromSortedMaps(List<Map<String, dynamic>> sorted) {
    return sorted.map((t) {
      final fromName = _transferSideTeamName(t, const ['fromTeam', 'fromteam', 'from_team']);
      final toName = _transferSideTeamName(t, const ['toTeam', 'toteam', 'to_team']);
      final fromFallback = t['from_team_id'] != null ? 'Club #${t['from_team_id']}' : null;
      final toFallback = t['to_team_id'] != null ? 'Club #${t['to_team_id']}' : null;
      final dateStr = _asString(t['date']);
      final dt = _parseIsoDate(dateStr);
      final year = dt?.year;
      final amount = t['amount'];
      return SportmonksTransferLine(
        year: year,
        fromClub: fromName ?? fromFallback ?? '—',
        toClub: toName ?? toFallback ?? '—',
        amountFormatted: formatMarketValueEuroDisplay(amount),
      );
    }).toList();
  }

  static double? _ageYearsFromBirthString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.trim());
    if (d == null) return null;
    final now = DateTime.now();
    var years = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      years--;
    }
    if (years < 10 || years > 55) return null;
    return years.toDouble();
  }

  /// Normaliza nombres de club para comparar API-Football ↔ Sportmonks.
  static String _normTeamKey(String raw) {
    var s = raw.trim().toLowerCase();
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ñ': 'n',
      'ü': 'u',
    };
    for (final e in accents.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// API-Football (liga 128) → Sportmonks team id (temporada LPF 26808). Evita cruces por fuzzy match.
  static const Map<int, int> _lpfHardcodedSportmonksTeamId = {
    451: 587, // Boca Juniors
    450: 9335, // Estudiantes (La Plata)
    438: 9904, // Vélez Sarsfield
    441: 7228, // Unión Santa Fe
    442: 9561, // Defensa y Justicia
    446: 9878, // Lanús
    453: 10840, // Independiente
    456: 9999, // Talleres Córdoba
    460: 520, // San Lorenzo
    478: 9941, // Instituto
    1064: 9896, // Platense
    1066: 14288, // Gimnasia Mendoza
    1065: 14212, // Central Córdoba SdE
    457: 32, // Newell's
    476: 14578, // Deportivo Riestra
    435: 10002, // River Plate
    458: 3393, // Argentinos Juniors
    440: 6829, // Belgrano
    437: 3365, // Rosario Central
    445: 3139, // Huracán
    2432: 8228, // Barracas Central
    452: 9884, // Tigre
    436: 3608, // Racing Club
    474: 9931, // Sarmiento
    434: 470, // Gimnasia La Plata
    449: 887, // Banfield
    455: 10675, // Atlético Tucumán
    473: 812, // Independiente Rivadavia
    463: 9874, // Aldosivi
    2424: 12186, // Estudiantes Río Cuarto
  };

  /// Cuando Sportmonks/API-Football no envían `venue.image` (común en varios clubes LPF).
  static const Map<int, String> _lpfStadiumPhotoByApiFootballId = {
    450: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Estadio_Jorge_Luis_Hirschi_-_Estudiantes_de_La_Plata.jpg/1280px-Estadio_Jorge_Luis_Hirschi_-_Estudiantes_de_La_Plata.jpg',
    434: 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Estadio_Juan_Carmelo_Zerillo.jpg/1280px-Estadio_Juan_Carmelo_Zerillo.jpg',
    2424: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Estadio_Antonio_Candini.jpg/1280px-Estadio_Antonio_Candini.jpg',
  };

  static String? stadiumPhotoFallbackForApiTeam(int apiFootballTeamId) {
    final id = reconcileLpfApiFootballTeamId(apiFootballTeamId, '');
    return _lpfStadiumPhotoByApiFootballId[id];
  }

  /// Alias por id API-Football (liga 128) — evita confundir Racing, Independiente, etc.
  static const Map<int, List<String>> _lpfApiFootballAliases = {
    451: ['Boca Juniors', 'CA Boca Juniors', 'Boca'],
    450: ['Estudiantes', 'Estudiantes L.P.', 'Estudiantes de La Plata', 'Estudiantes LP'],
    438: ['Velez Sarsfield', 'Vélez Sarsfield', 'Velez'],
    441: ['Union Santa Fe', 'Unión Santa Fe'],
    442: ['Defensa y Justicia'],
    446: ['Lanus', 'Lanús'],
    453: ['Independiente', 'CA Independiente'],
    456: ['Talleres Cordoba', 'Talleres Córdoba', 'Talleres'],
    460: ['San Lorenzo', 'San Lorenzo de Almagro'],
    478: ['Instituto Cordoba', 'Instituto'],
    1064: ['Platense'],
    1066: ['Gimnasia y Esgrima Mendoza', 'Gimnasia Mendoza'],
    1065: ['Central Cordoba Santiago', 'Central Córdoba', 'Central Cordoba'],
    457: ["Newell's Old Boys", 'Newells Old Boys'],
    476: ['Deportivo Riestra'],
    435: ['River Plate', 'River'],
    458: ['Argentinos Juniors', 'Argentinos JRS'],
    440: ['Belgrano Cordoba', 'Belgrano'],
    437: ['Rosario Central'],
    445: ['Huracan', 'Huracán', 'CA Huracán'],
    2432: ['Barracas Central'],
    452: ['Tigre', 'CA Tigre'],
    436: ['Racing Club', 'Racing'],
    474: ['Sarmiento Junin', 'Sarmiento'],
    449: ['Banfield'],
    455: ['Atletico Tucuman', 'Atlético Tucumán'],
    473: ['Independiente Rivadavia'],
    463: ['Aldosivi', 'CA Aldosivi'],
    2424: [
      'Estudiantes de Río Cuarto',
      'Estudiantes de Rio Cuarto',
      'Estudiantes Rio Cuarto',
      'Estudiantes Río Cuarto',
    ],
    434: ['Gimnasia La Plata', 'Gimnasia y Esgrima L.P.', 'Gimnasia LP', 'Gimnasia y Esgrima La Plata'],
  };

  /// Corrige id API-Football cuando el fixture trae nombre e id de otro club (Estudiantes LP vs ERC).
  static int reconcileLpfApiFootballTeamId(int apiFootballTeamId, String teamName) {
    final n = _normTeamKey(teamName);
    if (n.isEmpty) return apiFootballTeamId;

    if (n.contains('riocuarto') ||
        n.contains('riocuart') ||
        n.contains('estudiantesderio') ||
        n.contains('estudiantesderiocuarto')) {
      return 2424;
    }
    if (n.contains('gimnasia') && n.contains('mendoza')) {
      return 1066;
    }
    if (n.contains('gimnasia') &&
        (n.contains('plata') || n.contains('esgrimalp') || n.contains('esgrimalaplata'))) {
      return 434;
    }
    if (n.contains('estudiantes') &&
        !n.contains('riocuarto') &&
        !n.contains('riocuart') &&
        !n.contains('derio')) {
      return 450;
    }
  return apiFootballTeamId;
  }

  static List<String> _teamNameCandidates(String teamName, {int? apiFootballTeamId}) {
    final aliases = apiFootballTeamId != null ? _lpfApiFootballAliases[apiFootballTeamId] : null;
    if (aliases != null && aliases.isNotEmpty) {
      return aliases.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    }
    final t = teamName.trim();
    if (t.isEmpty) return const [];
    return [t];
  }

  /// Catálogo de equipos de la temporada LPF en Sportmonks (id + nombres).
  Future<List<({int id, String name, String? short})>> _fetchLpfSeasonTeamCatalog(
    String token,
    int seasonId,
  ) async {
    final key = _cacheKey('lpfTeamCatalog', '$seasonId');
    final hit = _cache[key];
    if (hit is List) {
      return List<({int id, String name, String? short})>.from(hit);
    }

    final catalog = <({int id, String name, String? short})>[];
    var page = 1;
    var hasMore = true;
    while (hasMore) {
      final uri = Uri.parse('$_baseUrl/teams/seasons/$seasonId').replace(queryParameters: {
        'api_token': token.trim(),
        'per_page': '50',
        'page': '$page',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) break;
      final root = _asMap(json.decode(res.body));
      if (root == null || _apiErrorsPresent(root)) break;
      final data = root['data'];
      if (data is List) {
        for (final raw in data) {
          final row = _asMap(raw);
          if (row == null) continue;
          final nested = _asMap(row['team']) ?? _asMap(row['participant']);
          final team = nested ?? row;
          final id = _parseIntLoose(team['id']) ??
              _parseIntLoose(row['team_id']) ??
              _parseIntLoose(row['participant_id']);
          final name = _asString(team['name']);
          if (id == null || id <= 0 || name == null) continue;
          final short = _asString(team['short_code']);
          catalog.add((id: id, name: name, short: short));
        }
      }
      hasMore = _paginationHasMore(root) && page < 30;
      page++;
    }
    _cache[key] = catalog;
    return catalog;
  }

  /// Solo coincidencia exacta de nombre normalizado (sin `contains` — evita Estudiantes ↔ Platense).
  int? _matchTeamInLpfCatalog(
    List<({int id, String name, String? short})> catalog,
    String teamName, {
    int? apiFootballTeamId,
  }) {
    final candidates = _teamNameCandidates(teamName, apiFootballTeamId: apiFootballTeamId)
        .map(_normTeamKey)
        .where((k) => k.length >= 3)
        .toSet();
    if (candidates.isEmpty) return null;

    for (final t in catalog) {
      final labels = <String>[t.name, if (t.short != null && t.short!.isNotEmpty) t.short!];
      for (final label in labels) {
        final norm = _normTeamKey(label);
        if (norm.isNotEmpty && candidates.contains(norm)) return t.id;
      }
    }
    return null;
  }

  /// Nombre preferido para resolver plantel LPF (alias API-Football).
  static String? primaryAliasForApiFootballTeam(int apiFootballTeamId) {
    final list = _lpfApiFootballAliases[apiFootballTeamId];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  /// Construye API-Football id → Sportmonks id (hardcoded + catálogo exacto).
  Future<void> _ensureApiFootballToSportmonksMap(String token) async {
    if (_apiFootballToSportmonksTeam != null) return;
    final map = Map<int, int>.from(_lpfHardcodedSportmonksTeamId);
    final seasonId = await _lpfSeasonIdForPlayers(token);
    if (seasonId != null) {
      final catalog = await _fetchLpfSeasonTeamCatalog(token, seasonId);
      for (final entry in _lpfApiFootballAliases.entries) {
        if (map.containsKey(entry.key)) continue;
        for (final alias in entry.value) {
          final smId = _matchTeamInLpfCatalog(
            catalog,
            alias,
            apiFootballTeamId: entry.key,
          );
          if (smId != null) {
            map[entry.key] = smId;
            break;
          }
        }
      }
    }
    _apiFootballToSportmonksTeam = map;
  }

  /// ID Sportmonks del club LPF para un id de equipo de API-Football (liga 128).
  Future<int?> sportmonksTeamIdForApiFootball(
    int apiFootballTeamId,
    String displayName,
  ) async {
    final apiId = reconcileLpfApiFootballTeamId(apiFootballTeamId, displayName);
    if (apiId <= 0) return null;

    final hard = _lpfHardcodedSportmonksTeamId[apiId];
    if (hard != null && hard > 0) return hard;

    final token = _pickToken();
    if (token == null) return null;

    await _ensureApiFootballToSportmonksMap(token);
    final cached = _apiFootballToSportmonksTeam?[apiId];
    if (cached != null && cached > 0) return cached;

    final seasonId = await _lpfSeasonIdForPlayers(token);
    if (seasonId == null) return null;

    final name = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (primaryAliasForApiFootballTeam(apiId) ?? '');
    if (name.isEmpty) return null;

    final resolved = await _resolveLpfSportmonksTeamId(
      name,
      token,
      apiFootballTeamId: apiId,
      seasonId: seasonId,
    );
    if (resolved != null && resolved > 0) {
      _apiFootballToSportmonksTeam ??= {};
      _apiFootballToSportmonksTeam![apiId] = resolved;
    }
    return resolved;
  }

  Future<int?> _resolveLpfSportmonksTeamId(
    String teamName,
    String token, {
    int? apiFootballTeamId,
    int? seasonId,
  }) async {
    final sid = seasonId ?? await _lpfSeasonIdForPlayers(token);
    if (sid == null) return null;
    final catalog = await _fetchLpfSeasonTeamCatalog(token, sid);
    if (catalog.isEmpty) return null;
    return _matchTeamInLpfCatalog(catalog, teamName, apiFootballTeamId: apiFootballTeamId);
  }

  Future<int?> _resolveSportmonksTeamForLigaArgentina(
    String teamName,
    String token, {
    int? apiFootballTeamId,
  }) async {
    final apiId = apiFootballTeamId;
    if (apiId != null && apiId > 0) {
      final mapped = await sportmonksTeamIdForApiFootball(apiId, teamName);
      if (mapped != null) return mapped;
    }
    final lpf = await _resolveLpfSportmonksTeamId(
      teamName,
      token,
      apiFootballTeamId: apiFootballTeamId,
    );
    if (lpf != null) return lpf;
    // Con id API-Football no buscar otro "Racing/Independiente" en el mundo.
    if (apiId != null && apiId > 0) return null;
    return _sportmonksTeamIdFromSearch(teamName, token, preferCountryName: 'Argentina');
  }

  static Future<int?> _sportmonksTeamIdFromSearch(
    String name,
    String token, {
    String? preferCountryName,
  }) async {
    final q = name.trim();
    if (q.isEmpty) return null;
    final enc = Uri.encodeComponent(q);
    final key = _cacheKey('teamSearch', '$enc|${preferCountryName ?? ''}');
    if (_cache.containsKey(key)) {
      final hit = _cache[key];
      if (hit is int) return hit;
      if (hit == null) return null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/teams/search/$enc').replace(queryParameters: {
        'api_token': token.trim(),
        'per_page': '15',
        'include': 'country',
      });
      final res = await _httpGet(uri, token: token);
      if (res.statusCode != 200) {
        _cache[key] = null;
        return null;
      }
      final root = _asMap(json.decode(res.body));
      if (_apiErrorsPresent(root)) {
        _cache[key] = null;
        return null;
      }
      final data = root?['data'];
      if (data is! List || data.isEmpty) {
        _cache[key] = null;
        return null;
      }
      final wantKey = _normTeamKey(q);
      final prefer = preferCountryName?.trim().toLowerCase();

      int scoreRow(Map<String, dynamic> row) {
        var score = 0;
        final rowName = _normTeamKey(_asString(_pick(row, ['name', 'display_name'])) ?? '');
        if (rowName == wantKey) score += 100;
        else if (rowName.contains(wantKey) || wantKey.contains(rowName)) score += 50;
        if (prefer != null && prefer.isNotEmpty) {
          final country = _asMap(row['country']);
          final cname = (_asString(country?['name']) ?? '').toLowerCase();
          if (cname == prefer || cname.contains(prefer)) score += 40;
        }
        return score;
      }

      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final raw in data) {
        final row = _asMap(raw);
        if (row == null) continue;
        final sc = scoreRow(row);
        if (sc > bestScore) {
          bestScore = sc;
          best = row;
        }
      }
      best ??= _asMap(data.first);
      final id = _parseIntLoose(best?['id']);
      if (id == null || id <= 0) {
        _cache[key] = null;
        return null;
      }
      _cache[key] = id;
      return id;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }

  Future<SportmonksSquadInfo?> _aggregateSquadInfo(int sportmonksTeamId, String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/squads/teams/$sportmonksTeamId').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'player',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) return null;
      final root = _asMap(json.decode(res.body));
      if (_apiErrorsPresent(root)) return null;
      final data = root?['data'];
      final rows = <Map<String, dynamic>>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map<String, dynamic>) {
            rows.add(e);
          } else if (e is Map) {
            rows.add(Map<String, dynamic>.from(e));
          }
        }
      }
      if (rows.isEmpty) return null;

      final ages = <double>[];
      num sumValue = 0;
      var nValues = 0;
      for (final row in rows) {
        final player = _asMap(row['player']);
        if (player == null) continue;
        final dob = _asString(player['date_of_birth']);
        final age = _ageYearsFromBirthString(dob);
        if (age != null) ages.add(age);
        final v = _asNumLoose(_pick(player, ['value', 'market_value', 'price', 'worth']));
        if (v != null && v > 0) {
          sumValue += v;
          nValues++;
        }
      }

      final avg = ages.isEmpty ? null : ages.reduce((a, b) => a + b) / ages.length;
      final total = nValues > 0 ? sumValue : null;
      final out = SportmonksSquadInfo(averageAge: avg, totalMarketValueEuros: total);
      if (!out.hasAnyData) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Datos de plantel Sportmonks para mostrar bajo la formación.
  ///
  /// [teamId] es el ID del club en **API-Football** (u otro origen): solo sirve como parte de la clave de caché.
  /// [teamName] debe ser el nombre del equipo (como en el fixture); Sportmonks resuelve el club por búsqueda,
  /// porque los IDs no coinciden entre proveedores.
  Future<SportmonksSquadInfo?> getSquadInfo(int teamId, {required String teamName}) async {
    final token = _pickToken();
    if (token == null) return null;
    final name = teamName.trim();
    if (name.isEmpty) return null;

    final memKey = '$teamId|${name.toLowerCase()}';
    if (_squadInfoCache.containsKey(memKey)) {
      return _squadInfoCache[memKey];
    }

    var smId = teamId > 0 ? await sportmonksTeamIdForApiFootball(teamId, name) : null;
    smId ??= await _resolveSportmonksTeamForLigaArgentina(name, token, apiFootballTeamId: teamId);
    if (smId == null) {
      _squadInfoCache[memKey] = null;
      return null;
    }

    final info = await _aggregateSquadInfo(smId, token);
    _squadInfoCache[memKey] = info;
    return info;
  }

  static int? _lpfSeasonIdFromEnv() {
    const raw = String.fromEnvironment('SPORTMONKS_LPF_SEASON_ID', defaultValue: '');
    final id = int.tryParse(raw.trim());
    if (id == null || id <= 0) return null;
    return id;
  }

  static int? _mundialSeasonIdFromEnv() {
    const raw = String.fromEnvironment('SPORTMONKS_WORLD_CUP_SEASON_ID', defaultValue: '');
    final id = int.tryParse(raw.trim());
    if (id == null || id <= 0) return null;
    return id;
  }

  /// ID de temporada Sportmonks para Copa del Mundo (2026 u otra edición configurada).
  Future<int?> resolveWorldCupSeasonSportmonksId() async {
    final token = _pickToken();
    if (token == null) return null;
    final r = await _resolveWorldCupSeasonSportmonksId(token);
    return r.id;
  }

  Future<({int? id, String? error})> _resolveWorldCupSeasonSportmonksId(String token) async {
    final fromEnv = _mundialSeasonIdFromEnv();
    if (fromEnv != null) return (id: fromEnv, error: null);

    const cacheKey = 'wcSeasonSm:v1';
    final hit = _cache[cacheKey];
    if (hit is int && hit > 0) return (id: hit, error: null);

    const queries = ['World Cup 2026', 'FIFA World Cup', 'World Cup'];
    for (final q in queries) {
      try {
        final uri = Uri.parse('$_baseUrl/leagues/search/${Uri.encodeComponent(q)}').replace(
          queryParameters: {
            'api_token': token.trim(),
            'include': 'seasons;currentSeason',
            'per_page': '25',
          },
        );
        final res = await _httpGet(uri, token: token);
        if (res.statusCode != 200) continue;
        final root = _asMap(json.decode(res.body));
        if (_apiErrorsPresent(root)) continue;
        final data = root?['data'];
        if (data is! List) continue;

        int? pickFromLeague(Map<String, dynamic> league) {
          final cs = _asMap(league['currentSeason']);
          final csName = (_asString(cs?['name']) ?? '').toLowerCase();
          final csId = _parseIntLoose(cs?['id']);
          if (csId != null && csId > 0 && csName.contains('2026')) return csId;

          final seasons = league['seasons'];
          if (seasons is List) {
            for (final s in seasons) {
              final sm = _asMap(s);
              if (sm == null) continue;
              final sname = (_asString(sm['name']) ?? '').toLowerCase();
              if (sname.contains('2026')) {
                final sid = _parseIntLoose(sm['id']);
                if (sid != null && sid > 0) return sid;
              }
            }
            final first = _asMap(seasons.first);
            return _parseIntLoose(first?['id']);
          }
          return _parseIntLoose(cs?['id']);
        }

        for (final e in data) {
          final league = _asMap(e);
          if (league == null) continue;
          final lname = (_asString(league['name']) ?? '').toLowerCase();
          if (!lname.contains('world cup') && !lname.contains('worldcup')) continue;
          final sid = pickFromLeague(league);
          if (sid != null && sid > 0) {
            _cache[cacheKey] = sid;
            return (id: sid, error: null);
          }
        }
      } catch (_) {}
    }

    return (
      id: null,
      error: 'No se encontró temporada de Copa del Mundo en Sportmonks. '
          'Definí SPORTMONKS_WORLD_CUP_SEASON_ID en dart_defines.json.',
    );
  }

  Future<int?> _resolveMundialSportmonksTeamId(
    String token,
    int seasonId,
    String teamName,
  ) async {
    final want = _normTeamKey(teamName);
    if (want.isEmpty) return null;

    final catalog = await _fetchMundialSeasonTeamCatalog(token, seasonId);
    if (catalog.containsKey(want)) return catalog[want];

    for (final e in catalog.entries) {
      if (e.key.contains(want) || want.contains(e.key)) return e.value;
    }

    return _sportmonksTeamIdFromSearch(teamName, token, preferCountryName: teamName);
  }

  Future<Map<String, int>> _fetchMundialSeasonTeamCatalog(String token, int seasonId) async {
    final key = _cacheKey('mundialTeamCatalog', '$seasonId');
    if (_cache.containsKey(key)) {
      return Map<String, int>.from(_cache[key]! as Map);
    }
    final out = <String, int>{};
    var page = 1;
    var hasMore = true;
    while (hasMore && page <= 20) {
      final uri = Uri.parse('$_baseUrl/teams/seasons/$seasonId').replace(queryParameters: {
        'api_token': token.trim(),
        'per_page': '50',
        'page': '$page',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) break;
      final root = _asMap(json.decode(res.body));
      final data = root?['data'];
      if (data is List) {
        for (final raw in data) {
          final row = _asMap(raw);
          if (row == null) continue;
          final tm = _asMap(row['team']) ?? row;
          final tid = _parseIntLoose(tm['id']) ?? _parseIntLoose(row['team_id']);
          final name = _asString(_pick(tm, ['name', 'display_name']));
          if (tid == null || tid <= 0 || name == null || name.trim().isEmpty) continue;
          out[_normTeamKey(name)] = tid;
        }
      }
      hasMore = _paginationHasMore(root);
      page++;
    }
    _cache[key] = out;
    return out;
  }

  static bool _esTrofeoMundialSm(String? label) {
    final l = (label ?? '').toLowerCase();
    return l.contains('world cup') ||
        l.contains('worldcup') ||
        l.contains('copa mundial') ||
        l.contains('fifa world');
  }

  static int _rankPuestoMundial(String place) {
    final p = place.toLowerCase();
    if (p.contains('winner') || p == '1' || p.contains('1st') || p.contains('first')) return 100;
    if (p.contains('2nd') || p.contains('second') || p.contains('runner')) return 80;
    if (p.contains('3rd') || p.contains('third')) return 60;
    if (p.contains('semi')) return 50;
    if (p.contains('quarter') || p.contains('1/4')) return 40;
    return 5;
  }

  static String _textoPuestoMundial(String place) {
    final p = place.toLowerCase();
    if (p.contains('winner') || p == '1' || p.contains('1st')) return 'Campeón del Mundo';
    if (p.contains('2nd') || p.contains('second') || p.contains('runner')) return 'Subcampeón';
    if (p.contains('3rd') || p.contains('third')) return '3.er puesto';
    if (p.contains('semi')) return 'Semifinal';
    if (p.contains('quarter') || p.contains('1/4')) return 'Cuartos de final';
    if (p.isNotEmpty) return place;
    return 'Participación';
  }

  static List<Map<String, dynamic>> _parseSmTrophiesMundial(dynamic trophiesRaw) {
    final out = <Map<String, dynamic>>[];
    if (trophiesRaw is! List) return out;
    for (final raw in trophiesRaw) {
      final row = _asMap(raw);
      if (row == null) continue;
      final trophy = _asMap(row['trophy']) ?? row;
      final league = _asMap(row['league']) ?? _asMap(trophy?['league']);
      final leagueName = _asString(league?['name']) ??
          _asString(trophy?['name']) ??
          _asString(row['name']) ??
          '';
      if (!_esTrofeoMundialSm(leagueName)) continue;
      final season = _asMap(row['season']);
      final year = _parseIntLoose(season?['name']) ??
          _parseIntLoose(season?['id']) ??
          _parseIntLoose(row['season_id']);
      final place = _asString(row['place']) ??
          _asString(row['position']) ??
          _asString(trophy?['place']) ??
          '';
      out.add({
        'league': leagueName,
        'season': year != null && year > 0 ? '$year' : '',
        'place': place,
        'source': 'sportmonks',
      });
    }
    return out;
  }

  /// Perfil completo de selección: escudo, foto, títulos y mejores participaciones (Sportmonks).
  Future<Map<String, dynamic>?> fetchMundialSeleccionProfile(
    int apiFootballTeamId,
    String teamName,
  ) async {
    final token = _pickToken();
    if (token == null) return null;
    final name = teamName.trim();
    if (name.isEmpty && apiFootballTeamId <= 0) return null;

    final seasonRes = await _resolveWorldCupSeasonSportmonksId(token);
    final seasonId = seasonRes.id;
    if (seasonId == null) return null;

    final smTeamId = await _resolveMundialSportmonksTeamId(
      token,
      seasonId,
      name.isNotEmpty ? name : 'Team $apiFootballTeamId',
    );
    if (smTeamId == null) return null;

    final key = _cacheKey('mundialSelProfile', '$apiFootballTeamId|$smTeamId');
    if (_cache.containsKey(key)) {
      final hit = _cache[key];
      if (hit is Map) return Map<String, dynamic>.from(hit);
    }

    try {
      final uri = Uri.parse('$_baseUrl/teams/$smTeamId').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'country;trophies.trophy;trophies.season;trophies.league;venue',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) return null;
      final team = _asMap(_asMap(json.decode(res.body))?['data']);
      if (team == null) return null;

      final country = _asMap(team['country']);
      final countryName = _asString(country?['name']) ?? name;
      final logo = _asString(team['image_path']) ?? '';
      final trophiesSm = _parseSmTrophiesMundial(team['trophies']);

      final titulosYears = <int>{};
      final destacadas = <String>[];
      var mejorRank = 0;
      var mejorTxt = '-';

      for (final t in trophiesSm) {
        final place = (t['place'] as String?) ?? '';
        final r = _rankPuestoMundial(place);
        if (r > mejorRank) {
          mejorRank = r;
          mejorTxt = _textoPuestoMundial(place);
        }
        final y = int.tryParse((t['season'] as String?) ?? '') ?? 0;
        final esCampeon = r >= 100;
        if (esCampeon && y > 0) titulosYears.add(y);
        if (y > 0 && r >= 50) {
          destacadas.add('${_textoPuestoMundial(place)} · $y');
        }
      }

      titulosYears.toList().sort((a, b) => b.compareTo(a));
      final titulos = titulosYears.map((y) => '$y').toList();

      final fotoSeleccion = _asString(team['image_path']);

      final mapped = <String, dynamic>{
        'info': {
          'id': apiFootballTeamId > 0 ? apiFootballTeamId : smTeamId,
          'name': _asString(team['name']) ?? name,
          'logo': logo,
          'country': countryName,
          'national': true,
          'sportmonksTeamId': smTeamId,
          'founded': _parseIntLoose(team['founded']),
        },
        'seleccionFotoUrl': fotoSeleccion,
        'titulosMundial': titulos,
        'participacionesDestacadas': destacadas.take(8).toList(),
        'mejorPuestoTexto': mejorTxt,
        'trofeosSm': trophiesSm,
        'fuentePalmarés': 'sportmonks',
      };
      _cache[key] = mapped;
      return mapped;
    } catch (_) {
      return null;
    }
  }

  /// País / selección en formato API-Football (`teams?id=`).
  Future<Map<String, dynamic>?> fetchMundialTeamInfoApiFormat(
    int apiFootballTeamId,
    String teamName,
  ) async {
    final profile = await fetchMundialSeleccionProfile(apiFootballTeamId, teamName);
    if (profile != null) {
      final info = profile['info'];
      if (info is Map) return Map<String, dynamic>.from(info);
    }
    return null;
  }

  /// Plantel mundial en formato API-Football (`player` + `statistics` liga 1).
  Future<List<Map<String, dynamic>>?> fetchMundialPlantelApiFormat(
    int apiFootballTeamId,
    String teamName,
  ) async {
    final token = _pickToken();
    if (token == null) return null;
    final name = teamName.trim();
    if (name.isEmpty && apiFootballTeamId <= 0) return null;

    final seasonRes = await _resolveWorldCupSeasonSportmonksId(token);
    final seasonId = seasonRes.id;
    if (seasonId == null) return null;

    final smTeamId = await _resolveMundialSportmonksTeamId(token, seasonId, name);
    if (smTeamId == null) return null;

    final cacheKey = _cacheKey('mundialSquad', '$apiFootballTeamId|$smTeamId|$seasonId');
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]! as List);
    }

    try {
      final data = await _fetchSquadDataForMundialTeam(token, seasonId, smTeamId);
      if (data == null || data.isEmpty) return null;

      final out = <Map<String, dynamic>>[];
      for (final raw in data) {
        final row = _asMap(raw);
        if (row == null) continue;
        final pl = _asMap(row['player']);
        if (pl == null) continue;
        final display = _asString(_pick(pl, ['display_name', 'name', 'common_name'])) ?? '—';
        final nat = _asMap(pl['nationality']);
        final pos = _asMap(pl['position']);
        final posName = _asString(pos?['name']) ?? 'Midfielder';
        final posApi = _mapPositionToApiFootball(posName);
        final dorsal = _parseIntLoose(row['jersey_number']) ?? _parseIntLoose(row['number']) ?? 0;
        final details = row['details'];
        final pj = _sumDetail(details, const [321]);
        final goles = _sumDetail(details, const [52]);
        final asist = _sumDetail(details, const [79]);
        final rojas = _sumDetail(details, const [83]);
        final amarillas = _sumDetail(details, const [84]);
        final dob = _asString(pl['date_of_birth']);
        final edad = _ageYearsFromBirthString(dob)?.round();
        final smPlayerId = _parseIntLoose(pl['id']) ?? 0;

        out.add({
          'player': {
            'id': smPlayerId,
            'name': display,
            'photo': _asString(pl['image_path']) ?? '',
            'age': edad,
            'nationality': _asString(nat?['name']) ?? '',
            'number': dorsal,
            'sportmonksPlayerId': smPlayerId,
          },
          'statistics': [
            {
              'league': {'id': 1, 'name': 'World Cup'},
              'team': {
                'id': apiFootballTeamId > 0 ? apiFootballTeamId : smTeamId,
                'name': name,
              },
              'games': {
                'position': posApi,
                'number': dorsal,
                'appearences': pj,
                'appearances': pj,
                'rating': null,
              },
              'goals': {'total': goles, 'assists': asist},
              'cards': {'yellow': amarillas, 'red': rojas, 'yellowred': 0},
            },
          ],
        });
      }

      if (out.isEmpty) return null;
      _cache[cacheKey] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> _fetchSquadDataForMundialTeam(
    String token,
    int seasonId,
    int smTeamId,
  ) async {
    const includes = [
      'player.nationality;player.position;details.type',
      'player',
    ];
    final paths = [
      'squads/seasons/$seasonId/teams/$smTeamId',
      'squads/teams/$smTeamId',
    ];

    for (final path in paths) {
      for (final include in includes) {
        final qp = <String, String>{
          'api_token': token.trim(),
          'include': include,
        };
        if (path.startsWith('squads/teams/')) {
          qp['filters'] = 'playerstatisticSeasons:$seasonId';
        }
        final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: qp);
        final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
        if (res.statusCode != 200) continue;
        final root = _asMap(json.decode(res.body));
        if (_apiErrorsPresent(root)) continue;
        final data = root?['data'];
        if (data is! List || data.isEmpty) continue;
        final hasPlayer = data.any((e) => _asMap(_asMap(e)?['player']) != null);
        if (hasPlayer) return data;
      }
    }
    return null;
  }

  static bool _looksLikeSuspension(String categoryLower, String typeLower) {
    final s = '$categoryLower $typeLower';
    if (s.isEmpty) return false;
    return s.contains('suspension') ||
        s.contains('suspended') ||
        s.contains('suspensión') ||
        s.contains('red card') ||
        s.contains('discipline') ||
        s.contains('disciplinary') ||
        s.contains('ban ') ||
        s.contains('banned') ||
        (s.contains('tarjeta') && s.contains('roja'));
  }

  static bool _isInjurySidelined(Map<String, dynamic> row, Map<String, dynamic>? typeMap) {
    final cat = (_asString(row['category']) ?? '').toLowerCase();
    final typeName = (_asString(_pick(typeMap ?? {}, ['name', 'developer_name'])) ?? '').toLowerCase();
    if (_looksLikeSuspension(cat, typeName)) return false;
    if (cat.contains('suspend')) return false;
    return cat.contains('injury') || cat.contains('injur') || cat.contains('lesion');
  }

  static String? _playerPhotoFromSidelined(Map<String, dynamic> row) {
    final pl = _asMap(row['player']);
    return _asString(pl?['image_path']);
  }

  static bool _paginationHasMore(Map<String, dynamic>? root) {
    if (root == null) return false;
    final p = _asMap(root['pagination']);
    if (p == null) return false;
    final hm = p['has_more'];
    if (hm is bool) return hm;
    if (hm is num) return hm != 0;
    final nx = p['next_page'];
    if (nx == null) return false;
    if (nx is num) return nx > 0;
    return nx.toString().trim().isNotEmpty && nx.toString() != 'null';
  }

  static Future<({int? id, String? error})> _resolveLpfSeasonSportmonksId(String token) async {
    final fromEnv = _lpfSeasonIdFromEnv();
    if (fromEnv != null) return (id: fromEnv, error: null);

    const cacheKey = 'lpfSeasonSm:v1';
    final hit = _cache[cacheKey];
    if (hit is int && hit > 0) return (id: hit, error: null);

    try {
      final uri = Uri.parse('$_baseUrl/leagues/search/${Uri.encodeComponent('Liga Profesional')}').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'currentSeason;country',
        'per_page': '40',
      });
      final res = await _httpGet(uri, token: token);
      if (res.statusCode != 200) {
        return (id: null, error: _userFacingHttpError(res.statusCode));
      }
      final root = _asMap(json.decode(res.body));
      if (root == null) {
        return (id: null, error: 'Sportmonks: no se pudo resolver la temporada LPF (liga).');
      }
      if (_apiErrorsPresent(root)) {
        return (id: null, error: 'Sportmonks: no se pudo resolver la temporada LPF (liga).');
      }
      final Map<String, dynamic> rootMap = root;
      final data = rootMap['data'];
      if (data is! List) {
        return (id: null, error: 'Sportmonks: respuesta de ligas inválida.');
      }
      int? pickSeason(Map<String, dynamic> league) {
        final cs = _asMap(league['currentSeason']);
        final sid = _parseIntLoose(cs?['id']);
        if (sid != null && sid > 0) return sid;
        final seasons = league['seasons'];
        if (seasons is List && seasons.isNotEmpty) {
          final first = _asMap(seasons.first);
          return _parseIntLoose(first?['id']);
        }
        return null;
      }

      for (final e in data) {
        final league = _asMap(e);
        if (league == null) continue;
        final country = _asMap(league['country']);
        final cname = (country?['name'] as String?)?.toLowerCase() ?? '';
        if (cname != 'argentina') continue;
        final name = (league['name'] as String?)?.toLowerCase() ?? '';
        final looksLpf = name.contains('profesional') || name.contains('lpf');
        final looksPrimera = name.contains('primera');
        if (!looksLpf && !looksPrimera) continue;
        final sid = pickSeason(league);
        if (sid != null) {
          _cache[cacheKey] = sid;
          return (id: sid, error: null);
        }
      }
      return (
        id: null,
        error: 'No se encontró temporada actual de LPF en Sportmonks. '
            'Definí SPORTMONKS_LPF_SEASON_ID en dart_defines.json.',
      );
    } catch (e) {
      return (id: null, error: e.toString());
    }
  }

  static String? _playerDisplayFromSidelined(Map<String, dynamic> row) {
    final pl = _asMap(row['player']);
    if (pl != null) {
      final n = _asString(_pick(pl, ['display_name', 'name', 'common_name']));
      if (n != null) return n;
    }
    return null;
  }

  /// Perfil de club (estadio, foto del venue, capacidad) vía `teams/{sportmonksId}?include=venue`.
  Future<SportmonksClubProfile?> fetchClubProfileForApiFootball(
    int apiFootballTeamId,
    String teamName,
  ) async {
    final apiId = reconcileLpfApiFootballTeamId(apiFootballTeamId, teamName);
    if (apiId <= 0) return null;
    final token = _pickToken();
    if (token == null) return null;

    final smId = await sportmonksTeamIdForApiFootball(apiId, teamName);
    if (smId == null) return null;

    final key = _cacheKey('clubProfile', '$smId');
    final hit = _cache[key];
    if (hit is SportmonksClubProfile) return hit;
    if (hit == null && _cache.containsKey(key)) return null;

    try {
      final uri = Uri.parse('$_baseUrl/teams/$smId').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'venue',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutSearch);
      if (res.statusCode != 200) {
        _cache[key] = null;
        return null;
      }
      final root = _asMap(json.decode(res.body));
      if (_apiErrorsPresent(root)) {
        _cache[key] = null;
        return null;
      }
      final team = _asMap(root?['data']);
      if (team == null) {
        _cache[key] = null;
        return null;
      }
      final venue = _asMap(team['venue']);
      final cap = _parseIntLoose(venue?['capacity']);
      var venueImg = _asString(venue?['image_path']);
      if (venueImg == null || venueImg.trim().isEmpty) {
        venueImg = _asString(venue?['image']);
      }
      final venueId = _parseIntLoose(team['venue_id']) ?? _parseIntLoose(venue?['id']);
      if ((venueImg == null || venueImg.trim().isEmpty) && venueId != null) {
        venueImg = await _fetchVenueImageById(venueId, token);
      }
      if (venueImg == null || venueImg.trim().isEmpty) {
        venueImg = stadiumPhotoFallbackForApiTeam(apiId);
      }
      final profile = SportmonksClubProfile(
        sportmonksTeamId: smId,
        name: _asString(team['name']),
        logoUrl: _asString(team['image_path']),
        venueName: _asString(venue?['name']),
        venueImageUrl: venueImg,
        venueCity: _asString(venue?['city_name']),
        venueCapacity: cap,
        foundedYear: _parseIntLoose(team['founded']),
      );
      _cache[key] = profile;
      return profile;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }

  /// Parsea equipos de `teams/seasons/{id}` con sidelined; prueba distintos `include` si hace falta.
  Future<({List<Map<String, dynamic>> teams, String? error})> _fetchLpfSeasonTeamsWithSidelined(
    String token,
    int seasonId,
    String include,
  ) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;
    var sawSidelinedKey = false;

    while (hasMore) {
      final uri = Uri.parse('$_baseUrl/teams/seasons/$seasonId').replace(queryParameters: {
        'api_token': token.trim(),
        'include': include,
        'per_page': '50',
        'page': '$page',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) {
        return (teams: out, error: _userFacingHttpError(res.statusCode));
      }
      final root = _asMap(json.decode(res.body));
      if (root == null || _apiErrorsPresent(root)) {
        return (teams: out, error: 'Sportmonks: error al listar equipos de la temporada.');
      }
      final data = root['data'];
      if (data is List) {
        for (final raw in data) {
          final team = _asMap(raw);
          if (team == null) continue;
          if (team.containsKey('sidelined')) sawSidelinedKey = true;
          out.add(team);
        }
      }
      hasMore = _paginationHasMore(root);
      page++;
      if (page > 10) break;
    }
    if (!sawSidelinedKey && out.isNotEmpty) {
      return (teams: <Map<String, dynamic>>[], error: null);
    }
    return (teams: out, error: null);
  }

  /// Jugadores que no deben figurar como lesionados (dato desactualizado en Sportmonks).
  static bool _excluirLesionadoLpf(String playerName, String teamName) {
    final p = playerName.toLowerCase();
    final t = teamName.toLowerCase();
    if (p.contains('cauteruccio') && t.contains('independiente') && !t.contains('rivadavia')) {
      return true;
    }
    return false;
  }

  List<SportmonksInjuryRow> _injuryRowsFromSeasonTeams(List<Map<String, dynamic>> teams) {
    final merged = <SportmonksInjuryRow>[];
    final seenPlayer = <String>{};

    for (final team in teams) {
      final teamSmId = _parseIntLoose(team['id']);
      final teamName = _asString(team['name']) ?? '—';
      final sidelined = team['sidelined'];
      if (sidelined is! List) continue;
      for (final raw in sidelined) {
        final row = _asMap(raw);
        if (row == null) continue;
        if (row['completed'] == true) continue;
        final rowTeamId = _parseIntLoose(row['team_id']);
        if (teamSmId != null && rowTeamId != null && rowTeamId != teamSmId) continue;
        final typeMap = _asMap(row['type']);
        if (!_isInjurySidelined(row, typeMap)) continue;
        final pid = row['player_id']?.toString() ?? '';
        final dedupeKey = pid.isNotEmpty ? pid : '${teamName}_${_asString(row['category'])}_${_asString(row['start_date'])}';
        if (seenPlayer.contains(dedupeKey)) continue;
        seenPlayer.add(dedupeKey);
        final pname = _playerDisplayFromSidelined(row) ?? (pid.isNotEmpty ? 'Jugador #$pid' : '—');
        if (_excluirLesionadoLpf(pname, teamName)) continue;
        merged.add(SportmonksInjuryRow(
          playerName: pname,
          teamName: teamName,
          playerPhotoUrl: _playerPhotoFromSidelined(row),
          category: _asString(row['category']),
          typeLabel: _asString(_pick(typeMap ?? {}, ['name', 'developer_name'])),
          startDate: _asString(row['start_date']),
          endDate: _asString(row['end_date']),
          gamesMissed: _parseIntLoose(row['games_missed']),
        ));
      }
    }

    merged.sort((a, b) {
      final c = a.teamName.toLowerCase().compareTo(b.teamName.toLowerCase());
      if (c != 0) return c;
      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    });
    return merged;
  }

  /// Lesionados de la **Liga Profesional (Argentina)** según Sportmonks: equipos de la temporada con `sidelined` activo,
  /// excluyendo suspensiones obvias (palabras clave en `category` / `type`).
  Future<SportmonksLpfInjuriesSnapshot> getLigaProfesionalArgentinaInjuries({bool forceRefresh = false}) async {
    final token = _pickToken();
    if (token == null) {
      return const SportmonksLpfInjuriesSnapshot(
        rows: [],
        errorMessage:
            'Falta el token Sportmonks. Usá --dart-define=SPORTMONKS_API_TOKEN=… o dart_defines.json.',
      );
    }
    if (!forceRefresh &&
        _lpfInjuriesMem != null &&
        _lpfInjuriesMemAt != null &&
        DateTime.now().difference(_lpfInjuriesMemAt!) < _lpfInjuriesTtl) {
      return _lpfInjuriesMem!;
    }

    try {
      final seasonPick = await _resolveLpfSeasonSportmonksId(token);
      final seasonId = seasonPick.id;
      if (seasonId == null) {
        final snap = SportmonksLpfInjuriesSnapshot(rows: const [], errorMessage: seasonPick.error ?? 'Sin temporada LPF.');
        _lpfInjuriesMem = snap;
        _lpfInjuriesMemAt = DateTime.now();
        return snap;
      }

      const includeAttempts = [
        'sidelined.player;sidelined.type',
        'sidelined.player',
        'sidelined',
      ];

      List<Map<String, dynamic>> teams = [];
      String? fetchError;
      for (final include in includeAttempts) {
        final batch = await _fetchLpfSeasonTeamsWithSidelined(token, seasonId, include);
        if (batch.error != null) {
          fetchError = batch.error;
          break;
        }
        if (batch.teams.isEmpty) continue;
        teams = batch.teams;
        final trial = _injuryRowsFromSeasonTeams(teams);
        if (trial.isNotEmpty || batch.teams.any((t) => t['sidelined'] is List)) {
          break;
        }
      }

      if (fetchError != null) {
        final snap = SportmonksLpfInjuriesSnapshot(
          rows: const [],
          errorMessage: fetchError,
          resolvedSeasonId: seasonId,
        );
        _lpfInjuriesMem = snap;
        _lpfInjuriesMemAt = DateTime.now();
        return snap;
      }

      final merged = _injuryRowsFromSeasonTeams(teams);
      final snap = SportmonksLpfInjuriesSnapshot(rows: merged, resolvedSeasonId: seasonId);
      _lpfInjuriesMem = snap;
      _lpfInjuriesMemAt = DateTime.now();
      return snap;
    } on TimeoutException {
      const snap = SportmonksLpfInjuriesSnapshot(
        rows: [],
        errorMessage: 'Sportmonks tardó demasiado al cargar lesionados. Probá de nuevo.',
      );
      _lpfInjuriesMem = snap;
      _lpfInjuriesMemAt = DateTime.now();
      return snap;
    } catch (e) {
      final snap = SportmonksLpfInjuriesSnapshot(rows: const [], errorMessage: e.toString());
      _lpfInjuriesMem = snap;
      _lpfInjuriesMemAt = DateTime.now();
      return snap;
    }
  }

  /// Busca por nombre en Sportmonks y arma el snapshot del **primer** resultado de la API.
  Future<SportmonksPlayerMarketSnapshot> searchPlayerByName(String nombreJugador) async {
    final token = _pickToken();
    if (token == null) {
      return const SportmonksPlayerMarketSnapshot(
        errorMessage:
            'Falta el token Sportmonks. En terminal: --dart-define=SPORTMONKS_API_TOKEN=… '
            'o --dart-define-from-file=dart_defines.json (copiá dart_defines.example.json). '
            'En Cursor: ejecutá "hdf_stats (con Sportmonks)".',
      );
    }
    final name = nombreJugador.trim();
    if (name.isEmpty) {
      return const SportmonksPlayerMarketSnapshot(errorMessage: 'Nombre vacío');
    }

    try {
      var search = await _searchPlayersFirstPage(name, token);
      if (search['ok'] != true) {
        return SportmonksPlayerMarketSnapshot(
          errorMessage: '${search['error'] ?? 'Error en búsqueda Sportmonks'}',
        );
      }
      var players = List<Map<String, dynamic>>.from(search['players'] as List? ?? []);
      if (players.isEmpty) {
        final fb = _searchFallbackQuery(name);
        if (fb != null && fb.isNotEmpty) {
          search = await _searchPlayersFirstPage(fb, token);
          if (search['ok'] != true) {
            return SportmonksPlayerMarketSnapshot(
              errorMessage: '${search['error'] ?? 'Error en búsqueda Sportmonks'}',
            );
          }
          players = List<Map<String, dynamic>>.from(search['players'] as List? ?? []);
        }
      }
      if (players.isEmpty) {
        return const SportmonksPlayerMarketSnapshot(errorMessage: 'Sin resultados en Sportmonks');
      }
      final picked = _pickBestPlayerRow(players, name) ?? players.first;
      final idVal = picked['id'];
      final idStr = idVal?.toString();
      if (idStr == null || idStr.isEmpty) {
        return const SportmonksPlayerMarketSnapshot(errorMessage: 'Respuesta inválida (sin id)');
      }

      final displayName =
          _asString(_pick(picked, ['display_name', 'name', 'common_name'])) ?? name;

      Future<Map<String, dynamic>> safeContract() async {
        try {
          return await _fetchPlayerContractBundle(idStr, token);
        } catch (e) {
          return {'ok': false, 'error': e.toString()};
        }
      }

      Future<Map<String, dynamic>> safeTransfers() async {
        try {
          return await _fetchTransfersByPlayer(idStr, token);
        } catch (e) {
          return {
            'ok': false,
            'error': e.toString(),
            'lines': <SportmonksTransferLine>[],
            'sortedRaw': <Map<String, dynamic>>[],
          };
        }
      }

      final pair = await Future.wait([safeContract(), safeTransfers()]);
      final contractWrap = pair[0];
      final transfersWrap = pair[1];

      if (contractWrap['ok'] != true && transfersWrap['ok'] != true) {
        final e1 = contractWrap['error']?.toString() ?? '';
        final e2 = transfersWrap['error']?.toString() ?? '';
        return SportmonksPlayerMarketSnapshot(
          errorMessage: 'Sportmonks: no se pudo cargar contrato ni transferencias.\n$e1\n$e2',
        );
      }

      var contratoHasta = contractWrap['ok'] == true ? contractWrap['contratoHasta'] as String? : null;
      if (contratoHasta == null) {
        final hintsRaw = contractWrap['ok'] == true ? contractWrap['teamIdsHint'] : null;
        final teamIdsHint = hintsRaw is List
            ? hintsRaw.map(_parseIntLoose).whereType<int>().toList()
            : <int>[];
        final sortedRaw = <Map<String, dynamic>>[];
        if (transfersWrap['ok'] == true) {
          final rawList = transfersWrap['sortedRaw'];
          if (rawList is List) {
            for (final e in rawList) {
              if (e is Map<String, dynamic>) {
                sortedRaw.add(e);
              } else if (e is Map) {
                sortedRaw.add(Map<String, dynamic>.from(e));
              }
            }
          }
        }
        if (teamIdsHint.isNotEmpty || sortedRaw.isNotEmpty) {
          contratoHasta = await _trySquadContractFallback(idStr, token, teamIdsHint, sortedRaw);
        }
      }
      final contractRaw = contratoHasta;
      final contractUntil = _parseIsoDate(contractRaw);
      final contractStatus = contractStatusFromEndDate(contractUntil);
      final contractUntilFormatted = formatContractMonthYear(contractUntil);

      final transfers = transfersWrap['ok'] == true
          ? List<SportmonksTransferLine>.from(transfersWrap['lines'] as List? ?? const <SportmonksTransferLine>[])
          : <SportmonksTransferLine>[];

      final mvRaw = _extractMarketValueRaw(picked);
      final mvFmt = mvRaw != null ? formatMarketValueCompactEur(mvRaw) : '—';

      return SportmonksPlayerMarketSnapshot(
        data: SportmonksPlayerMarketData(
          sportmonksPlayerId: idStr,
          displayName: displayName,
          marketValue: mvRaw,
          marketValueFormatted: mvFmt,
          contractUntil: contractUntil,
          contractUntilFormatted: contractUntilFormatted,
          contractStatus: contractStatus,
          transfers: transfers,
        ),
      );
    } on TimeoutException {
      return const SportmonksPlayerMarketSnapshot(
        errorMessage:
            'Sportmonks tardó demasiado (servidor o red lenta). Probá de nuevo en unos segundos.',
      );
    } catch (e) {
      return SportmonksPlayerMarketSnapshot(errorMessage: e.toString());
    }
  }

  static bool get hasConfiguredToken => _pickToken() != null;

  /// Carrera y perfil en el mismo formato que [ApiService.getPlayerCareerSnapshot].
  Future<Map<String, dynamic>?> fetchPlayerCareerSnapshot({
    required String playerName,
    String? clubTeamNameHint,
    int? clubApiFootballTeamId,
  }) async {
    final token = _pickToken();
    if (token == null) return null;
    final name = playerName.trim();
    if (name.isEmpty) return null;

    try {
      final idStr = await _resolveSportmonksPlayerId(
        name,
        token,
        clubTeamNameHint: clubTeamNameHint,
        apiFootballTeamId: clubApiFootballTeamId,
      );
      if (idStr == null) return null;

      final clubSmId = clubApiFootballTeamId != null && clubApiFootballTeamId > 0
          ? await sportmonksTeamIdForApiFootball(
              clubApiFootballTeamId,
              clubTeamNameHint ?? primaryAliasForApiFootballTeam(clubApiFootballTeamId) ?? '',
            )
          : null;

      final key = _cacheKey('profileCareer', '$idStr|${clubSmId ?? 0}');
      if (_cache.containsKey(key)) {
        return Map<String, dynamic>.from(_cache[key]! as Map<String, dynamic>);
      }

      final uri = Uri.parse('$_baseUrl/players/$idStr').replace(queryParameters: {
        'api_token': token.trim(),
        'include':
            'statistics.details.type;statistics.season.league;statistics.team;teams.team;nationality;country;position;detailedPosition',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) return null;
      final root = _asMap(json.decode(res.body));
      if (_apiErrorsPresent(root)) return null;
      final player = _unwrapPlayer(root?['data']);
      if (player == null) return null;

      var mapped = _mapPlayerCareerFromSportmonks(
        player,
        clubTeamNameHint: clubTeamNameHint,
        clubSportmonksTeamId: clubSmId,
      );

      final transfersWrap = await _fetchTransfersByPlayer(idStr, token);
      if (transfersWrap['ok'] == true) {
        final sortedRaw = List<Map<String, dynamic>>.from(
          transfersWrap['sortedRaw'] as List? ?? const [],
        );
        final fromTransfers = _clubesHistorialFromTransfers(sortedRaw);
        final mergedHist = _mergeClubHistorialLists(
          List<Map<String, dynamic>>.from(mapped['clubesHistorial'] as List? ?? []),
          fromTransfers,
        );
        mapped = Map<String, dynamic>.from(mapped);
        mapped['clubesHistorial'] = mergedHist;
      }

      _cache[key] = mapped;
      return Map<String, dynamic>.from(mapped);
    } catch (_) {
      return null;
    }
  }

  static bool _statRowMatchesClub(
    Map<String, dynamic> statRow, {
    int? clubSportmonksTeamId,
    required String clubHintNorm,
  }) {
    final tm = _asMap(statRow['team']);
    if (tm == null) return false;
    final tid = _parseIntLoose(tm['id']);
    if (clubSportmonksTeamId != null &&
        clubSportmonksTeamId > 0 &&
        tid != null &&
        tid == clubSportmonksTeamId) {
      return true;
    }
    if (clubHintNorm.isEmpty) return false;
    final tnorm = _normTeamKey(_teamNameFrom(tm) ?? '');
    if (tnorm.isEmpty) return false;
    return tnorm == clubHintNorm;
  }

  Future<Map<String, dynamic>?> fetchClubActualExcluyendoSeleccion({
    required String playerName,
    required String excludeNationalTeamName,
  }) async {
    final token = _pickToken();
    if (token == null) return null;
    final idStr = await _resolveSportmonksPlayerId(playerName.trim(), token);
    if (idStr == null) return null;

    try {
      final excl = excludeNationalTeamName.trim().toLowerCase();

      final transfersWrap = await _fetchTransfersByPlayer(idStr, token);
      if (transfersWrap['ok'] == true) {
        final sortedRaw = List<Map<String, dynamic>>.from(
          transfersWrap['sortedRaw'] as List? ?? const [],
        );
        for (final t in sortedRaw) {
          final toTeam = _asMap(t['toTeam']);
          if (toTeam == null) continue;
          final tname = (_teamNameFrom(toTeam) ?? '').toLowerCase();
          if (tname.isEmpty) continue;
          if (_looksLikeNationalTeamName(tname)) continue;
          if (excl.isNotEmpty &&
              (tname == excl || tname.contains(excl) || excl.contains(tname))) {
            continue;
          }
          final dt = _parseIsoDate(_asString(t['date']));
          return {
            'id': _parseIntLoose(toTeam['id']) ?? 0,
            'nombre': _teamNameFrom(toTeam) ?? '',
            'logo': _teamLogoFrom(toTeam),
            'temporada': dt?.year ?? DateTime.now().year,
          };
        }
      }

      final uri = Uri.parse('$_baseUrl/players/$idStr').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'teams.team;statistics.season.league',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) return null;
      final player = _unwrapPlayer(_asMap(json.decode(res.body))?['data']);
      if (player == null) return null;

      final teams = player['teams'];
      var bestYear = 0;
      Map<String, dynamic>? best;

      if (teams is List) {
        for (final row in teams) {
          final m = _asMap(row);
          if (m == null) continue;
          final tm = _asMap(m['team']);
          if (tm == null) continue;
          final tname = (_teamNameFrom(tm) ?? '').toLowerCase();
          if (tname.isEmpty) continue;
          if (excl.isNotEmpty && (tname == excl || tname.contains(excl) || excl.contains(tname))) {
            continue;
          }
          if (_looksLikeNationalTeamName(tname)) continue;
          final y = _yearFromTeamRow(m);
          if (y > bestYear) {
            bestYear = y;
            best = {
              'id': _parseIntLoose(tm['id']) ?? 0,
              'nombre': _teamNameFrom(tm) ?? '',
              'logo': _teamLogoFrom(tm),
              'temporada': y,
            };
          }
        }
      }

      if (best != null) return best;

      final stats = player['statistics'];
      if (stats is List) {
        for (final raw in stats) {
          final st = _asMap(raw);
          if (st == null || _statRowIsNational(st)) continue;
          final tm = _asMap(st['team']);
          final tname = (_teamNameFrom(tm) ?? '').toLowerCase();
          if (tname.isEmpty || _looksLikeNationalTeamName(tname)) continue;
          if (excl.isNotEmpty &&
              (tname == excl || tname.contains(excl) || excl.contains(tname))) {
            continue;
          }
          final season = _asMap(st['season']);
          final y = _parseIntLoose(season?['name']) ?? _parseIntLoose(season?['id']) ?? 0;
          if (y > bestYear) {
            bestYear = y;
            best = {
              'id': _parseIntLoose(tm?['id']) ?? 0,
              'nombre': _teamNameFrom(tm) ?? '',
              'logo': _teamLogoFrom(tm),
              'temporada': y,
            };
          }
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> fetchLpfGoleadoresApiFormat() async {
    return _fetchLpfTopscorersApiFormat(208, statKey: 'goals');
  }

  Future<List<Map<String, dynamic>>?> fetchLpfAsistenciasApiFormat() async {
    return _fetchLpfTopscorersApiFormat(209, statKey: 'assists');
  }

  Future<List<dynamic>?> fetchPlantillaClubApiFormat(
    String teamName, {
    int? apiFootballTeamId,
  }) async {
    final token = _pickToken();
    if (token == null) return null;
    final name = teamName.trim();
    if (name.isEmpty) return null;

    final seasonId = await _lpfSeasonIdForPlayers(token);
    if (seasonId == null) return null;

    final rawApiId = apiFootballTeamId ?? 0;
    final apiId = rawApiId > 0 ? reconcileLpfApiFootballTeamId(rawApiId, name) : 0;
    int? smTeamId;
    if (apiId > 0) {
      smTeamId = _lpfHardcodedSportmonksTeamId[apiId] ??
          await sportmonksTeamIdForApiFootball(apiId, name);
    }
    smTeamId ??= await _resolveLpfSportmonksTeamId(
      name,
      token,
      apiFootballTeamId: apiId > 0 ? apiId : null,
      seasonId: seasonId,
    );
    if (smTeamId == null) return null;

    final key = _cacheKey('squadApiFmt', '${apiId > 0 ? apiId : 'n'}|$smTeamId|$seasonId');
    if (_cache.containsKey(key)) {
      return List<dynamic>.from(_cache[key]! as List);
    }

    try {
      final data = await _fetchSquadDataForLpfTeam(token, seasonId, smTeamId);
      if (data == null) return null;

      final out = <dynamic>[];
      for (final raw in data) {
        final row = _asMap(raw);
        if (row == null) continue;
        final rowTeamId = _parseIntLoose(row['team_id']) ??
            _parseIntLoose(_asMap(row['team'])?['id']);
        if (rowTeamId != null && rowTeamId != smTeamId) continue;
        final pl = _asMap(row['player']);
        if (pl == null) continue;
        final smPlayerId = _parseIntLoose(pl['id']) ?? 0;
        final display = _asString(_pick(pl, ['display_name', 'name', 'common_name'])) ?? '—';
        final nat = _asMap(pl['nationality']);
        final pos = _asMap(pl['position']);
        final posName = _asString(pos?['name']) ?? 'Attacker';
        final posApi = _mapPositionToApiFootball(posName);
        final dorsal = _parseIntLoose(row['jersey_number']) ?? _parseIntLoose(row['number']) ?? 0;
        final details = row['details'];
        final pj = _sumDetail(details, const [321]);
        final goles = _sumDetail(details, const [52]);
        final asist = _sumDetail(details, const [79]);
        final dob = _asString(pl['date_of_birth']);
        final edad = _ageYearsFromBirthString(dob)?.round();

        out.add({
          'player': {
            'id': smPlayerId,
            'name': display,
            'photo': _asString(pl['image_path']) ?? '',
            'age': edad,
            'nationality': _asString(nat?['name']) ?? '',
            'number': dorsal,
          },
          'statistics': [
            {
              'games': {
                'position': posApi,
                'number': dorsal,
                'appearences': pj,
                'appearances': pj,
                'rating': null,
              },
              'goals': {'total': goles, 'assists': asist},
            },
          ],
        });
      }
      if (out.isEmpty) return null;
      _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Sportmonks no incluye `player` anidado si falta `include=player` — sin eso el plantel queda vacío.
  Future<List<dynamic>?> _fetchSquadDataForLpfTeam(
    String token,
    int seasonId,
    int smTeamId,
  ) async {
    const includes = [
      'player.nationality;player.position;details.type',
      'player',
    ];
    final paths = [
      'squads/seasons/$seasonId/teams/$smTeamId',
      'squads/teams/$smTeamId',
    ];

    for (final path in paths) {
      for (final include in includes) {
        final qp = <String, String>{
          'api_token': token.trim(),
          'include': include,
        };
        if (path.startsWith('squads/teams/')) {
          qp['filters'] = 'playerstatisticSeasons:$seasonId';
        }
        final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: qp);
        final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
        if (res.statusCode != 200) continue;
        final root = _asMap(json.decode(res.body));
        if (_apiErrorsPresent(root)) continue;
        final data = root?['data'];
        if (data is! List || data.isEmpty) continue;
        final hasPlayer = data.any((e) => _asMap(_asMap(e)?['player']) != null);
        if (hasPlayer) return data;
      }
    }
    return null;
  }

  Future<String?> _resolveSportmonksPlayerId(
    String name,
    String token, {
    String? clubTeamNameHint,
    int? apiFootballTeamId,
  }) async {
    var search = await _searchPlayersFirstPage(name, token);
    if (search['ok'] != true) return null;
    var players = List<Map<String, dynamic>>.from(search['players'] as List? ?? []);
    if (players.isEmpty) {
      final fb = _searchFallbackQuery(name);
      if (fb != null) {
        search = await _searchPlayersFirstPage(fb, token);
        if (search['ok'] == true) {
          players = List<Map<String, dynamic>>.from(search['players'] as List? ?? []);
        }
      }
    }
    if (players.isEmpty) return null;

    final clubHint = clubTeamNameHint?.trim();
    if (players.length > 1 && (clubHint != null && clubHint.isNotEmpty || apiFootballTeamId != null)) {
      final alias = apiFootballTeamId != null
          ? primaryAliasForApiFootballTeam(apiFootballTeamId)
          : null;
      final wantClub = _normTeamKey(alias ?? clubHint ?? '');
      if (wantClub.isNotEmpty) {
        Map<String, dynamic>? byClub;
        for (final p in players) {
          final teamName = _asString(_pick(p, ['team_name', 'team', 'current_team']));
          if (teamName != null && _normTeamKey(teamName) == wantClub) {
            byClub = p;
            break;
          }
        }
        if (byClub != null) return byClub['id']?.toString();
      }
    }

    final picked = _pickBestPlayerRow(players, name) ?? players.first;
    return picked['id']?.toString();
  }

  Future<int?> _lpfSeasonIdForPlayers(String token) async {
    final r = await _resolveLpfSeasonSportmonksId(token);
    return r.id;
  }

  Future<List<Map<String, dynamic>>?> _fetchLpfTopscorersApiFormat(
    int topscorerType, {
    required String statKey,
  }) async {
    final token = _pickToken();
    if (token == null) return null;
    final seasonId = await _lpfSeasonIdForPlayers(token);
    if (seasonId == null) return null;

    final lpfTeams = await _fetchLpfSeasonTeamCatalog(token, seasonId);
    final lpfTeamIds = lpfTeams.map((t) => t.id).toSet();

    final key = _cacheKey('topscorers', '$seasonId|$topscorerType');
    if (_cache.containsKey(key)) {
      return List<Map<String, dynamic>>.from(_cache[key]! as List);
    }

    try {
      final uri = Uri.parse('$_baseUrl/topscorers/seasons/$seasonId').replace(queryParameters: {
        'api_token': token.trim(),
        'include': 'player;participant;type',
        'filters': 'seasontopscorerTypes:$topscorerType',
        'per_page': '50',
        'order': 'asc',
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
      if (res.statusCode != 200) return null;
      final root = _asMap(json.decode(res.body));
      if (_apiErrorsPresent(root)) return null;
      final data = root?['data'];
      if (data is! List) return [];

      final out = <Map<String, dynamic>>[];
      for (final raw in data) {
        final row = _asMap(raw);
        if (row == null) continue;
        final participantId = _parseIntLoose(row['participant_id']);
        if (lpfTeamIds.isNotEmpty &&
            participantId != null &&
            !lpfTeamIds.contains(participantId)) {
          continue;
        }
        final pl = _asMap(row['player']);
        if (pl == null) continue;
        final participant = _asMap(row['participant']);
        final total = _parseIntLoose(row['total']) ?? 0;
        final smId = _parseIntLoose(pl['id']) ?? 0;
        final teamName = _teamNameFrom(participant) ?? '—';
        final goalsMap = <String, dynamic>{
          'total': statKey == 'goals' ? total : 0,
          'assists': statKey == 'assists' ? total : 0,
        };
        out.add({
          'player': {
            'id': smId,
            'name': _asString(_pick(pl, ['display_name', 'name', 'common_name'])) ?? '—',
            'photo': _asString(pl['image_path']) ?? '',
          },
          'statistics': [
            {
              'team': {'name': teamName, 'logo': _teamLogoFrom(participant)},
              'goals': goalsMap,
              'games': {'appearences': 0, 'appearances': 0},
            },
          ],
        });
      }
      _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _mapPlayerCareerFromSportmonks(
    Map<String, dynamic> player, {
    String? clubTeamNameHint,
    int? clubSportmonksTeamId,
  }) {
    final nombre = _asString(_pick(player, ['display_name', 'name', 'common_name'])) ?? '';
    final foto = _asString(player['image_path']) ?? '';
    final dob = _asString(player['date_of_birth']);
    final edad = _ageYearsFromBirthString(dob)?.round();
    final nat = _asMap(player['nationality']);
    final country = _asMap(player['country']);
    final nacionalidad = _asString(nat?['name']);
    final paisNac = _asString(country?['name']);

    var pjCar = 0, gCar = 0, rCar = 0;
    var pjClub = 0, gClub = 0, rClub = 0;
    var muestras = 0;
    final clubHintNorm = _normTeamKey(clubTeamNameHint ?? '');

    final stats = player['statistics'];
    final totalSeasons = stats is List ? stats.length : 0;

    if (stats is List) {
      for (final raw in stats) {
        final st = _asMap(raw);
        if (st == null) continue;
        if (_statRowIsNational(st)) continue;
        final details = st['details'];
        final pj = _sumDetail(details, const [321]);
        final g = _sumDetail(details, const [52]);
        final r = _sumDetail(details, const [83, 85]);
        if (pj == 0 && g == 0 && r == 0) continue;
        muestras++;
        pjCar += pj;
        gCar += g;
        rCar += r;
        if (_statRowMatchesClub(
          st,
          clubSportmonksTeamId: clubSportmonksTeamId,
          clubHintNorm: clubHintNorm,
        )) {
          pjClub += pj;
          gClub += g;
          rClub += r;
        }
      }
    }

    var dorsal = 0;
    var tieneSel = false;
    var pjSelTotal = 0;
    var golesSelTotal = 0;
    final detallesSel = <String>[];

    if (stats is List) {
      for (final raw in stats) {
        final st = _asMap(raw);
        if (st == null || !_statRowIsNational(st)) continue;
        tieneSel = true;
        final league = _asMap(st['league']) ?? _asMap(_asMap(st['season'])?['league']);
        final lname = _asString(league?['name']) ?? 'Selección';
        final season = _asMap(st['season']);
        final seasonLabel = _asString(season?['name']) ?? '';
        final details = st['details'];
        final pj = _sumDetail(details, const [321]);
        final g = _sumDetail(details, const [52]);
        pjSelTotal += pj;
        golesSelTotal += g;
        if (lname.isNotEmpty) {
          detallesSel.add(pj > 0 ? '$lname ($seasonLabel) · $pj PJ' : '$lname ($seasonLabel)');
        }
      }
    }

    var clubNombre = '';
    var clubLogo = '';
    if (stats is List && (clubHintNorm.isNotEmpty || clubSportmonksTeamId != null)) {
      for (final raw in stats) {
        final st = _asMap(raw);
        if (st == null || _statRowIsNational(st)) continue;
        if (!_statRowMatchesClub(
          st,
          clubSportmonksTeamId: clubSportmonksTeamId,
          clubHintNorm: clubHintNorm,
        )) {
          continue;
        }
        final tm = _asMap(st['team']);
        clubNombre = _teamNameFrom(tm) ?? '';
        clubLogo = _teamLogoFrom(tm);
        if (clubNombre.isNotEmpty) break;
      }
    }

    final clubesHistorial = _clubesHistorialFromSportmonks(player);

    if (clubNombre.isEmpty && clubesHistorial.isNotEmpty) {
      clubNombre = (clubesHistorial.first['nombre'] as String?) ?? '';
      clubLogo = (clubesHistorial.first['logo'] as String?) ?? '';
    }

    return {
      'nombre': nombre,
      'foto': foto,
      'edad': edad,
      'nacimiento': dob,
      'nacionalidad': nacionalidad,
      'paisNacimiento': paisNac,
      'pjCarrera': pjCar,
      'golesCarrera': gCar,
      'rojasCarrera': rCar,
      'pjClub': pjClub,
      'golesClub': gClub,
      'rojasClub': rClub,
      'temporadasMuestra': muestras,
      'temporadasTotal': totalSeasons,
      'dorsal': dorsal,
      'tieneSeleccion': tieneSel,
      'seleccionDetalle': detallesSel.isNotEmpty ? detallesSel.take(5).join('\n') : null,
      'seleccionPjTotal': pjSelTotal,
      'seleccionGolesTotal': golesSelTotal,
      'clubActualNombre': clubNombre,
      'clubActualLogo': clubLogo,
      'clubesHistorial': clubesHistorial,
      'sportmonksPlayerId': player['id']?.toString(),
    };
  }

  List<Map<String, dynamic>> _clubesHistorialFromSportmonks(Map<String, dynamic> player) {
    final byKey = <String, Map<String, dynamic>>{};

    void addRow(int tid, String nombre, String logo, int y) {
      if (y <= 0 || nombre.trim().isEmpty) return;
      final key = '$tid|$y';
      byKey[key] = {'teamId': tid, 'nombre': nombre, 'logo': logo, 'anio': y};
    }

    final stats = player['statistics'];
    if (stats is List) {
      for (final raw in stats) {
        final st = _asMap(raw);
        if (st == null || _statRowIsNational(st)) continue;
        final tm = _asMap(st['team']);
        if (tm == null) continue;
        final tid = _parseIntLoose(tm['id']) ?? 0;
        final nombre = _teamNameFrom(tm) ?? '';
        final logo = _teamLogoFrom(tm);
        final season = _asMap(st['season']);
        var y = _parseIntLoose(season?['name']);
        if (y == null || y < 1900) {
          y = _yearFromTeamRow(st);
        }
        if (y != null && y > 0) addRow(tid, nombre, logo, y);
      }
    }

    final teams = player['teams'];
    if (teams is List) {
      for (final raw in teams) {
        final m = _asMap(raw);
        if (m == null) continue;
        final tm = _asMap(m['team']);
        if (tm == null) continue;
        final tid = _parseIntLoose(tm['id']) ?? 0;
        final nombre = _teamNameFrom(tm) ?? '';
        final logo = _teamLogoFrom(tm);
        final y = _yearFromTeamRow(m);
        addRow(tid, nombre, logo, y);
      }
    }

    final rows = byKey.values.toList();
    rows.sort((a, b) => (b['anio'] as int).compareTo(a['anio'] as int));
    return rows;
  }

  static List<Map<String, dynamic>> _clubesHistorialFromTransfers(
    List<Map<String, dynamic>> transfers,
  ) {
    final byKey = <String, Map<String, dynamic>>{};

    void addTeam(Map<String, dynamic>? tm, int year) {
      if (year <= 0) return;
      final tid = _parseIntLoose(tm?['id']) ?? 0;
      final nombre = _teamNameFrom(tm) ?? '';
      if (nombre.trim().isEmpty) return;
      final logo = _teamLogoFrom(tm);
      byKey['$tid|$year'] = {
        'teamId': tid,
        'nombre': nombre,
        'logo': logo,
        'anio': year,
      };
    }

    for (final t in transfers) {
      final dt = _parseIsoDate(_asString(t['date']));
      final y = dt?.year ?? 0;
      addTeam(_asMap(t['fromTeam']), y);
      addTeam(_asMap(t['toTeam']), y);
    }

    final rows = byKey.values.toList();
    rows.sort((a, b) => (b['anio'] as int).compareTo(a['anio'] as int));
    return rows;
  }

  static List<Map<String, dynamic>> _mergeClubHistorialLists(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final row in [...a, ...b]) {
      final tid = row['teamId'] as int? ?? 0;
      final y = row['anio'] as int? ?? 0;
      if (y <= 0) continue;
      final nombre = (row['nombre'] as String?)?.trim() ?? '';
      if (nombre.isEmpty) continue;
      byKey['$tid|$y'] = {
        'teamId': tid,
        'nombre': nombre,
        'logo': row['logo'] as String? ?? '',
        'anio': y,
      };
    }
    final out = byKey.values.toList();
    out.sort((x, y) => (y['anio'] as int).compareTo(x['anio'] as int));
    return out;
  }

  Future<String?> _fetchVenueImageById(int venueId, String token) async {
    final key = _cacheKey('venueImg', '$venueId');
    if (_cache.containsKey(key)) {
      final hit = _cache[key];
      return hit is String ? hit : null;
    }
    try {
      final uri = Uri.parse('$_baseUrl/venues/$venueId').replace(queryParameters: {
        'api_token': token.trim(),
      });
      final res = await _httpGet(uri, token: token, timeout: _timeoutSearch);
      if (res.statusCode != 200) {
        _cache[key] = null;
        return null;
      }
      final root = _asMap(json.decode(res.body));
      final venue = _asMap(root?['data']);
      final img = _asString(venue?['image_path']) ?? _asString(venue?['image']);
      _cache[key] = img;
      return img;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }

  static int _yearFromTeamRow(Map<String, dynamic> row) {
    for (final k in ['end', 'start']) {
      final raw = _asString(row[k]);
      if (raw == null) continue;
      final d = DateTime.tryParse(raw);
      if (d != null) return d.year;
    }
    return 0;
  }

  static String _teamLogoFrom(Map<String, dynamic>? team) {
    if (team == null) return '';
    return _asString(_pick(team, ['image_path', 'logo', 'logo_path'])) ?? '';
  }

  static bool _looksLikeNationalTeamName(String tnameLower) {
    if (tnameLower.contains(' u20') ||
        tnameLower.contains(' u23') ||
        tnameLower.contains(' u21')) {
      return true;
    }
    const countries = {
      'argentina',
      'brazil',
      'uruguay',
      'chile',
      'colombia',
      'peru',
      'ecuador',
      'paraguay',
      'bolivia',
      'venezuela',
      'mexico',
      'usa',
      'united states',
      'england',
      'france',
      'germany',
      'spain',
      'italy',
      'portugal',
      'netherlands',
      'croatia',
      'belgium',
      'switzerland',
      'austria',
      'poland',
      'serbia',
      'denmark',
      'sweden',
      'norway',
      'japan',
      'korea republic',
      'south korea',
      'saudi arabia',
      'australia',
      'canada',
      'morocco',
      'senegal',
      'ghana',
      'nigeria',
      'cameroon',
      'tunisia',
      'algeria',
      'egypt',
      'iran',
      'qatar',
    };
    final t = tnameLower.trim();
    if (countries.contains(t)) return true;
    return false;
  }

  static bool _statRowIsNational(Map<String, dynamic> statRow) {
    final league = _asMap(statRow['league']) ?? _asMap(_asMap(statRow['season'])?['league']);
    final lname = (_asString(league?['name']) ?? '').toLowerCase();
    final ltype = (_asString(league?['type']) ?? '').toLowerCase();
    if (ltype.contains('national') || ltype.contains('international')) return true;
    const keys = [
      'world cup',
      'copa america',
      'copa américa',
      'euro championship',
      'uefa nations',
      'nations league',
      'africa cup',
      'asian cup',
      'gold cup',
      'wc qualification',
      'world cup - qualification',
      'olympic',
      'friendlies',
      'friendly',
      'qualification',
      'mundial',
    ];
    for (final k in keys) {
      if (lname.contains(k)) return true;
    }
    final team = _asMap(statRow['team']);
    final tname = (_asString(team?['name']) ?? '').toLowerCase();
    if (tname.endsWith(' u20') || tname.endsWith(' u23')) return true;
    return false;
  }

  static int _sumDetail(dynamic details, List<int> typeIds) {
    if (details is! List) return 0;
    var sum = 0;
    for (final d in details) {
      final m = _asMap(d);
      if (m == null) continue;
      final tid = _parseIntLoose(m['type_id']);
      if (tid == null || !typeIds.contains(tid)) continue;
      sum += _detailValueToInt(m['value']);
    }
    return sum;
  }

  static int _detailValueToInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.round();
    if (v is Map) {
      for (final k in ['total', 'goals', 'count', 'value', 'appearances']) {
        final n = _asNumLoose(v[k]);
        if (n != null) return n.round();
      }
    }
    return int.tryParse(v.toString()) ?? 0;
  }

  static String _mapPositionToApiFootball(String pos) {
    final p = pos.toLowerCase();
    if (p.contains('goal')) return 'Goalkeeper';
    if (p.contains('def')) return 'Defender';
    if (p.contains('mid')) return 'Midfielder';
    return 'Attacker';
  }

  static void clearCache() {
    _cache.clear();
    _squadInfoCache.clear();
    _lpfInjuriesMem = null;
    _lpfInjuriesMemAt = null;
    _apiFootballToSportmonksTeam = null; // fuerza remapeo si cambia temporada
  }

  /// Limpia caché de equipos/planteles (tras corregir mapeos API ↔ Sportmonks).
  static void invalidateLpfTeamMappings() {
    _apiFootballToSportmonksTeam = null;
    _cache.removeWhere((k, _) =>
        k.startsWith('lpfTeamCatalog:') ||
        k.startsWith('squadApiFmt:') ||
        k.startsWith('mundial'));
  }

  /// Tras publicar planteles definitivos del Mundial: forzar recarga desde Sportmonks/API.
  static void invalidateMundialPlantelCache() {
    _cache.removeWhere((k, _) =>
        k.startsWith('mundialSquad:') ||
        k.startsWith('mundialSelProfile:') ||
        k.startsWith('mundialTeamCatalog:'));
  }

  static void invalidatePlayer(String playerId) {
    final id = playerId.trim();
    _cache.remove(_cacheKey('playerTeams', id));
    _cache.remove(_cacheKey('transfersPlayer', id));
    _cache.remove(_cacheKey('profile', id));
  }

  /// Sportmonks `countries.id` para Argentina (filtro de señal local).
  static const int countryIdArgentina = 44;

  static final Map<String, List<String>> _tvArgentinaCache = {};
  static final Map<String, DateTime> _tvArgentinaCacheAt = {};
  static final Map<String, List<Map<String, dynamic>>> _tvFixturesByDate = {};
  static final Map<String, DateTime> _tvFixturesByDateAt = {};
  static const Duration _tvArgentinaTtl = Duration(hours: 8);

  static String _normTeamNameMatch(String raw) {
    var s = raw.toLowerCase().trim();
    const accents = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };
    for (final e in accents.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _teamTokensMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    final aw = a.split(' ').where((w) => w.length > 2);
    final bw = b.split(' ').where((w) => w.length > 2);
    for (final wa in aw) {
      for (final wb in bw) {
        if (wa == wb || wa.contains(wb) || wb.contains(wa)) return true;
      }
    }
    return false;
  }

  static List<String> _tvMatchNameVariants(String name, int? apiFootballId) {
    final out = <String>{_normTeamNameMatch(name)};
    if (apiFootballId != null) {
      final fixed = reconcileLpfApiFootballTeamId(apiFootballId, name);
      for (final alias in _lpfApiFootballAliases[fixed] ?? const []) {
        out.add(_normTeamNameMatch(alias));
      }
    }
    return out.toList();
  }

  static bool _participantMatchesVariants(
    Map<String, dynamic> participant,
    List<String> variants, {
    int? apiFootballId,
    String? teamNameForReconcile,
  }) {
    final pid = _parseIntLoose(participant['id']);
    if (pid != null && apiFootballId != null) {
      final fixed = reconcileLpfApiFootballTeamId(apiFootballId, teamNameForReconcile ?? '');
      final smId = _lpfHardcodedSportmonksTeamId[fixed];
      if (smId != null && pid == smId) return true;
    }
    if (pid != null) {
      for (final entry in _lpfHardcodedSportmonksTeamId.entries) {
        if (entry.value != pid) continue;
        final aliases = _lpfApiFootballAliases[entry.key] ?? const [];
        if (variants.any((v) => aliases.any((a) => _teamTokensMatch(_normTeamNameMatch(a), v)))) {
          return true;
        }
      }
    }
    final n = _asString(participant['name']) ?? _asString(_pick(participant, ['participant_name']));
    if (n == null) return false;
    final norm = _normTeamNameMatch(n);
    return variants.any((v) => _teamTokensMatch(norm, v));
  }

  static int? _sportmonksTeamIdFromApiFootball(int? apiFootballId, String teamName) {
    if (apiFootballId == null || apiFootballId <= 0) return null;
    final fixed = reconcileLpfApiFootballTeamId(apiFootballId, teamName);
    return _lpfHardcodedSportmonksTeamId[fixed];
  }

  static ({int? home, int? away}) _participantIdsByLocation(Map<String, dynamic> fx) {
    int? home;
    int? away;
    for (final raw in fx['participants'] as List? ?? []) {
      final p = _asMap(raw);
      if (p == null) continue;
      final pid = _parseIntLoose(p['id']);
      if (pid == null) continue;
      final meta = _asMap(p['meta']);
      final loc = _asString(meta?['location'])?.toLowerCase();
      if (loc == 'home') {
        home = pid;
      } else if (loc == 'away') {
        away = pid;
      }
    }
    return (home: home, away: away);
  }

  static bool _sportmonksFixtureMatchesTeams(
    Map<String, dynamic> fx,
    String homeName,
    String awayName, {
    int? homeApiFootballId,
    int? awayApiFootballId,
  }) {
    final smHome = _sportmonksTeamIdFromApiFootball(homeApiFootballId, homeName);
    final smAway = _sportmonksTeamIdFromApiFootball(awayApiFootballId, awayName);
    final loc = _participantIdsByLocation(fx);
    if (smHome != null &&
        smAway != null &&
        loc.home != null &&
        loc.away != null &&
        loc.home == smHome &&
        loc.away == smAway) {
      return true;
    }

    final homeVariants = _tvMatchNameVariants(homeName, homeApiFootballId);
    final awayVariants = _tvMatchNameVariants(awayName, awayApiFootballId);

    final title = _normTeamNameMatch(fx['name']?.toString() ?? '');
    if (homeVariants.any((v) => _teamTokensMatch(title, v)) &&
        awayVariants.any((v) => _teamTokensMatch(title, v))) {
      return true;
    }

    final participants = fx['participants'] as List? ?? [];
    if (participants.length < 2) return false;

    var hasH = false;
    var hasA = false;
    for (final raw in participants) {
      final p = _asMap(raw);
      if (p == null) continue;
      final meta = _asMap(p['meta']);
      final locSide = _asString(meta?['location'])?.toLowerCase();
      if (locSide == 'home' &&
          _participantMatchesVariants(
            p,
            homeVariants,
            apiFootballId: homeApiFootballId,
            teamNameForReconcile: homeName,
          )) {
        hasH = true;
      } else if (locSide == 'away' &&
          _participantMatchesVariants(
            p,
            awayVariants,
            apiFootballId: awayApiFootballId,
            teamNameForReconcile: awayName,
          )) {
        hasA = true;
      }
    }
    if (hasH && hasA) return true;

    for (final raw in participants) {
      final p = _asMap(raw);
      if (p == null) continue;
      if (!hasH &&
          _participantMatchesVariants(
            p,
            homeVariants,
            apiFootballId: homeApiFootballId,
            teamNameForReconcile: homeName,
          )) {
        hasH = true;
      }
      if (!hasA &&
          _participantMatchesVariants(
            p,
            awayVariants,
            apiFootballId: awayApiFootballId,
            teamNameForReconcile: awayName,
          )) {
        hasA = true;
      }
    }
    return hasH && hasA;
  }

  static Future<List<Map<String, dynamic>>> _fetchFixturesBetweenPages({
    required String token,
    required String fromDate,
    required String toDate,
    String? seasonFilter,
    int maxPages = 8,
  }) async {
    final fixtures = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;
    while (hasMore && page <= maxPages) {
      final params = <String, String>{
        'api_token': token.trim(),
        'include': 'participants;tvStations.tvstation;tvStations.country',
        'per_page': '50',
        'page': '$page',
      };
      if (seasonFilter != null && seasonFilter.isNotEmpty) {
        params['filters'] = seasonFilter;
      }
      final uri = Uri.parse('$_baseUrl/fixtures/between/$fromDate/$toDate')
          .replace(queryParameters: params);
      final res = await _httpGet(uri, token: token);
      if (res.statusCode == 403 || res.statusCode != 200) break;
      final root = _asMap(json.decode(res.body));
      if (root == null || _apiErrorsPresent(root)) break;
      final data = root['data'];
      if (data is List) {
        for (final raw in data) {
          final fx = _asMap(raw);
          if (fx != null) fixtures.add(fx);
        }
      }
      hasMore = _paginationHasMore(root);
      page++;
    }
    return fixtures;
  }

  static void _mergeFixturesTvUnicos(
    List<Map<String, dynamic>> dest,
    Set<int> ids,
    List<Map<String, dynamic>> src,
  ) {
    for (final fx in src) {
      final id = _parseIntLoose(fx['id']);
      if (id == null || !ids.add(id)) continue;
      dest.add(fx);
    }
  }

  /// Partidos del día con TV: prioriza **LPF** (temporada Sportmonks) y suma fecha global.
  static Future<List<Map<String, dynamic>>> _fixturesTvDelDia(
    String token,
    String dateStr,
  ) async {
    final cacheKey = 'day|v2|$dateStr';
    final cachedAt = _tvFixturesByDateAt[cacheKey];
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _tvArgentinaTtl &&
        _tvFixturesByDate.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_tvFixturesByDate[cacheKey]!);
    }

    final fixtures = <Map<String, dynamic>>[];
    final ids = <int>{};

    final seasonRes = await _resolveLpfSeasonSportmonksId(token);
    if (seasonRes.id != null) {
      final lpf = await _fetchFixturesBetweenPages(
        token: token,
        fromDate: dateStr,
        toDate: dateStr,
        seasonFilter: 'fixtureSeasons:${seasonRes.id}',
        maxPages: 6,
      );
      _mergeFixturesTvUnicos(fixtures, ids, lpf);
    }

    final global = await _fetchFixturesBetweenPages(
      token: token,
      fromDate: dateStr,
      toDate: dateStr,
      maxPages: 4,
    );
    _mergeFixturesTvUnicos(fixtures, ids, global);

    if (fixtures.isEmpty) {
      var page = 1;
      var hasMore = true;
      while (hasMore && page <= 6) {
        final uri = Uri.parse('$_baseUrl/fixtures/date/$dateStr').replace(
          queryParameters: {
            'api_token': token.trim(),
            'include': 'participants;tvStations.tvstation;tvStations.country',
            'per_page': '50',
            'page': '$page',
          },
        );
        final res = await _httpGet(uri, token: token);
        if (res.statusCode != 200) break;
        final root = _asMap(json.decode(res.body));
        if (root == null || _apiErrorsPresent(root)) break;
        final data = root['data'];
        if (data is List) {
          final batch = <Map<String, dynamic>>[];
          for (final raw in data) {
            final fx = _asMap(raw);
            if (fx != null) batch.add(fx);
          }
          _mergeFixturesTvUnicos(fixtures, ids, batch);
        }
        hasMore = _paginationHasMore(root);
        page++;
      }
    }

    _tvFixturesByDate[cacheKey] = fixtures;
    _tvFixturesByDateAt[cacheKey] = DateTime.now();
    return fixtures;
  }

  static bool _tvRowEsArgentina(Map<String, dynamic> row) {
    final countryId = _parseIntLoose(row['country_id']);
    if (countryId == countryIdArgentina) return true;
    final country = _asMap(row['country']);
    final cid = _parseIntLoose(country?['id']);
    if (cid == countryIdArgentina) return true;
    final cname = (_asString(country?['name']) ?? '').toLowerCase();
    return cname.contains('argentina');
  }

  static bool _nombreCanalArgentino(String name) {
    final n = name.toLowerCase();
    const hints = [
      'tyc',
      'espn',
      'directv',
      'telefe',
      'fox sports',
      'fox ',
      'cablevision',
      'flow',
      'pack futbol',
      'deportv',
      'vtv',
    ];
    for (final h in hints) {
      if (n.contains(h)) return true;
    }
    return false;
  }

  static List<String> _canalesTvArgentinaDesdeFixture(Map<String, dynamic> fx) {
    final canales = <String>{};
    final rows = (fx['tvstations'] ?? fx['tvStations']) as List? ?? [];
    for (final raw in rows) {
      final row = _asMap(raw);
      if (row == null) continue;

      final station = _asMap(row['tvstation']) ?? _asMap(row['tv_station']);
      var name = _asString(station?['name']) ?? _asString(row['name']);
      if (name == null || name.isEmpty) continue;

      final esAr = _tvRowEsArgentina(row) || _nombreCanalArgentino(name);
      if (!esAr) continue;

      final lower = name.toLowerCase();
      if (lower.contains('.com') && !lower.contains('tyc')) continue;
      canales.add(name.trim());
    }
    final list = canales.toList()..sort();
    return list;
  }

  /// Canales que transmiten el partido en **Argentina** (Sportmonks + filtro país 44).
  static Future<List<String>> getCanalesTvArgentina({
    required String homeName,
    required String awayName,
    String? fixtureDateIso,
    int? homeApiFootballId,
    int? awayApiFootballId,
  }) async {
    final token = _pickToken();
    if (token == null) return [];

    final dt = fixtureDateIso != null
        ? DateTime.tryParse(fixtureDateIso)?.toLocal()
        : null;
    if (dt == null) return [];

    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final cacheKey =
        'v2|$dateStr|${_normTeamNameMatch(homeName)}|${_normTeamNameMatch(awayName)}|$homeApiFootballId|$awayApiFootballId';
    final cachedAt = _tvArgentinaCacheAt[cacheKey];
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _tvArgentinaTtl &&
        _tvArgentinaCache.containsKey(cacheKey)) {
      return List<String>.from(_tvArgentinaCache[cacheKey]!);
    }

    try {
      final fixtures = await _fixturesTvDelDia(token, dateStr);

      Map<String, dynamic>? match;
      for (final fx in fixtures) {
        if (_sportmonksFixtureMatchesTeams(
          fx,
          homeName,
          awayName,
          homeApiFootballId: homeApiFootballId,
          awayApiFootballId: awayApiFootballId,
        )) {
          match = fx;
          break;
        }
      }

      var canales = match != null ? _canalesTvArgentinaDesdeFixture(match) : <String>[];

      if (canales.isEmpty && match == null) {
        final smH = _sportmonksTeamIdFromApiFootball(homeApiFootballId, homeName);
        final smA = _sportmonksTeamIdFromApiFootball(awayApiFootballId, awayName);
        if (smH != null && smA != null) {
          for (final fx in fixtures) {
            final loc = _participantIdsByLocation(fx);
            if (loc.home == smH && loc.away == smA) {
              match = fx;
              canales = _canalesTvArgentinaDesdeFixture(fx);
              break;
            }
          }
        }
      }

      _tvArgentinaCache[cacheKey] = canales;
      _tvArgentinaCacheAt[cacheKey] = DateTime.now();
      return canales;
    } catch (_) {
      return [];
    }
  }

  /// Invalida caché de TV (p. ej. tras cambiar lógica de matching).
  static void clearTvArgentinaCache() {
    _tvArgentinaCache.clear();
    _tvArgentinaCacheAt.clear();
    _tvFixturesByDate.clear();
    _tvFixturesByDateAt.clear();
  }
}
