import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MonitorBajasWidget extends StatefulWidget {
  const MonitorBajasWidget({Key? key}) : super(key: key);
  @override
  State<MonitorBajasWidget> createState() => _MonitorBajasWidgetState();
}

class _MonitorBajasWidgetState extends State<MonitorBajasWidget> {
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const String _apiKey = 'e41f25b121cc73bca63f00b362424fff';
  static const int _leagueId = 128;
  static const int _season = 2026;
  static const Map<String, String> _headers = {'x-apisports-key': _apiKey};
  List<Map<String, dynamic>> _alFilo = [];
  List<Map<String, dynamic>> _suspendidos = [];
  bool _cargando = true;

  @override
  void initState() { super.initState(); _cargarDatos(); }

  Future<void> _cargarDatos() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/players/topyellowcards?league=$_leagueId&season=$_season'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['response'] as List).map((i) => i as Map<String, dynamic>).toList();
        final alFilo = <Map<String, dynamic>>[];
        final suspendidos = <Map<String, dynamic>>[];
        for (final item in items) {
          final cards = item['statistics']?[0]?['cards'];
          final yellow = cards?['yellow'] as int? ?? 0;
          final yellowred = cards?['yellowred'] as int? ?? 0;
          final red = cards?['red'] as int? ?? 0;
          if (yellow == 4) alFilo.add({...item, '_tipo': 'filo'});
          if (yellow >= 5) suspendidos.add({...item, '_tipo': 'amarillas'});
          if (yellowred >= 1 || red >= 1) suspendidos.add({...item, '_tipo': 'roja'});
        }
        if (mounted) setState(() { _alFilo = alFilo; _suspendidos = suspendidos; _cargando = false; });
      } else { if (mounted) setState(() => _cargando = false); }
    } catch (e) { if (mounted) setState(() => _cargando = false); }
  }

  int get _total => _alFilo.length + _suspendidos.length;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _total == 0 ? null : () => _mostrarDetalle(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('🟨', style: TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AL FILO DE LA NAVAJA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            if (_cargando) const Text('Cargando...', style: TextStyle(color: Colors.white38, fontSize: 11))
            else if (_total == 0) const Text('Sin jugadores en riesgo', style: TextStyle(color: Colors.white38, fontSize: 11))
            else Text('${_alFilo.length} jugadores en riesgo · datos según acumulado de temporada', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          if (!_cargando && _total > 0) ...[
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
              child: Text('$_total', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13))),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ]),
      ),
    );
  }

  void _mostrarDetalle(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1B2A3B), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.65, maxChildSize: 0.95, minChildSize: 0.4,
        builder: (context, sc) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              Text('🟨', style: TextStyle(fontSize: 20)), SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AL FILO DE LA NAVAJA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Tarjetas acumuladas en la temporada', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ])),
          const Divider(color: Colors.white12, height: 1),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            if (_alFilo.isNotEmpty) ...[
              const Text('⚠️ EN RIESGO — 4 amarillas', style: TextStyle(color: Color(0xFFFFAB00), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._alFilo.map((p) => _cardJugador(p)),
              const SizedBox(height: 16),
            ],
           
          ])),
        ]),
      ),
    );
  }

  Widget _cardJugador(Map<String, dynamic> data) {
    final player = data['player'];
    final stats = (data['statistics'] as List?)?.isNotEmpty == true ? data['statistics'][0] as Map<String, dynamic> : <String, dynamic>{};
    final nombre = player?['name'] as String? ?? '';
    final foto = player?['photo'] as String? ?? '';
    final equipo = stats['team']?['name'] as String? ?? '';
    final logoEquipo = stats['team']?['logo'] as String? ?? '';
    final yellow = stats['cards']?['yellow'] as int? ?? 0;
    final red = stats['cards']?['red'] as int? ?? 0;
    final tipo = data['_tipo'] as String? ?? 'filo';
    String badge; Color badgeColor; String subTexto;
    if (tipo == 'roja') { badge = '🟥 Roja'; badgeColor = const Color(0xFFFF5252); subTexto = 'Suspendido por roja'; }
    else if (tipo == 'amarillas') { badge = '🟨×$yellow'; badgeColor = const Color(0xFFFF5252); subTexto = 'Suspendido por acumulación'; }
    else { badge = '⚠️ 4 🟨'; badgeColor = const Color(0xFFFFAB00); subTexto = 'La próxima lo suspende'; }
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.2), width: 1)),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
          backgroundColor: Colors.white12,
          child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38, size: 22) : null),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
          Row(children: [
            if (logoEquipo.isNotEmpty) Image.network(logoEquipo, width: 14, height: 14, errorBuilder: (_, __, ___) => const SizedBox()),
            const SizedBox(width: 4),
            Expanded(child: Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 11), overflow: TextOverflow.ellipsis)),
          ]),
          Text(subTexto, style: TextStyle(color: badgeColor, fontSize: 10)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
