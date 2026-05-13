import 'package:flutter/material.dart';

/// Barra comparativa local vs visitante (estilo broadcast).
class LiveCompareBar extends StatelessWidget {
  const LiveCompareBar({
    super.key,
    required this.label,
    required this.homeValue,
    required this.awayValue,
    required this.homeColor,
    required this.awayColor,
    this.isPercent = false,
    this.hideIfBothZero = true,
  });

  final String label;
  final dynamic homeValue;
  final dynamic awayValue;
  final Color homeColor;
  final Color awayColor;
  final bool isPercent;
  final bool hideIfBothZero;

  static String _parse(dynamic v) {
    if (v == null) return '0';
    final s = v.toString().replaceAll('%', '').trim();
    return s.isEmpty || s == '-' ? '0' : s;
  }

  @override
  Widget build(BuildContext context) {
    final vH = double.tryParse(_parse(homeValue)) ?? 0;
    final vA = double.tryParse(_parse(awayValue)) ?? 0;
    if (hideIfBothZero && vH == 0 && vA == 0) return const SizedBox.shrink();
    final total = vH + vA;
    final ratioH = total > 0 ? vH / total : 0.5;
    final lH = isPercent ? '${vH.round()}%' : '${vH.round()}';
    final lA = isPercent ? '${vA.round()}%' : '${vA.round()}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              lH,
              style: TextStyle(color: homeColor, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (ratioH * 100).round().clamp(1, 1000),
                        child: Container(height: 6, color: homeColor),
                      ),
                      Expanded(
                        flex: ((1 - ratioH) * 100).round().clamp(1, 1000),
                        child: Container(height: 6, color: awayColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              lA,
              style: TextStyle(color: awayColor, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
