import 'package:flutter/material.dart';

import '../widgets/vota_widget.dart';

/// Sección VOTA del detalle de partido (debajo de info, antes de estadísticas).
class PartidoDetailVotaSection extends StatelessWidget {
  const PartidoDetailVotaSection({
    super.key,
    required this.fixtureId,
    required this.localName,
    required this.visitanteName,
    this.homeLogo,
    this.awayLogo,
    required this.jugado,
    required this.isLive,
    this.statusShort,
    this.mundial = false,
  });

  /// Si `true`, persiste en `votos_mundial` (Mundial 2026).
  final bool mundial;

  final int fixtureId;
  final String localName;
  final String visitanteName;
  final String? homeLogo;
  final String? awayLogo;
  final bool jugado;
  final bool isLive;
  final String? statusShort;

  static const _sectionStyle = TextStyle(
    color: Color(0xFF00C853),
    fontSize: 12,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10, top: 4, left: 20, right: 20),
          child: Text('VOTA ✨', style: _sectionStyle),
        ),
        VotaWidget(
          fixtureId: fixtureId,
          localName: localName,
          visitanteName: visitanteName,
          homeLogo: homeLogo,
          awayLogo: awayLogo,
          jugado: jugado,
          isLive: isLive,
          statusShort: statusShort,
          mundial: mundial,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
