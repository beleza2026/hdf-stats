import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../services/sportmonks_service.dart';
import 'live_fixture_bundle.dart';

/// Fila Sportmonks bajo el nombre del equipo: Future propio para no acoplar cargas.
class _PitchSquadSportmonksRow extends StatefulWidget {
  const _PitchSquadSportmonksRow({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.accent,
  });

  final int teamId;
  final String teamName;
  final Color accent;

  @override
  State<_PitchSquadSportmonksRow> createState() => _PitchSquadSportmonksRowState();
}

class _PitchSquadSportmonksRowState extends State<_PitchSquadSportmonksRow> {
  late final Future<SportmonksSquadInfo?> _future =
      SportmonksService().getSquadInfo(widget.teamId, teamName: widget.teamName);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportmonksSquadInfo?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.accent.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          );
        }
        final data = snap.data;
        if (data == null || !data.hasAnyData) {
          return const SizedBox.shrink();
        }
        final chips = <Widget>[];
        if (data.averageAge != null) {
          chips.add(
            Text(
              '👥 Edad prom: ${data.averageAge!.toStringAsFixed(1)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 9, height: 1.2),
            ),
          );
        }
        if (data.totalMarketValueEuros != null && data.totalMarketValueEuros! > 0) {
          chips.add(
            Text(
              '💰 Valor plantel: ${SportmonksService.formatMarketValueCompactEur(data.totalMarketValueEuros!)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 9, height: 1.2),
            ),
          );
        }
        if (chips.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: chips,
          ),
        );
      },
    );
  }
}

/// Mini cancha con jugadores según `grid` de la API.
class LivePitchField extends StatelessWidget {
  const LivePitchField({
    super.key,
    required this.lineupTeam,
    required this.accent,
    required this.title,
    required this.teamId,
    this.ratingsByPlayerId = const {},
  });

  final Map<String, dynamic> lineupTeam;
  final Color accent;
  final String title;
  /// ID del club en API-Football (clave de caché); el nombre [title] resuelve el equipo en Sportmonks.
  final int teamId;
  final Map<int, double> ratingsByPlayerId;

  static (double x, double y) _gridToXY(String? grid, {required bool flipVertical}) {
    if (grid == null || !grid.contains(':')) return (0.5, 0.5);
    final p = grid.split(':');
    final row = int.tryParse(p[0].trim()) ?? 1;
    final col = int.tryParse(p[1].trim()) ?? 1;
    final x = (col / 9.0).clamp(0.08, 0.92);
    var y = (row / 7.0).clamp(0.1, 0.9);
    if (flipVertical) y = 1.0 - y;
    return (x, y);
  }

  @override
  Widget build(BuildContext context) {
    final xi = List<Map<String, dynamic>>.from(lineupTeam['startXI'] ?? []);
    if (xi.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        _PitchSquadSportmonksRow(
          key: ValueKey('sm-sq-$teamId-${title.hashCode}'),
          teamId: teamId,
          teamName: title,
          accent: accent,
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 0.72,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _PitchPainter(accent: accent.withValues(alpha: 0.35))),
                    ...xi.map((slot) {
                      final pl = slot['player'] as Map<String, dynamic>? ?? {};
                      final grid = pl['grid'] as String?;
                      final (nx, ny) = _gridToXY(grid, flipVertical: false);
                      final name = liveCleanPlayerName(pl['name'] as String? ?? '');
                      final short = name.split(' ').isNotEmpty ? name.split(' ').last : name;
                      final numRaw = pl['number'];
                      final dorsal = numRaw is int ? numRaw : (numRaw is num ? numRaw.toInt() : int.tryParse('$numRaw') ?? 0);
                      final idRaw = pl['id'];
                      final pid = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw') ?? 0);
                      final rating = ratingsByPlayerId[pid];
                      return Positioned(
                        left: nx * w - 18,
                        top: ny * h - 18,
                        child: Tooltip(
                          message: rating != null ? '$name · $dorsal · $rating' : '$name · $dorsal',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF0D1B2A),
                                  border: Border.all(color: accent, width: 1.5),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 3)],
                                ),
                                child: pl['photo'] != null && (pl['photo'] as String).isNotEmpty
                                    ? ClipOval(
                                        child: DecodedNetworkImage(
                                          pl['photo'] as String,
                                          width: 30,
                                          height: 30,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Center(child: Text('$dorsal', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold))),
                                        ),
                                      )
                                    : Center(child: Text('$dorsal', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold))),
                              ),
                              if (rating != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: rating >= 7.5 ? Colors.green : rating >= 6.5 ? Colors.orange : Colors.red.shade800,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  short,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 8, height: 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PitchPainter extends CustomPainter {
  _PitchPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    final fill = Paint()..color = const Color(0xFF0F2418);
    canvas.drawRRect(r, fill);

    final line = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final midX = size.width / 2;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), line);
    canvas.drawOval(Rect.fromCenter(center: Offset(midX, size.height / 2), width: size.width * 0.32, height: size.height * 0.22), line);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.22, size.width * 0.12, size.height * 0.56), line);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.88, size.height * 0.22, size.width * 0.12, size.height * 0.56), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
