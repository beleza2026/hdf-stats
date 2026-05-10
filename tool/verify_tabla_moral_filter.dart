// Verifica que la tabla moral solo cuente "Regular Season" y excluya play-offs.
// Uso:  $env:APISPORTS_KEY='tu_clave'; dart run tool/verify_tabla_moral_filter.dart
// O la clave se lee de lib/api_service.dart si APISPORTS_KEY no está definida (solo desarrollo local).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _base = 'https://v3.football.api-sports.io';
const _league = 128;
const _season = 2026;

Future<String> _resolveApiKey() async {
  final fromEnv = Platform.environment['APISPORTS_KEY']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final apiPath = File('lib/api_service.dart');
  if (!await apiPath.exists()) {
    stderr.writeln('Definí APISPORTS_KEY o ejecutá desde la raíz del proyecto.');
    exit(1);
  }
  final text = await apiPath.readAsString();
  final m = RegExp(r"_apiKey = '([^']+)'").firstMatch(text);
  if (m == null) exit(1);
  return m.group(1)!;
}

bool _cuentaParaMoral(Map<String, dynamic> f) {
  final round = (f['league']?['round'] as String? ?? '').trim();
  if (round.isEmpty) return false;
  final lower = round.toLowerCase();
  if (lower.contains('play-off') || lower.contains('playoff')) return false;
  if (lower.contains('round of')) return false;
  if (lower.contains('relegation') || lower.contains('descenso')) return false;
  if (round.contains('Regular Season')) return true;
  return RegExp(r'^(Apertura|Clausura) - \d+$').hasMatch(round);
}

Future<void> main() async {
  final key = await _resolveApiKey();
  final uri = Uri.parse('$_base/fixtures?league=$_league&season=$_season&status=FT');
  final res = await http.get(uri, headers: {'x-apisports-key': key});
  if (res.statusCode != 200) {
    stderr.writeln('HTTP ${res.statusCode}');
    exit(1);
  }
  final list = jsonDecode(res.body)['response'] as List;

  final byRound = <String, int>{};
  var incl = 0;
  var excl = 0;
  final exclSamples = <String>[];

  for (final raw in list) {
    final f = raw as Map<String, dynamic>;
    final status = f['fixture']?['status']?['short'] as String? ?? '';
    if (status != 'FT' && status != 'AET' && status != 'PEN') continue;

    final round = f['league']?['round'] as String? ?? '(sin round)';
    byRound[round] = (byRound[round] ?? 0) + 1;

    if (_cuentaParaMoral(f)) {
      incl++;
    } else {
      excl++;
      if (exclSamples.length < 12) {
        final home = f['teams']?['home']?['name'] ?? '?';
        final away = f['teams']?['away']?['name'] ?? '?';
        exclSamples.add('$round  |  $home vs $away');
      }
    }
  }

  stdout.writeln('Liga $_league temporada $_season — partidos finalizados (FT/AET/PEN): ${incl + excl}');
  stdout.writeln('  Incluidos en tabla moral (Regular Season): $incl');
  stdout.writeln('  Excluidos (play-offs u otras rondas):       $excl');
  stdout.writeln('');
  stdout.writeln('Desglose por valor de league.round:');
  final sorted = byRound.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final e in sorted) {
    stdout.writeln('  ${e.value.toString().padLeft(3)} ×  ${e.key}');
  }
  if (exclSamples.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Muestra de excluidos:');
    for (final s in exclSamples) {
      stdout.writeln('  • $s');
    }
  }
}
