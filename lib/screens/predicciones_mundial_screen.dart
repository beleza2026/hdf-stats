import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../nationality_flags.dart';
import '../paywall_screen.dart';
import '../services/predicciones_mundial_service.dart';
import '../services/premium_service.dart';
import '../widgets/premium_gate.dart';
import '../widgets/vota_widget.dart';

/// Pestaña PREDICCIONES del Mundial 2026 (±48 h, HDF™ + VOTA).
class PrediccionesMundialScreen extends StatefulWidget {
  const PrediccionesMundialScreen({super.key, required this.esPremium});

  final bool esPremium;

  @override
  State<PrediccionesMundialScreen> createState() => _PrediccionesMundialScreenState();
}

class _PrediccionesMundialScreenState extends State<PrediccionesMundialScreen> {
  static const _bg = Color(0xFF0D1B2A);
  static const _green = Color(0xFF00C853);
  static const _card = Color(0xFF1B2A3B);

  late Future<List<PrediccionMundialItem>> _future;
  late bool _esPremium;

  @override
  void initState() {
    super.initState();
    _esPremium = widget.esPremium;
    _future = PrediccionesMundialService.getPrediccionesVentana48h();
  }

  Future<void> _refrescarPremium() async {
    final v = await PremiumService.isPremium();
    if (mounted) setState(() => _esPremium = v);
  }

  void _reload() {
    PrediccionesMundialService.clearCache();
    setState(() {
      _future = PrediccionesMundialService.getPrediccionesVentana48h();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _green,
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<PrediccionMundialItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: _green),
                        SizedBox(height: 12),
                        Text(
                          'Calculando predicciones HDF™…',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'No se pudieron cargar las predicciones.\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _reload,
                      child: const Text('Reintentar', style: TextStyle(color: _green)),
                    ),
                  ),
                ],
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                children: const [
                  Text(
                    'No hay partidos en las próximas 48 horas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              );
            }

            final porDia = <String, List<PrediccionMundialItem>>{};
            for (final it in items) {
              final key = _etiquetaDia(it.kickoff);
              porDia.putIfAbsent(key, () => []).add(it);
            }
            final dias = porDia.keys.toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                const Text(
                  'IA MatchGol Stats · ventana ±48 h',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 12),
                for (final dia in dias) ...[
                  _headerDia(dia),
                  ...porDia[dia]!.map((p) => _cardPartido(p)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _etiquetaDia(DateTime dt) {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == hoy) return 'HOY';
    if (d == hoy.add(const Duration(days: 1))) return 'MAÑANA';
    if (d == hoy.subtract(const Duration(days: 1))) return 'AYER';
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dt.day} ${meses[dt.month - 1]}';
  }

  Widget _headerDia(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: _green,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _cardPartido(PrediccionMundialItem p) {
    final hora =
        '${p.kickoff.hour.toString().padLeft(2, '0')}:${p.kickoff.minute.toString().padLeft(2, '0')}';
    final diaCorto = _etiquetaDia(p.kickoff);
    final estado = p.isLive
        ? 'EN JUEGO'
        : p.isFinished
            ? 'FINALIZADO'
            : '$diaCorto $hora';

    final flagH = flagEmojiFromCountryName(p.homeCountry);
    final flagA = flagEmojiFromCountryName(p.awayCountry);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: p.isLive ? _green.withValues(alpha: 0.45) : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${p.grupoLabel}  •  $estado',
              style: TextStyle(
                color: p.isLive ? _green : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 14),
            if (p.isFinished && p.goalsHome != null && p.goalsAway != null)
              _resultadoFinal(p, flagH, flagA)
            else ...[
              _filaEquipo(flagH, p.homeName, p.homeLogo),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('VS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              _filaEquipo(flagA, p.awayName, p.awayLogo),
              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),
              const Text(
                'PREDICCIÓN HDF™',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _green,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              PremiumGate(
                esPremium: _esPremium,
                title: 'Predicción HDF™',
                subtitle: 'Activá Premium para ver los porcentajes de la IA.',
                compact: true,
                onPremiumChanged: () async {
                  final ok = await PaywallScreen.open(context);
                  if (ok == true) await _refrescarPremium();
                },
                child: Column(
                  children: [
                    _barraPred('${flagH.isNotEmpty ? '$flagH ' : ''}${p.homeName}', p.pctLocal, destacado: p.predichoKey == 'local'),
                    const SizedBox(height: 8),
                    _barraPred('Empate', p.pctEmpate, destacado: p.predichoKey == 'empate'),
                    const SizedBox(height: 8),
                    _barraPred('${flagA.isNotEmpty ? '$flagA ' : ''}${p.awayName}', p.pctVisitante, destacado: p.predichoKey == 'visitante'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            VotaWidget(
              fixtureId: p.fixtureId,
              localName: p.homeName,
              visitanteName: p.awayName,
              homeLogo: p.homeLogo,
              awayLogo: p.awayLogo,
              jugado: p.isFinished,
              isLive: p.isLive,
              statusShort: p.statusShort,
              mundial: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultadoFinal(PrediccionMundialItem p, String flagH, String flagA) {
    final acerto = p.prediccionAcertada;
    final predNombre = p.predichoKey == 'local'
        ? p.homeName
        : p.predichoKey == 'visitante'
            ? p.awayName
            : 'Empate';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flagH, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                p.homeName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${p.goalsHome} - ${p.goalsAway}',
                style: const TextStyle(color: _green, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: Text(
                p.awayName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(flagA, style: const TextStyle(fontSize: 16)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (acerto == true ? _green : Colors.red).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (acerto == true ? _green : Colors.red).withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            acerto == null
                ? 'HDF™ predijo: $predNombre'
                : acerto
                    ? 'HDF™ predijo: ✅ CORRECTO ($predNombre)'
                    : 'HDF™ predijo: ❌ INCORRECTO (era $predNombre)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: acerto == true ? _green : acerto == false ? Colors.red : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaEquipo(String flag, String name, String? logo) {
    return Row(
      children: [
        if (flag.isNotEmpty) ...[
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
        ],
        if (logo != null && logo.isNotEmpty)
          DecodedNetworkImage(logo, width: 28, height: 28, errorBuilder: (_, __, ___) => const SizedBox(width: 28))
        else
          const Icon(Icons.shield_outlined, color: Colors.white24, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _barraPred(String label, int pct, {bool destacado = false}) {
    final color = destacado ? _green : Colors.white24;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(
              color: destacado ? _green : Colors.white70,
              fontSize: 12,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: _bg,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
