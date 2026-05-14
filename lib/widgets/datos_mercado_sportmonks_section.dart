import 'package:flutter/material.dart';

import '../services/sportmonks_service.dart';

/// Sección **MERCADO** (Sportmonks): [FutureBuilder] sobre [SportmonksService.searchPlayerByName].
///
/// El [Future] se crea **una sola vez** por ciclo de vida (no en cada `build`).
/// Usar con `key: ValueKey(nombre)` si el nombre puede cambiar en el mismo State.
///
/// Si no hay token, error de red o todos los datos útiles son vacíos, no se muestra nada.
class DatosMercadoSportmonksSection extends StatefulWidget {
  const DatosMercadoSportmonksSection({super.key, required this.playerName});

  final String playerName;

  @override
  State<DatosMercadoSportmonksSection> createState() => _DatosMercadoSportmonksSectionState();
}

class _DatosMercadoSportmonksSectionState extends State<DatosMercadoSportmonksSection> {
  late Future<SportmonksPlayerMarketSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = SportmonksService().searchPlayerByName(widget.playerName);
  }

  @override
  void didUpdateWidget(covariant DatosMercadoSportmonksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerName != widget.playerName) {
      _future = SportmonksService().searchPlayerByName(widget.playerName);
    }
  }

  static String _contractUrgencyEmoji(SportmonksContractStatus s) {
    switch (s) {
      case SportmonksContractStatus.expired:
      case SportmonksContractStatus.expiresUnderSixMonths:
        return '🔴';
      case SportmonksContractStatus.expiresUnderTwelveMonths:
        return '🟡';
      case SportmonksContractStatus.ok:
        return '🟢';
      case SportmonksContractStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportmonksPlayerMarketSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _mercadoTitle(),
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF00C853),
                  ),
                ),
              ),
            ],
          );
        }

        if (snap.hasError) {
          return const SizedBox.shrink();
        }

        final result = snap.data;
        if (result == null || result.errorMessage != null) {
          return const SizedBox.shrink();
        }

        final data = result.data;
        if (data == null || !data.hasMercadoContent) {
          return const SizedBox.shrink();
        }

        final ultima = data.transfers.isNotEmpty ? data.transfers.first : null;
        final emojiContrato = data.contractUntil != null ? _contractUrgencyEmoji(data.contractStatus) : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mercadoTitle(),
            const SizedBox(height: 12),
            if (data.marketValue != null) ...[
              _emojiRow('💰', 'Valor de mercado', data.marketValueFormatted),
              const SizedBox(height: 12),
            ],
            if (data.contractUntil != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📄 ', style: TextStyle(fontSize: 14, height: 1.35)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.35),
                        children: [
                          const TextSpan(text: 'Contrato hasta: '),
                          TextSpan(
                            text: data.contractUntilFormatted,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (emojiContrato.isNotEmpty)
                            TextSpan(text: '  $emojiContrato', style: const TextStyle(fontSize: 14, height: 1.2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (ultima != null)
              _emojiRow(
                '🔄',
                'Última transferencia',
                [
                  if (ultima.year != null) '${ultima.year} · ',
                  '${ultima.fromClub} → ${ultima.toClub}',
                  if (ultima.amountFormatted.trim().isNotEmpty && ultima.amountFormatted != '—') ' · ${ultima.amountFormatted}',
                ].join(),
              ),
          ],
        );
      },
    );
  }

  static Widget _mercadoTitle() {
    return const Text(
      'MERCADO',
      style: TextStyle(
        color: Color(0xFF00C853),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  static Widget _emojiRow(String emoji, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$emoji ', style: const TextStyle(fontSize: 14, height: 1.35)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.2),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
