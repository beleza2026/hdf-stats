import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../penales_shootout_helper.dart';
import 'partido_transmision_argentina.dart';

/// Card vertical para listados HOY (Liga y copas).
class HoyMatchCard extends StatelessWidget {
  const HoyMatchCard({
    super.key,
    required this.partido,
    required this.onTap,
    this.trailing,
    this.borderHighlight = false,
  });

  final Map<String, dynamic> partido;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool borderHighlight;

  static const _cardBg = Color(0xFF1A2E3B);
  static const _green = Color(0xFF00E650);
  static const _greenLive = Color(0xFF00C853);

  @override
  Widget build(BuildContext context) {
    final teams = partido['teams'] as Map<String, dynamic>?;
    final goals = partido['goals'] as Map<String, dynamic>?;
    final fixture = partido['fixture'] as Map<String, dynamic>?;
    if (teams == null || fixture == null) return const SizedBox.shrink();

    final home = teams['home'] as Map<String, dynamic>?;
    final away = teams['away'] as Map<String, dynamic>?;
    final statusShort = fixture['status']?['short']?.toString() ?? '';
    final homeName = home?['name']?.toString() ?? 'Local';
    final awayName = away?['name']?.toString() ?? 'Visitante';
    final homeLogo = home?['logo']?.toString() ?? '';
    final awayLogo = away?['logo']?.toString() ?? '';

    final gh = goals?['home'];
    final ga = goals?['away'];
    final hStr = gh == null ? '-' : '$gh';
    final aStr = ga == null ? '-' : '$ga';
    final penSuf = PenalesShootoutHelper.sufijoMarcadorParentesis(partido) ?? '';
    final marcador = '$hStr  -  $aStr$penSuf';

    final isLive = statusShort == '1H' ||
        statusShort == '2H' ||
        statusShort == 'HT' ||
        statusShort == 'ET' ||
        statusShort == 'BT' ||
        statusShort == 'P' ||
        statusShort == 'LIVE' ||
        statusShort.contains("'");
    final isFinished = statusShort == 'FT' || statusShort == 'AET' || statusShort == 'PEN';
    final isNs = statusShort == 'NS' || statusShort == 'TBD' || statusShort == 'PST';
    final showTvPrevia = isNs && !isFinished;

    final kickoff = DateTime.tryParse(fixture['date']?.toString() ?? '')?.toLocal();
    final hora = kickoff != null
        ? '${kickoff.hour.toString().padLeft(2, '0')}:${kickoff.minute.toString().padLeft(2, '0')}'
        : '';

    String? liveLabel;
    if (isLive) {
      liveLabel = 'EN JUEGO';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borderHighlight
                      ? const Color(0xFFFFD700).withValues(alpha: 0.75)
                      : isLive
                          ? _greenLive.withValues(alpha: 0.45)
                          : Colors.transparent,
                  width: borderHighlight ? 2 : 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _teamRow(homeName, homeLogo),
                  const SizedBox(height: 10),
                  Text(
                    marcador,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isLive ? _greenLive : Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _teamRow(awayName, awayLogo),
                  const SizedBox(height: 12),
                  _StatusFooter(
                    hora: hora,
                    isLive: isLive,
                    isFinished: isFinished,
                    isNs: isNs,
                    liveLabel: liveLabel,
                    statusShort: isNs ? '' : (isFinished ? 'FT' : statusShort),
                  ),
                  if (showTvPrevia)
                    PartidoTransmisionArgentina(
                      local: homeName,
                      visitante: awayName,
                      fechaPartido: fixture['date']?.toString(),
                      homeTeamId: (home?['id'] as num?)?.toInt(),
                      awayTeamId: (away?['id'] as num?)?.toInt(),
                      compact: true,
                      centered: true,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: trailing!,
          ),
        ],
      ],
    );
  }

  Widget _teamRow(String name, String logoUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (logoUrl.isNotEmpty)
          DecodedNetworkImage(
            logoUrl,
            width: 32,
            height: 32,
            errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 32),
          )
        else
          const Icon(Icons.shield, color: Colors.white38, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            softWrap: true,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({
    required this.hora,
    required this.isLive,
    required this.isFinished,
    required this.isNs,
    this.liveLabel,
    this.statusShort = '',
  });

  final String hora;
  final bool isLive;
  final bool isFinished;
  final bool isNs;
  final String? liveLabel;
  final String statusShort;

  @override
  Widget build(BuildContext context) {
    if (isNs) {
      return Text(
        hora,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hora.isNotEmpty) ...[
          Text(hora, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('•', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
        if (isLive && liveLabel != null)
          _BlinkingLiveText(liveLabel!)
        else if (isFinished)
          const Text('FT', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600))
        else if (statusShort.isNotEmpty)
          Text(statusShort, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }
}

class _BlinkingLiveText extends StatefulWidget {
  const _BlinkingLiveText(this.label);
  final String label;

  @override
  State<_BlinkingLiveText> createState() => _BlinkingLiveTextState();
}

class _BlinkingLiveTextState extends State<_BlinkingLiveText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        widget.label,
        style: const TextStyle(
          color: Color(0xFF00E650),
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
