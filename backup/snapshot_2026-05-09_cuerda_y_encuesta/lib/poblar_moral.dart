// SCRIPT DEFINITIVO: Poblar Tabla Moral con algoritmo completo
// dart run lib/poblar_moral.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
const String _baseUrl = 'https://v3.football.api-sports.io';
const int _liga = 128;
const int _season = 2026;
const String _projectId = 'hdf-stats';

Map<String, String> get _apiHeaders => {'x-apisports-key': _apiKey};

void main(List<String> args) async {
  final soloUltima = args.contains('--ultima');

  if (soloUltima) {
    print('=== POBLAR TABLA MORAL - ÚLTIMA FECHA ===\n');
  } else {
    print('=== POBLAR TABLA MORAL - COMPLETO ===\n');
    print('TIP: usá --ultima para correr solo la última fecha (más rápido)\n');
  }

  // 1. Traer fixtures
  print('Trayendo fixtures...');
  final fixtureResp = await http.get(
    Uri.parse('$_baseUrl/fixtures?league=$_liga&season=$_season'),
    headers: _apiHeaders,
  );
  if (fixtureResp.statusCode != 200) {
    print('ERROR fixtures: ${fixtureResp.statusCode}');
    exit(1);
  }

  final allFixtures = jsonDecode(fixtureResp.body)['response'] as List;
  final todosJugados = allFixtures.where((f) {
    final s = f['fixture']['status']['short'];
    return s == 'FT' || s == 'AET' || s == 'PEN';
  }).toList();

  List jugados;
  if (soloUltima) {
    int maxRound = 0;
    for (var f in todosJugados) {
      final round = f['league']['round'] as String? ?? '';
      if (round.contains('Regular Season')) {
        final parts = round.split('- ');
        if (parts.length == 2) {
          final n = int.tryParse(parts[1].trim()) ?? 0;
          if (n > maxRound) maxRound = n;
        }
      }
    }
    final roundStr = 'Regular Season - $maxRound';
    jugados = todosJugados.where((f) => f['league']['round'] == roundStr).toList();
    print('Última fecha: Fecha $maxRound — ${jugados.length} partidos\n');
  } else {
    jugados = todosJugados;
  }

  print('${jugados.length} partidos a procesar');
  print('Procesando con algoritmo moral completo...\n');

  int ok = 0;
  int errores = 0;
  int sinStats = 0;

  for (int i = 0; i < jugados.length; i++) {
    final f = jugados[i];
    final fId = f['fixture']['id'] as int;
    final homeId = (f['teams']['home']['id'] as int).toString();
    final awayId = (f['teams']['away']['id'] as int).toString();
    final homeName = f['teams']['home']['name'] as String;
    final awayName = f['teams']['away']['name'] as String;
    final glLocal = (f['goals']['home'] as num?)?.toInt() ?? 0;
    final glVisit = (f['goals']['away'] as num?)?.toInt() ?? 0;

    int moralL = glLocal;
    int moralV = glVisit;

    // 2. Traer stats del partido para algoritmo completo
    final statsResp = await http.get(
      Uri.parse('$_baseUrl/fixtures/statistics?fixture=$fId'),
      headers: _apiHeaders,
    );

    if (statsResp.statusCode == 200) {
      final statsList = jsonDecode(statsResp.body)['response'] as List;
      if (statsList.length >= 2) {
        double posLocal = 50, posVisit = 50;
        int tirosLocal = 0, tirosVisit = 0;
        int cornersLocal = 0, cornersVisit = 0;

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

        // Algoritmo moral exacto
        final difPos = posLocal - posVisit;
        final difTiros = tirosLocal - tirosVisit;
        final difCorners = cornersLocal - cornersVisit;
        double dominio = 0;
        if (difPos.abs() > 25) dominio += difPos > 0 ? 1.5 : -1.5;
        else if (difPos.abs() > 15) dominio += difPos > 0 ? 1.0 : -1.0;
        if (difTiros.abs() >= 3) dominio += difTiros > 0 ? 1.0 : -1.0;
        else if (difTiros.abs() >= 1) dominio += difTiros > 0 ? 0.5 : -0.5;
        if (difCorners.abs() >= 5) dominio += difCorners > 0 ? 0.5 : -0.5;

        final ajuste = dominio.round().clamp(-1, 1);
        moralL += ajuste;
        moralV -= ajuste;
        if (moralL < 0) moralL = 0;
        if (moralV < 0) moralV = 0;

        final dif = (glLocal - glVisit).abs();
        if (dif == 1) {
          if (glLocal > glVisit && moralL < moralV) moralL = moralV;
          if (glVisit > glLocal && moralV < moralL) moralV = moralL;
        }
        if (glLocal == glVisit) {
          if (moralL > moralV + 1) moralL = moralV + 1;
          if (moralV > moralL + 1) moralV = moralL + 1;
        }
      }
    } else if (statsResp.statusCode == 429) {
      print('  Rate limit en $fId — esperando 5s...');
      await Future.delayed(const Duration(seconds: 5));
      sinStats++;
    } else {
      sinStats++;
    }

    // 3. Guardar en Firestore via REST
    final docUrl = 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/resultados_morales/$fId';

    final resp = await http.patch(
      Uri.parse('$docUrl'
        '?updateMask.fieldPaths=fixtureId'
        '&updateMask.fieldPaths=homeId'
        '&updateMask.fieldPaths=awayId'
        '&updateMask.fieldPaths=homeNombre'
        '&updateMask.fieldPaths=awayNombre'
        '&updateMask.fieldPaths=moralLocal'
        '&updateMask.fieldPaths=moralVisitante'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'fixtureId': {'integerValue': '$fId'},
          'homeId': {'stringValue': homeId},
          'awayId': {'stringValue': awayId},
          'homeNombre': {'stringValue': homeName},
          'awayNombre': {'stringValue': awayName},
          'moralLocal': {'integerValue': '$moralL'},
          'moralVisitante': {'integerValue': '$moralV'},
        }
      }),
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      // Verificar homeId guardado
      final saved = jsonDecode(resp.body);
      final savedHome = saved['fields']?['homeId']?['stringValue'] ?? '';
      if (savedHome == homeId) {
        ok++;
        if (i < 3 || i % 30 == 0) {
          print('[$i/${jugados.length}] $homeName $moralL - $moralV $awayName');
        }
      } else {
        print('[$i] ERROR homeId: guardado=$savedHome esperado=$homeId');
        errores++;
      }
    } else {
      errores++;
      print('[$i] Firestore ERROR ${resp.statusCode}');
    }

    // Delay para no superar rate limit de API-Football
    await Future.delayed(const Duration(milliseconds: 1200));
  }

  print('\n=== RESULTADO ===');
  print('OK: $ok partidos con stats completas');
  print('Sin stats (solo goles): $sinStats');
  print('Errores Firestore: $errores');
  if (errores == 0) {
    print('\nListo! La Tabla Moral ahora tiene el algoritmo completo.');
  }
}
