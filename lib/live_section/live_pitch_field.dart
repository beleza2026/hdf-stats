import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import 'live_fixture_bundle.dart';

/// Mini cancha con jugadores según `grid` de la API.
class LivePitchField extends StatelessWidget {
  const LivePitchField({
    super.key,
    required this.lineupTeam,
    required this.accent,
    required this.title,
    this.ratingsByPlayerId = const {},
  });

  final Map<String, dynamic> lineupTeam;
  final Color accent;
  final String title;
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
