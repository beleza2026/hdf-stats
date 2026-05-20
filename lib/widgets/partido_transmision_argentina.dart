import 'package:flutter/material.dart';

import '../api_service.dart';

/// Canales que transmiten el partido en Argentina (Sportmonks).
class PartidoTransmisionArgentina extends StatelessWidget {
  const PartidoTransmisionArgentina({
    super.key,
    required this.local,
    required this.visitante,
    this.fechaPartido,
    this.homeTeamId,
    this.awayTeamId,
    this.compact = false,
    this.centered = false,
  });

  final String local;
  final String visitante;
  final String? fechaPartido;
  final int? homeTeamId;
  final int? awayTeamId;
  final bool compact;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: ApiService.getCanalesTransmisionArgentina(
        local: local,
        visitante: visitante,
        fechaPartido: fechaPartido,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          if (compact && centered) {
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Buscando señal…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 10),
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.only(top: compact ? 4 : 8),
            child: Row(
              mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Buscando señal…',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 12),
                ),
              ],
            ),
          );
        }
        final canales = snap.data ?? [];
        if (canales.isEmpty) return const SizedBox.shrink();

        if (compact) {
          final texto = canales.join(' · ');
          if (centered) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.live_tv, color: Colors.white.withValues(alpha: 0.45), size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Por TV en Argentina',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF00E650),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.live_tv, color: Color(0xFF00C853), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    texto,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.live_tv, color: Color(0xFF00C853), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Señal en Argentina',
                        style: TextStyle(
                          color: Color(0xFF00C853),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canales.join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
