import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'match_follow_service.dart';
import 'mundial_prefs_service.dart';
import 'mundial_premium_widgets.dart';
import 'mundial_service.dart';
import 'widgets/premium_gate.dart';

/// Hub Premium: récords, sedes, quiniela, alertas.
class MundialPremiumHub extends StatefulWidget {
  const MundialPremiumHub({
    super.key,
    required this.esPremium,
    this.onPremiumChanged,
  });

  final bool esPremium;
  final Future<void> Function()? onPremiumChanged;

  @override
  State<MundialPremiumHub> createState() => _MundialPremiumHubState();
}

class _MundialPremiumHubState extends State<MundialPremiumHub> {
  Map<String, dynamic>? _records;
  Map<String, dynamic>? _candidatosTitulo;
  List<Map<String, dynamic>> _proximos = [];
  List<Map<String, dynamic>> _fixture = [];
  Map<int, String> _quiniela = {};
  int _puntosQuiniela = 0;
  bool _loading = true;
  int? _alertTeamId;
  String _alertTeamName = '';
  bool _reminders = false;

  @override
  void initState() {
    super.initState();
    if (widget.esPremium) {
      _load();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(MundialPremiumHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.esPremium && !oldWidget.esPremium) {
      setState(() => _loading = true);
      _load();
    }
  }

  Future<void> _load() async {
    final records = await MundialService.getRecordesTorneoEnCurso();
    final candidatos = await MundialService.getProyeccionFavoritosTitulo(topN: 10);
    final prox = await MundialService.getProximosPartidos();
    final fix = await MundialService.getFixture();
    final q = await MundialPrefsService.getQuiniela();
    final ft = fix.where((p) => const {'FT', 'AET', 'PEN'}.contains(p['fixture']?['status']?['short'])).toList();
    final pts = await MundialPrefsService.totalPuntosQuiniela(ft);
    final alertId = await MundialPrefsService.getAlertSelectionId();
    final alertName = await MundialPrefsService.getAlertSelectionName();
    final rem = await MundialPrefsService.remindersEnabled();
    if (mounted) {
      setState(() {
        _records = records;
        _candidatosTitulo = candidatos;
        _proximos = prox.take(12).toList();
        _fixture = fix;
        _quiniela = q;
        _puntosQuiniela = pts;
        _alertTeamId = alertId;
        _alertTeamName = alertName ?? '';
        _reminders = rem;
        _loading = false;
      });
    }
  }

  Future<void> _syncFavoritoMundial() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt('equipo_favorito_id');
    final name = p.getString('equipo_favorito_nombre') ?? '';
    if (id != null && id > 0) {
      await MundialPrefsService.setAlertSelection(id, name);
      if (mounted) setState(() {
        _alertTeamId = id;
        _alertTeamName = name;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alertas Mundial vinculadas a $name (FCM equipo_$id)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.esPremium) {
      return PremiumGate(
        esPremium: false,
        title: 'Extra Premium · Mundial',
        subtitle: 'Récords del torneo, sedes 2026, quiniela, alertas y más.',
        onPremiumChanged: widget.onPremiumChanged,
        child: const SizedBox.shrink(),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF00C853),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hubHeader(),
          const SizedBox(height: 16),
          _sectionRecords(),
          const SizedBox(height: 20),
          _sectionSedes(),
          const SizedBox(height: 20),
          _sectionQuiniela(),
          const SizedBox(height: 20),
          _sectionAlertas(),
        ],
      ),
    );
  }

