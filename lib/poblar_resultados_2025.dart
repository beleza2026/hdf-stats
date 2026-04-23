// poblar_resultados_2025.dart
// Carga los fixtures finalizados de Liga Profesional 2025 (league 128)
// en Firestore → resultados_2025/fixtures
//
// USO:
//   dart run lib/poblar_resultados_2025.dart
//
// Requiere: FOOTBALL_API_KEY en variable de entorno, o hardcodeada abajo.
// El script intenta la API. Si devuelve datos, los guarda en Firestore.
// La app los lee como fallback cuando la API no devuelve datos 2025.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Configuración ─────────────────────────────────────────────────────────
const String _apiKey    = 'e41f25b1b90e5b8b8f3e3c2d1a4b5c6d2424fff'; // tu key real
const String _baseUrl   = 'https://v3.football.api-sports.io';
const int    _liga      = 128;   // Liga Profesional Argentina
const int    _season    = 2025;
// ──────────────────────────────────────────────────────────────────────────

void main() async {
  print('');
  print('╔══════════════════════════════════════════════╗');
  print('║   POBLAR RESULTADOS 2025 — MatchGol Stats   ║');
  print('╚══════════════════════════════════════════════╝');
  print('');

  // Inicializar Firebase
  await Firebase.initializeApp();
  final db = FirebaseFirestore.instance;

  // ── 1. Fetch de API-Football ──────────────────────────────────────────
  print('📡 Consultando API-Football: league=$_liga season=$_season status=FT...');
  final resp = await http.get(
    Uri.parse('$_baseUrl/fixtures?league=$_liga&season=$_season&status=FT'),
    headers: {
      'x-apisports-key': _apiKey,
      'Accept': 'application/json',
    },
  );

  if (resp.statusCode != 200) {
    print('❌ Error HTTP ${resp.statusCode}');
    exit(1);
  }

  final body    = jsonDecode(resp.body) as Map<String, dynamic>;
  final errors  = body['errors'];
  final rawList = body['response'] as List? ?? [];

  if (errors is Map && errors.isNotEmpty) {
    print('❌ API error: $errors');
    exit(1);
  }

  if (rawList.isEmpty) {
    print('⚠️  La API no devolvió fixtures para temporada 2025.');
    print('   → Esto es esperado con API-Football Pro si no tiene datos históricos.');
    print('   → Cargá los datos manualmente (ver instrucciones abajo).');
    _mostrarInstruccionesManual();
    exit(0);
  }

  print('✅ ${rawList.length} fixtures encontrados en temporada 2025.');
  print('');

  // ── 2. Transformar a formato mínimo para Firestore ────────────────────
  final fixturesMini = <Map<String, dynamic>>[];
  int errores = 0;

  for (final f in rawList) {
    try {
      final homeTeam  = f['teams']['home']  as Map<String, dynamic>;
      final awayTeam  = f['teams']['away']  as Map<String, dynamic>;
      final homeGoals = f['goals']['home']  as int?;
      final awayGoals = f['goals']['away']  as int?;
      final dateStr   = f['fixture']['date'] as String?;

      if (homeGoals == null || awayGoals == null || dateStr == null) {
        errores++;
        continue;
      }

      fixturesMini.add({
        'fecha':     dateStr,
        'homeId':    homeTeam['id'],
        'homeName':  homeTeam['name'],
        'homeLogo':  homeTeam['logo'],
        'awayId':    awayTeam['id'],
        'awayName':  awayTeam['name'],
        'awayLogo':  awayTeam['logo'],
        'homeGoals': homeGoals,
        'awayGoals': awayGoals,
      });
    } catch (e) {
      errores++;
    }
  }

  print('📦 ${fixturesMini.length} fixtures válidos (descartados: $errores)');
  print('');

  // ── 3. Preview por equipo ─────────────────────────────────────────────
  final Map<String, int> conteoEquipos = {};
  for (final m in fixturesMini) {
    conteoEquipos[m['homeName'] as String] = (conteoEquipos[m['homeName'] as String] ?? 0) + 1;
    conteoEquipos[m['awayName'] as String] = (conteoEquipos[m['awayName'] as String] ?? 0) + 1;
  }
  print('📊 Partidos por equipo:');
  final sorted = conteoEquipos.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final e in sorted) {
    print('   ${e.key.padRight(30)} ${e.value} partidos');
  }
  print('');

  // ── 4. Guardar en Firestore ───────────────────────────────────────────
  print('💾 Guardando en Firestore → resultados_2025/fixtures ...');
  await db.collection('resultados_2025').doc('fixtures').set({
    'temporada': _season,
    'liga':      _liga,
    'total':     fixturesMini.length,
    'actualizadoEn': FieldValue.serverTimestamp(),
    'data':      fixturesMini,
  });

  print('');
  print('╔══════════════════════════════════════════════╗');
  print('║   ✅  LISTO — ${fixturesMini.length} fixtures guardados          ║');
  print('╚══════════════════════════════════════════════╝');
  print('');
  print('La app ahora usará estos datos como temporada anterior para rachas.');
  print('No necesitás correr este script otra vez salvo que quieras actualizar.');
}

// ── Instrucciones para carga manual si la API falla ──────────────────────
void _mostrarInstruccionesManual() {
  print('');
  print('══ CARGA MANUAL (si la API no devuelve datos) ══');
  print('');
  print('Opción A: Desde la consola Firebase → Firestore:');
  print('  Colección: resultados_2025');
  print('  Documento: fixtures');
  print('  Campo "data": array de objetos con esta estructura:');
  print('  {');
  print('    "fecha":     "2025-11-30T21:00:00+00:00",');
  print('    "homeId":    435,');
  print('    "homeName":  "River Plate",');
  print('    "homeLogo":  "https://media.api-sports.io/football/teams/435.png",');
  print('    "awayId":    442,');
  print('    "awayName":  "Boca Juniors",');
  print('    "awayLogo":  "https://media.api-sports.io/football/teams/442.png",');
  print('    "homeGoals": 2,');
  print('    "awayGoals": 1');
  print('  }');
  print('');
  print('Opción B: Editar poblar_resultados_2025.dart y agregar un bloque');
  print('          hardcodeado con los últimos 10 partidos de cada equipo.');
}
