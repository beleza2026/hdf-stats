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

/// Cliente [Sportmonks Football API v3](https://docs.sportmonks.com/v3/welcome/welcome).
///
/// Token: compilación con **una** de estas opciones:
/// - `--dart-define=SPORTMONKS_API_TOKEN=tu_token`
/// - `--dart-define-from-file=dart_defines.json` (copiá `dart_defines.example.json` → `dart_defines.json`; está en `.gitignore`)
///
/// Base opcional: `--dart-define=SPORTMONKS_API_BASE_URL=https://api.sportmonks.com/v3/football`
class SportmonksService {
  SportmonksService();

  static const String _defaultBase = 'https://api.sportmonks.com/v3/football';

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

  /// Transferencias por endpoint dedicado (más liviano que embebido en el jugador).
  static Future<Map<String, dynamic>> _fetchTransfersByPlayer(String id, String token) async {
    final key = _cacheKey('transfersPlayer', id);
    if (_cache.containsKey(key)) return _snapshot(_cache[key]! as Map<String, dynamic>);

    final uri = Uri.parse('$_baseUrl/transfers/players/$id').replace(queryParameters: {
      'api_token': token.trim(),
      'include': 'fromTeam;toTeam',
      'per_page': '20',
      'order': 'desc',
    });
    final res = await _httpGet(uri, token: token, timeout: _timeoutProfile);
    if (res.statusCode != 200) {
      return {
        'ok': false,
        'error': _userFacingHttpError(res.statusCode),
        'statusCode': res.statusCode,
        'lines': <SportmonksTransferLine>[],
        'sortedRaw': <Map<String, dynamic>>[],
      };
    }
    final decoded = json.decode(res.body);
    final root = _asMap(decoded);
    final data = root == null ? null : root['data'];
    final list = data is List ? data : const <dynamic>[];
    final sortedRaw = _sortTransferMapsDesc(list);
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

  static Future<int?> _sportmonksTeamIdFromSearch(String name, String token) async {
    final q = name.trim();
    if (q.isEmpty) return null;
    final enc = Uri.encodeComponent(q);
    final key = _cacheKey('teamSearch', enc);
    if (_cache.containsKey(key)) {
      final hit = _cache[key];
      if (hit is int) return hit;
      if (hit == null) return null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/teams/search/$enc').replace(queryParameters: {
        'api_token': token.trim(),
        'per_page': '8',
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
      final first = _asMap(data.first);
      final id = _parseIntLoose(first?['id']);
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

    final smId = await _sportmonksTeamIdFromSearch(name, token);
    if (smId == null) {
      _squadInfoCache[memKey] = null;
      return null;
    }

    final info = await _aggregateSquadInfo(smId, token);
    _squadInfoCache[memKey] = info;
    return info;
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

  static void clearCache() {
    _cache.clear();
    _squadInfoCache.clear();
  }

  static void invalidatePlayer(String playerId) {
    final id = playerId.trim();
    _cache.remove(_cacheKey('playerTeams', id));
    _cache.remove(_cacheKey('transfersPlayer', id));
    _cache.remove(_cacheKey('profile', id));
  }
}
