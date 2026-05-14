import 'package:flutter/material.dart';

import '../services/sportmonks_service.dart';

/// **DATOS DE MERCADO** (Sportmonks): [FutureBuilder] sobre el primer resultado de búsqueda.
///
/// El [Future] se crea **una sola vez** por ciclo de vida (no en cada `build`), para no
/// cancelar la petición HTTP cuando el padre se reconstruye (evita *connection abort*).
///
/// Usar con `key: ValueKey(nombre)` si el nombre puede cambiar en el mismo State.
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

  static String _sanitizeForDisplay(String raw) {
    return raw.replaceAll(RegExp(r'api_token=[^&\s)]+'), 'api_token=***');
  }

  static String _friendlyError(Object? err) {
    if (err == null) return 'Error desconocido';
    final s = err.toString();
    if (s.contains('connection abort') ||
        s.contains('Connection reset') ||
        s.contains('SocketException') ||
        s.contains('Failed host lookup')) {
      return 'Falló la conexión con Sportmonks (red). Probá de nuevo en unos segundos.';
    }
    if (s.contains('TimeoutException')) {
      return 'Sportmonks tardó demasiado. Probá de nuevo con mejor señal de red.';
    }
    return _sanitizeForDisplay(s);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SportmonksPlayerMarketSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titleBlock(),
              const SizedBox(height: 8),
              Text(
                _friendlyError(snap.error),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleBlock(),
              const SizedBox(height: 20),
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

        final result = snap.data;
        if (result == null || result.errorMessage != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titleBlock(),
              const SizedBox(height: 8),
              Text(
                _sanitizeForDisplay(result?.errorMessage ?? 'Sin datos Sportmonks'),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        }

        final data = result.data;
        if (data == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titleBlock(),
              const SizedBox(height: 8),
              const Text(
                'Sin datos Sportmonks',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        }

        final recent = data.transfers.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleBlock(),
            const SizedBox(height: 12),
            if (data.marketValue != null) ...[
              _rowLabel('Valor de mercado'),
              const SizedBox(height: 4),
              Text(
                data.marketValueFormatted,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
            ],
            _rowLabel('Vencimiento contrato'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  data.contractUntilFormatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: data.contractStatus.badgeColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: data.contractStatus.badgeColor, width: 1),
                  ),
                  child: Text(
                    data.contractStatus.badgeShortLabel,
                    style: TextStyle(
                      color: data.contractStatus.badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Transferencias recientes',
              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              Text(
                'Sin transferencias en la respuesta.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
              )
            else
              ...recent.map((t) {
                final y = t.year != null ? '${t.year}' : '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                      children: [
                        TextSpan(
                          text: '$y · ',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                        ),
                        TextSpan(
                          text: '${t.fromClub} → ${t.toClub}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' · ${t.amountFormatted}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  static Widget _titleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATOS DE MERCADO',
          style: TextStyle(
            color: Color(0xFF00C853),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Sportmonks',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
        ),
      ],
    );
  }

  static Widget _rowLabel(String s) {
    return Text(s, style: const TextStyle(color: Colors.white54, fontSize: 11));
  }
}
