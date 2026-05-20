import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../nationality_flags.dart';
import '../services/posesion_mundial_service.dart';

/// Card de posesión promedio para el ranking Mundial.
class PosesionCard extends StatelessWidget {
  const PosesionCard({
    super.key,
    required this.posicion,
    required this.equipo,
    required this.barraRelativa,
  });

  final int posicion;
  final PosesionMundialEquipo equipo;
  /// 0.0–1.0 respecto al líder del ranking.
  final double barraRelativa;

  static const _green = Color(0xFF00E650);
  static const _card = Color(0xFF1B2A3B);

  String get _posLabel {
    if (posicion == 1) return '🥇';
    if (posicion == 2) return '🥈';
    if (posicion == 3) return '🥉';
    return '#$posicion';
  }

  @override
  Widget build(BuildContext context) {
    final flag = flagEmojiFromCountryName(equipo.country);
    final dg = equipo.diferenciaGoles;
    final dgTxt = dg >= 0 ? '+$dg' : '$dg';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  _posLabel,
                  style: TextStyle(
                    fontSize: posicion <= 3 ? 18 : 14,
                    fontWeight: FontWeight.bold,
                    color: posicion <= 3 ? _green : Colors.white54,
                  ),
                ),
              ),
              if (flag.isNotEmpty) ...[
                Text(flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
              ] else if (equipo.logo.isNotEmpty) ...[
                DecodedNetworkImage(
                  equipo.logo,
                  width: 28,
                  height: 28,
                  errorBuilder: (_, __, ___) => const Icon(Icons.flag, color: Colors.white24, size: 24),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  equipo.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${equipo.promedioPosesion.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: barraRelativa.clamp(0.05, 1.0),
              minHeight: 10,
              backgroundColor: const Color(0xFF0D1B2A),
              color: _green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PJ: ${equipo.partidos}  •  Goles: ${equipo.goles}  •  DG: $dgTxt',
            style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}
