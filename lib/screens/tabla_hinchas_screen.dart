import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../image_decode_helper.dart';
import '../services/hinchas_service.dart';
import 'mi_cuenta_screen.dart';

/// Ranking de equipos por cantidad de hinchas en la app.
class TablaHinchasScreen extends StatefulWidget {
  const TablaHinchasScreen({super.key});

  @override
  State<TablaHinchasScreen> createState() => _TablaHinchasScreenState();
}

class _TablaHinchasScreenState extends State<TablaHinchasScreen> {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00E650);
  static const _card = Color(0xFF1B2A3B);

  int _refresh = 0;

  Future<void> _elegirEquipo() async {
    final ok = await MiCuentaScreen.openTeamPicker(context);
    if (ok == true && mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _green),
        title: const Text(
          'TABLA DE HINCHAS ⚽',
          style: TextStyle(
            color: _green,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
      ),
      body: FutureBuilder<int?>(
        key: ValueKey(_refresh),
        future: HinchasService.favoriteTeamIdFromPrefs(),
        builder: (context, favSnap) {
          final favoriteId = favSnap.data;
          final sinEquipo = favoriteId == null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  '¿Qué equipo tiene más fans en MatchGol Stats?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.35),
                ),
              ),
              if (sinEquipo)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton.icon(
                    onPressed: _elegirEquipo,
                    icon: const Icon(Icons.favorite_border, color: Colors.black),
                    label: const Text(
                      'Elegí tu equipo',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              Expanded(
                child: StreamBuilder(
                  stream: HinchasService.watchRanking(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: _green));
                    }
                    final counts = HinchasService.rowsFromSnapshot(
                      snap.data?.docs ?? [],
                    );
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: ApiService.getEquiposLiga(),
                      builder: (context, lpfSnap) {
                        if (lpfSnap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: _green));
                        }
                        final equipos = lpfSnap.data ?? [];
                        final rows = <HinchasTeamRow>[];
                        for (final e in equipos) {
                          final id = e['id'] as int;
                          final fromFs = counts[id];
                          rows.add(
                            HinchasTeamRow(
                              teamId: id,
                              teamName: e['nombre'] as String? ?? 'Equipo',
                              teamLogo: e['escudo'] as String? ?? '',
                              count: fromFs?.count ?? 0,
                            ),
                          );
                        }
                        rows.sort((a, b) {
                          final c = b.count.compareTo(a.count);
                          if (c != 0) return c;
                          return a.teamName.compareTo(b.teamName);
                        });

                        final total = rows.fold<int>(0, (s, r) => s + r.count);
                        final maxCount = rows.isEmpty
                            ? 1
                            : rows.map((r) => r.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

                        if (rows.isEmpty) {
                          return const Center(
                            child: Text('No hay equipos de Liga Profesional', style: TextStyle(color: Colors.white54)),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: rows.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _green.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: _green.withValues(alpha: 0.45)),
                                      ),
                                      child: Text(
                                        '$total hinchas',
                                        style: const TextStyle(
                                          color: _green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final row = rows[i - 1];
                            final pos = i;
                            final esMio = favoriteId == row.teamId;
                            final pctTotal = total > 0 ? ((row.count / total) * 100).round() : 0;
                            final barPct = maxCount > 0 ? row.count / maxCount : 0.0;
                            final medal = pos == 1
                                ? '🥇'
                                : pos == 2
                                    ? '🥈'
                                    : pos == 3
                                        ? '🥉'
                                        : null;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: esMio ? _green : Colors.white10,
                                  width: esMio ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 32,
                                        child: Text(
                                          medal ?? '#$pos',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: medal != null ? 18 : 13,
                                            fontWeight: FontWeight.bold,
                                            color: esMio ? _green : Colors.white54,
                                          ),
                                        ),
                                      ),
                                      if (row.teamLogo.isNotEmpty)
                                        DecodedNetworkImage(
                                          row.teamLogo,
                                          width: 32,
                                          height: 32,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.shield, color: Colors.white38, size: 28),
                                        )
                                      else
                                        const Icon(Icons.shield, color: Colors.white38, size: 28),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row.teamName,
                                              style: TextStyle(
                                                color: esMio ? _green : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (esMio)
                                              const Text(
                                                'TU EQUIPO',
                                                style: TextStyle(
                                                  color: _green,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${row.count}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        row.count == 1 ? 'hincha' : 'hinchas',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: barPct.clamp(0.0, 1.0),
                                      minHeight: 8,
                                      backgroundColor: const Color(0xFF0D1B2A),
                                      color: esMio ? _green : Colors.white24,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '$pctTotal% del total',
                                      style: TextStyle(
                                        color: esMio ? _green.withValues(alpha: 0.9) : Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