  Widget _hubHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFCA28).withValues(alpha: 0.15),
            const Color(0xFF00C853).withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCA28).withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium, color: Color(0xFFFFCA28), size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CENTRO PREMIUM MUNDIAL', style: TextStyle(color: Color(0xFFFFCA28), fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Récords, sedes, quiniela y alertas en un solo lugar.', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      );

  Widget _sectionRecords() {
    final r = _records ?? {};
    final pj = r['partidosJugados'] as int? ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('RÉCORDS DEL TORNEO'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statRow('Partidos jugados', '$pj'),
              _statRow('Goles totales', '${r['totalGoles'] ?? 0}'),
              if ((r['partidoMasGoles'] as String? ?? '').isNotEmpty)
                _statRow('Partido con más goles', '${r['partidoMasGoles']} (${r['partidoMasGolesTotal']})'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('CANDIDATOS AL TÍTULO'),
        mundialCandidatosTituloLista(_candidatosTitulo ?? {}),
        const SizedBox(height: 8),
        const Text(
          'Goleadores del torneo → pestaña GOLEADORES.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _statRow(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(l, style: const TextStyle(color: Colors.white54, fontSize: 12))),
            Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      );

  Widget _sectionSedes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('SEDES 2026 · USA · MÉXICO · CANADÁ'),
        ...MundialService.sedesMundial2026.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stadium, color: Color(0xFF00C853), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['nombre'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${s['ciudad']} · ${s['pais']}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        if ((s['nota'] as String? ?? '').isNotEmpty)
                          Text(s['nota'] as String, style: const TextStyle(color: Color(0xFFFFCA28), fontSize: 10)),
                      ],
                    ),
                  ),
                  Text('${s['cap']}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _sectionQuiniela() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('QUINIELA HDF')),
            Text('$_puntosQuiniela pts', style: const TextStyle(color: Color(0xFFFFCA28), fontWeight: FontWeight.bold)),
          ],
        ),
        const Text('3 pts marcador exacto · 1 pt resultado (1X2). Guardado en el dispositivo.',
            style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 8),
        if (_proximos.isEmpty)
          const Text('No hay partidos próximos para pronosticar.', style: TextStyle(color: Colors.white38))
        else
          ..._proximos.map((p) => _quinielaTile(p)),
      ],
    );
  }

  String? _quinielaResultado1X2(String? pred) {
    if (pred == null || pred.isEmpty) return null;
    final parts = pred.split(RegExp(r'[-:xX\s]+'));
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final a = int.tryParse(parts[1].trim());
    if (h == null || a == null) return null;
    if (h > a) return 'local';
    if (h < a) return 'visitante';
    return 'empate';
  }

  Future<void> _guardarQuiniela(int fid, String score) async {
    await MundialPrefsService.setQuinielaPrediction(fid, score);
    final q = await MundialPrefsService.getQuiniela();
    final ft = _fixture
        .where((x) => const {'FT', 'AET', 'PEN'}.contains(x['fixture']?['status']?['short']))
        .toList();
    final pts = await MundialPrefsService.totalPuntosQuiniela(ft);
    if (mounted) {
      setState(() {
        _quiniela = q;
        _puntosQuiniela = pts;
      });
    }
  }

  Widget _quinielaBtn(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E650) : const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF00E650) : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _quinielaTile(Map<String, dynamic> p) {
    final fid = (p['fixture']?['id'] as num?)?.toInt() ?? 0;
    final home = p['teams']?['home']?['name'] ?? '';
    final away = p['teams']?['away']?['name'] ?? '';
    final pred = _quiniela[fid];
    final sel = _quinielaResultado1X2(pred);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sel != null ? const Color(0xFF00E650).withValues(alpha: 0.35) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$home vs $away',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _quinielaBtn('Local', sel == 'local', () => _guardarQuiniela(fid, '1-0')),
              const SizedBox(width: 6),
              _quinielaBtn('Empate', sel == 'empate', () => _guardarQuiniela(fid, '0-0')),
              const SizedBox(width: 6),
              _quinielaBtn('Visit.', sel == 'visitante', () => _guardarQuiniela(fid, '0-1')),
            ],
          ),
          if (pred != null && pred.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Marcador pronóstico: $pred',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF00E650), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionAlertas() {
    final hoy = MundialService.partidosDeEquipo(
      _fixture.where((p) {
        final d = DateTime.tryParse(p['fixture']?['date'] as String? ?? '')?.toLocal();
        if (d == null) return false;
        final now = DateTime.now();
        return d.year == now.year && d.month == now.month && d.day == now.day;
      }).toList(),
      _alertTeamId ?? 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('ALERTAS'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _alertTeamId != null && _alertTeamId! > 0
                    ? 'Selección alertas: $_alertTeamName (FCM equipo_$_alertTeamId)'
                    : 'Elegí equipo favorito en perfil o sincronizá abajo.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _syncFavoritoMundial,
                icon: const Icon(Icons.sync, size: 16, color: Color(0xFF00C853)),
                label: const Text('Usar mi equipo favorito', style: TextStyle(color: Color(0xFF00C853), fontSize: 12)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recordatorio local (experimental)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: const Text('Usá la campana en cada partido para push por partido (FCM).', style: TextStyle(color: Colors.white38, fontSize: 10)),
                value: _reminders,
                activeThumbColor: const Color(0xFF00C853),
                onChanged: (v) async {
                  await MundialPrefsService.setRemindersEnabled(v);
                  setState(() => _reminders = v);
                },
              ),
            ],
          ),
        ),
        if (hoy.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Partidos de hoy · tu selección', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 6),
          ...hoy.map((p) {
            final fid = (p['fixture']?['id'] as num?)?.toInt() ?? 0;
            final home = p['teams']?['home']?['name'] ?? '';
            final away = p['teams']?['away']?['name'] ?? '';
            return ListTile(
              dense: true,
              tileColor: const Color(0xFF0D1B2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('$home vs $away', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              trailing: fid > 0 ? MatchFollowToggle(fixtureId: fid) : null,
            );
          }),
        ],
      ],
    );
  }
}
