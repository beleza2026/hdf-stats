// ignore_for_file: dangling_library_doc_comments
/// Ejemplo: encuesta interactiva + datos en Google Sheets (sin Firestore).
///
/// ## Encuesta (como la de Racing / Costas)
/// Pregunta y 4 opciones con emoji; al tocar, se hace POST a un Apps Script que
/// agrega una fila: [fecha, opción_id, etiqueta, id_anónimo_app].
///
/// ## Pasos en Google (una sola vez)
/// 1. Creá una hoja de cálculo nueva (vacía).
/// 2. Menú **Extensiones → Apps Script**. Pegá este código y guardá:
///
/// ```javascript
/// function doPost(e) {
///   try {
///     var body = JSON.parse(e.postData.contents);
///     var sh = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
///     if (sh.getLastRow() === 0) {
///       sh.appendRow(['timestamp', 'opcion_id', 'opcion_texto', 'votante_app_id']);
///     }
///     sh.appendRow([
///       new Date().toISOString(),
///       body.opcion_id || '',
///       body.opcion_texto || '',
///       body.votante_id || '',
///     ]);
///     return ContentService
///       .createTextOutput(JSON.stringify({ ok: true }))
///       .setMimeType(ContentService.MimeType.JSON);
///   } catch (err) {
///     return ContentService
///       .createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
///       .setMimeType(ContentService.MimeType.JSON);
///   }
/// }
/// ```
///
/// 3. **Implementar → Nueva implementación → Tipo: aplicación web**
///    - Ejecutar como: **Yo**
///    - Quién tiene acceso: **Cualquiera** (o solo usuarios de tu dominio si preferís)
/// 4. Copiá la **URL de la aplicación web** (termina en `/exec`) y pasala a
///    [EncuestaEjemploSheet.appsScriptUrl] abajo, o al constructor del widget.
///
/// **Seguridad:** cualquiera con la URL puede enviar filas; para producción
/// conviene token secreto en el body, límite por IP en Script, o un backend propio.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// URL de la implementación web del Apps Script (reemplazá por la tuya).
const String kEncuestaAppsScriptUrlPlaceholder = 'https://script.google.com/macros/s/XXXX/exec';

class EncuestaEjemploSheet extends StatefulWidget {
  const EncuestaEjemploSheet({
    super.key,
    this.appsScriptUrl = kEncuestaAppsScriptUrlPlaceholder,
    this.escudoUrl = 'https://media.api-sports.io/football/teams/436.png',
  });

  final String appsScriptUrl;
  final String escudoUrl;

  @override
  State<EncuestaEjemploSheet> createState() => _EncuestaEjemploSheetState();
}

class _EncuestaEjemploSheetState extends State<EncuestaEjemploSheet> {
  static const _pregunta = '¿Debe seguir Gustavo Costas como técnico de Racing?';
  static const _opciones = <Map<String, String>>[
    {'id': 'si', 'emoji': '👍', 'texto': 'Sí, que siga'},
    {'id': 'no', 'emoji': '👎', 'texto': 'No, hay que cambiar'},
    {'id': 'depende', 'emoji': '🤔', 'texto': 'Depende de los resultados'},
    {'id': 'otro', 'emoji': '💬', 'texto': 'Otro / no sé'},
  ];

  bool _enviando = false;
  String? _error;
  bool _yaVoto = false;

  @override
  void initState() {
    super.initState();
    _cargarEstadoVoto();
  }

  Future<void> _cargarEstadoVoto() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _yaVoto = p.getBool('encuesta_costas_voto_2026') ?? false);
  }

  Future<String> _votanteId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('encuesta_anon_id');
    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await p.setString('encuesta_anon_id', id);
    }
    return id;
  }

  Future<void> _votar(String id, String texto) async {
    if (widget.appsScriptUrl.contains('XXXX')) {
      setState(() => _error = 'Configurá la URL del Apps Script en encuesta_ejemplo_sheet.dart');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final vid = await _votanteId();
      final uri = Uri.parse(widget.appsScriptUrl);
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'opcion_id': id,
              'opcion_texto': texto,
              'votante_id': vid,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>?;
      if (map?['ok'] != true) throw Exception(map?['error'] ?? res.body);
      final p = await SharedPreferences.getInstance();
      await p.setBool('encuesta_costas_voto_2026', true);
      if (!mounted) return;
      setState(() {
        _yaVoto = true;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'No se pudo enviar el voto. Revisá la URL y el despliegue del script.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text('ENCUESTA', style: TextStyle(fontSize: 14, letterSpacing: 1.2)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.escudoUrl.isNotEmpty)
            Center(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.5), width: 2),
                ),
                child: ClipOval(
                  child: Image.network(
                    widget.escudoUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            _pregunta,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tu voto se guarda en una hoja de cálculo (ejemplo técnico).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 24),
          if (_yaVoto)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '¡Gracias! Ya registramos tu respuesta.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF00C853), fontSize: 15),
              ),
            )
          else
            ..._opciones.map((op) {
              final id = op['id']!;
              final emoji = op['emoji']!;
              final texto = op['texto']!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _enviando ? null : () => _votar(id, '$emoji $texto'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              texto,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (_enviando) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF00C853)))),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
