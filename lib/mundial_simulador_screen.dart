import 'package:flutter/material.dart';

import 'api_service.dart';

/// Simulador de cruces Mundial 2026: reordenar grupos, elegir 8 mejores terceros,
/// avanzar bracket (R32 oficial FIFA) y ver un campeón proyectado.
class MundialSimuladorScreen extends StatefulWidget {
  const MundialSimuladorScreen({super.key});

  @override
  State<MundialSimuladorScreen> createState() => _MundialSimuladorScreenState();
}

class _MundialSimuladorScreenState extends State<MundialSimuladorScreen>
    with SingleTickerProviderStateMixin {
  Map<String, List<Map<String, dynamic>>> _simGrupos = {};
  bool _loading = true;
  late TabController _tabCtrl;
  Set<String> _tercerosManual = {};
  final Map<String, Map<String, dynamic>?> _bracketWinners = {};

  /// API usa claves `Group A` … `Group L`.
  String _k(String letter) => letter.startsWith('Group') ? letter : 'Group $letter';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadGrupos();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGrupos() async {
    final data = await ApiService.getMundialGrupos();
    if (mounted) {
      setState(() {
        _simGrupos = data.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v)));
        _loading = false;
        _calcBestThirds();
      });
    }
  }

  void _calcBestThirds() {
    final terceros = <Map<String, dynamic>>[];
    _simGrupos.forEach((g, teams) {
      if (teams.length >= 3) terceros.add({...teams[2], 'grupo': g});
    });
    terceros.sort((a, b) {
      final pA = a['points'] as int? ?? 0;
      final pB = b['points'] as int? ?? 0;
      if (pA != pB) return pB.compareTo(pA);
      final gdA = a['goalsDiff'] as int? ?? 0;
      final gdB = b['goalsDiff'] as int? ?? 0;
      if (gdA != gdB) return gdB.compareTo(gdA);
      final gfA = ((a['all'] as Map?)?['goals'] as Map?)?['for'] as int? ?? 0;
      final gfB = ((b['all'] as Map?)?['goals'] as Map?)?['for'] as int? ?? 0;
      return gfB.compareTo(gfA);
    });
    _tercerosManual = terceros.take(8).map((t) => t['grupo'] as String).toSet();
  }

  List<List<Map<String, dynamic>?>> _buildR32Matches() {
    final Map<String, Map<String, dynamic>?> w = {};
    final Map<String, Map<String, dynamic>?> r = {};
    final Map<String, Map<String, dynamic>?> t3 = {};

    _simGrupos.forEach((g, teams) {
      w[g] = teams.isNotEmpty ? {...teams[0], 'grupo': g} : null;
      r[g] = teams.length >= 2 ? {...teams[1], 'grupo': g} : null;
      if (teams.length >= 3 && _tercerosManual.contains(g)) {
        t3[g] = {...teams[2], 'grupo': g};
      }
    });

    Map<String, dynamic>? bestThird(List<String> candidates) {
      Map<String, dynamic>? best;
      var bestPts = -1;
      for (final g in candidates) {
        if (t3.containsKey(g)) {
          final pts = t3[g]!['points'] as int? ?? 0;
          if (pts > bestPts) {
            bestPts = pts;
            best = t3[g];
          }
        }
      }
      return best;
    }

    return [
      [r[_k('A')], r[_k('B')]],
      [w[_k('E')], bestThird([_k('A'), _k('B'), _k('C'), _k('D'), _k('F')])],
      [w[_k('F')], r[_k('C')]],
      [w[_k('C')], r[_k('F')]],
      [w[_k('I')], bestThird([_k('C'), _k('D'), _k('F'), _k('G'), _k('H')])],
      [r[_k('E')], r[_k('I')]],
      [w[_k('A')], bestThird([_k('C'), _k('E'), _k('F'), _k('H'), _k('I')])],
      [w[_k('L')], bestThird([_k('E'), _k('H'), _k('I'), _k('J'), _k('K')])],
      [w[_k('D')], bestThird([_k('B'), _k('E'), _k('F'), _k('I'), _k('J')])],
      [w[_k('G')], bestThird([_k('A'), _k('E'), _k('H'), _k('I'), _k('J')])],
      [r[_k('K')], r[_k('L')]],
      [w[_k('H')], r[_k('J')]],
      [w[_k('B')], bestThird([_k('E'), _k('F'), _k('G'), _k('I'), _k('J')])],
      [w[_k('J')], r[_k('H')]],
      [w[_k('K')], bestThird([_k('D'), _k('E'), _k('I'), _k('J'), _k('L')])],
      [r[_k('D')], r[_k('G')]],
    ];
  }

  void _setWinner(String matchId, Map<String, dynamic>? team) {
    setState(() {
      _bracketWinners[matchId] = team;
      _clearNext(matchId);
    });
  }

  void _clearNext(String matchId) {
    final parts = matchId.split('_');
    final round = parts[0];
    final idx = int.tryParse(parts[1]) ?? 0;
    if (round == 'r32') {
      final n = idx ~/ 2;
      _bracketWinners.remove('r16_$n');
      _clearNext('r16_$n');
    } else if (round == 'r16') {
      final n = idx ~/ 2;
      _bracketWinners.remove('qf_$n');
      _clearNext('qf_$n');
    } else if (round == 'qf') {
      final n = idx ~/ 2;
      _bracketWinners.remove('sf_$n');
      _clearNext('sf_$n');
    } else if (round == 'sf') {
      _bracketWinners.remove('f_0');
    }
  }

  Map<String, dynamic>? _wi(String id) =>
      _bracketWinners.containsKey(id) ? _bracketWinners[id] : null;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
    }
    if (_simGrupos.isEmpty) {
      return const Center(child: Text('Sin datos de grupos', style: TextStyle(color: Colors.white54)));
    }
    return Column(
      children: [
        Container(
          color: const Color(0xFF0D2137),
          child: TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: 'GRUPOS'),
              Tab(text: 'BRACKET'),
            ],
            labelColor: const Color(0xFF00C853),
            unselectedLabelColor: Colors.white54,
            indicatorColor: const Color(0xFF00C853),
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildGruposTab(),
              _buildBracketTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGruposTab() {
    final grupos = _simGrupos.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: grupos.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx == grupos.length) return _buildTercerosSelector();
        return _buildGrupoReorderable(grupos[idx]);
      },
    );
  }

  Widget _buildGrupoReorderable(String grupo) {
    final teams = _simGrupos[grupo] ?? [];
    final label = grupo.replaceFirst('Group ', '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(
                  'GRUPO $label',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.swap_vert, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                const Text(
                  'Mantén para reordenar',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx--;
                final team = teams.removeAt(oldIdx);
                teams.insert(newIdx, team);
                _simGrupos[grupo] = teams;
                _calcBestThirds();
                _bracketWinners.clear();
              });
            },
            children: teams.asMap().entries.map((entry) {
              final i = entry.key;
              final team = entry.value;
              final t = team['team'] as Map<String, dynamic>? ?? {};
              final pts = team['points'] as int? ?? 0;
              final gd = team['goalsDiff'] as int? ?? 0;
              late Color posColor;
              late String badge;
              if (i == 0) {
                posColor = const Color(0xFF00C853);
                badge = '1';
              } else if (i == 1) {
                posColor = const Color(0xFF2196F3);
                badge = '2';
              } else if (i == 2 && _tercerosManual.contains(grupo)) {
                posColor = const Color(0xFFFF6F00);
                badge = '3\u2713';
              } else {
                posColor = Colors.white24;
                badge = i == 2 ? '3' : '4';
              }
              return Container(
                key: ValueKey('$grupo-$i-${t['id']}'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: posColor, width: 3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: posColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (t['logo'] != null)
                      Image.network(
                        t['logo'] as String,
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 20),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t['name'] as String? ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    Text(
                      '$pts pts',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${gd >= 0 ? '+' : ''}$gd',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.drag_handle, color: Colors.white24, size: 16),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTercerosSelector() {
    final terceros = <Map<String, dynamic>>[];
    _simGrupos.forEach((g, teams) {
      if (teams.length >= 3) terceros.add({...teams[2], 'grupo': g});
    });
    terceros.sort((a, b) => ((b['points'] as int? ?? 0)).compareTo((a['points'] as int? ?? 0)));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MEJORES TERCEROS',
            style: TextStyle(
              color: Color(0xFFFF6F00),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Toca para incluir o excluir del bracket (máx. 8)',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
          ...terceros.map((t) {
            final g = t['grupo'] as String;
            final isIn = _tercerosManual.contains(g);
            final team = t['team'] as Map<String, dynamic>? ?? {};
            final pts = t['points'] as int? ?? 0;
            final gShort = g.replaceFirst('Group ', '');
            return GestureDetector(
              onTap: () => setState(() {
                if (isIn) {
                  _tercerosManual.remove(g);
                } else if (_tercerosManual.length < 8) {
                  _tercerosManual.add(g);
                }
                _bracketWinners.clear();
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isIn ? const Color(0xFFFF6F00).withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isIn ? const Color(0xFFFF6F00) : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIn ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isIn ? const Color(0xFFFF6F00) : Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gr. $gShort',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    if (team['logo'] != null)
                      Image.network(
                        team['logo'] as String,
                        width: 16,
                        height: 16,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 16),
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        team['name'] as String? ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    Text(
                      '$pts pts',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            '${_tercerosManual.length}/8 seleccionados',
            style: TextStyle(
              color: _tercerosManual.length == 8 ? const Color(0xFF00C853) : const Color(0xFFFF6F00),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBracketTab() {
    final r32 = _buildR32Matches();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildRoundHeader('ROUND OF 32 — 16 partidos (bracket FIFA 2026)'),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Toca el equipo ganador en cada llave. Cambiar grupos borra el bracket.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
        ...r32.asMap().entries.map((e) => _buildMatchCard('r32_${e.key}', e.value[0], e.value[1])),
        const SizedBox(height: 12),
        _buildRoundHeader('OCTAVOS DE FINAL'),
        ...List.generate(
          8,
          (i) => _buildMatchCard('r16_$i', _wi('r32_${i * 2}'), _wi('r32_${i * 2 + 1}')),
        ),
        const SizedBox(height: 12),
        _buildRoundHeader('CUARTOS DE FINAL'),
        ...List.generate(
          4,
          (i) => _buildMatchCard('qf_$i', _wi('r16_${i * 2}'), _wi('r16_${i * 2 + 1}')),
        ),
        const SizedBox(height: 12),
        _buildRoundHeader('SEMIFINALES'),
        ...List.generate(
          2,
          (i) => _buildMatchCard('sf_$i', _wi('qf_${i * 2}'), _wi('qf_${i * 2 + 1}')),
        ),
        const SizedBox(height: 12),
        _buildRoundHeader('FINAL'),
        _buildMatchCard('f_0', _wi('sf_0'), _wi('sf_1')),
        const SizedBox(height: 8),
        _buildCampeon(),
      ],
    );
  }

  Widget _buildRoundHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF00C853),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _buildMatchCard(String matchId, Map<String, dynamic>? t1, Map<String, dynamic>? t2) {
    final winner = _wi(matchId);
    final t1t = t1?['team'] as Map<String, dynamic>? ?? {};
    final t2t = t2?['team'] as Map<String, dynamic>? ?? {};
    final t1Name = t1t['name'] as String? ?? t1?['name'] as String? ?? 'TBD';
    final t2Name = t2t['name'] as String? ?? t2?['name'] as String? ?? 'TBD';
    final t1Logo = t1t['logo'] as String? ?? t1?['logo'] as String?;
    final t2Logo = t2t['logo'] as String? ?? t2?['logo'] as String?;
    final t1id = t1t['id'] ?? t1?['id'];
    final winnerId = (winner?['team'] as Map<String, dynamic>?)?['id'] ?? winner?['id'];
    final t1Win = winner != null && winnerId == t1id;
    final t2Win = winner != null && !t1Win;

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: t1 == null ? null : () => _setWinner(matchId, t1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: t1Win ? const Color(0xFF00C853).withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (t1Logo != null)
                        Image.network(
                          t1Logo,
                          width: 18,
                          height: 18,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 18),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t1Name,
                          style: TextStyle(
                            color: t1 == null ? Colors.white24 : (t1Win ? const Color(0xFF00C853) : Colors.white),
                            fontSize: 11,
                            fontWeight: t1Win ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (t1Win) const Icon(Icons.check_circle, color: Color(0xFF00C853), size: 13),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              color: const Color(0xFF0D1B2A),
              alignment: Alignment.center,
              child: const Text(
                'VS',
                style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: t2 == null ? null : () => _setWinner(matchId, t2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: t2Win ? const Color(0xFF00C853).withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (t2Win) const Icon(Icons.check_circle, color: Color(0xFF00C853), size: 13),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          t2Name,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: t2 == null ? Colors.white24 : (t2Win ? const Color(0xFF00C853) : Colors.white),
                            fontSize: 11,
                            fontWeight: t2Win ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (t2Logo != null)
                        Image.network(
                          t2Logo,
                          width: 18,
                          height: 18,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampeon() {
    final c = _wi('f_0');
    if (c == null) return const SizedBox.shrink();
    final t = c['team'] as Map<String, dynamic>? ?? c;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'TU CAMPEÓN (simulación)',
            style: TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          if (t['logo'] != null)
            Image.network(
              t['logo'] as String,
              width: 50,
              height: 50,
              errorBuilder: (_, __, ___) => const SizedBox(height: 50),
            ),
          const SizedBox(height: 6),
          Text(
            t['name'] as String? ?? '',
            style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
