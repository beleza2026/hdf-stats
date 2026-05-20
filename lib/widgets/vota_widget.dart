import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../image_decode_helper.dart';
import '../paywall_screen.dart';
import '../services/premium_service.dart';
import '../services/vota_mundial_service.dart';
import '../services/vota_service.dart';

/// Card de votación estilo Scouter (local / empate / visitante).
class VotaWidget extends StatefulWidget {
  const VotaWidget({
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

  /// Si `true`, usa Firestore `votos_mundial` (Mundial 2026).
  final bool mundial;

  final int fixtureId;
  final String localName;
  final String visitanteName;
  final String? homeLogo;
  final String? awayLogo;
  final bool jugado;
  final bool isLive;
  final String? statusShort;

  @override
  State<VotaWidget> createState() => _VotaWidgetState();
}

class _VotaWidgetState extends State<VotaWidget> {
  static const _green = Color(0xFF00E650);
  static const _btnBg = Color(0xFF1A2E3B);
  static const _cardBg = Color(0xFF1B2A3B);

  bool _submitting = false;
  bool? _esPremium;

  String get _fixtureKey => widget.fixtureId.toString();

  String get _votosCollection =>
      widget.mundial ? VotaMundialService.collection : VotaService.collectionLiga;

  bool get _puedeVotar => VotaService.puedeVotar(
        jugado: widget.jugado,
        isLive: widget.isLive,
        statusShort: widget.statusShort,
      );

  Future<bool> _ensureAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A3B),
        title: const Text('Iniciá sesión', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Para votar necesitás identificarte. ¿Continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar', style: TextStyle(color: _green)),
          ),
        ],
      ),
    );
    if (go != true) return false;
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}
    return FirebaseAuth.instance.currentUser != null;
  }

  Future<void> _onVote(String voto) async {
    if (!_puedeVotar || _submitting) return;
    if (!await _ensureAuth()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _submitting = true);
    try {
      await VotaService.castVote(
        fixtureId: _fixtureKey,
        uid: uid,
        voto: voto,
        collection: _votosCollection,
      );
    } on VotaAlreadyVotedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya votaste este partido')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar el voto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    final v = await PremiumService.isPremium();
    if (mounted) setState(() => _esPremium = v);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final premium =
        widget.mundial || (_esPremium ?? false) || PremiumService.unlockAllForPreview;

    return StreamBuilder<VotaTotals>(
      stream: VotaService.watchTotals(_fixtureKey, collection: _votosCollection),
      builder: (context, totalsSnap) {
        final totals = totalsSnap.data ?? VotaTotals.empty;

        return StreamBuilder<String?>(
          stream: uid != null
              ? VotaService.watchUserVote(_fixtureKey, uid, collection: _votosCollection)
              : Stream.value(null),
          builder: (context, userSnap) {
            final userVote = userSnap.data;
            final yaVoto = userVote != null && userVote.isNotEmpty;
            final mostrarBotones = _puedeVotar && !yaVoto && !_submitting;
            final mostrarResultados = !mostrarBotones;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'VOTA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (mostrarResultados)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _green.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            '${totals.total} votos',
                            style: const TextStyle(
                              color: _green,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (mostrarBotones)
                    _buildVoteButtons(userVote)
                  else if (!premium)
                    _buildResultadosPremiumLock()
                  else
                    _buildResults(totals, userVote, destacarGanador: widget.jugado || widget.isLive || yaVoto),
                  if (_submitting)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVoteButtons(String? selectedPreview) {
    return Row(
      children: [
        Expanded(child: _voteButton('local', widget.localName, logo: widget.homeLogo, selected: selectedPreview == 'local')),
        const SizedBox(width: 8),
        Expanded(child: _voteButton('empate', 'Empate', icon: Icons.sports_soccer, selected: selectedPreview == 'empate')),
        const SizedBox(width: 8),
        Expanded(child: _voteButton('visitante', 'Visitante', logo: widget.awayLogo, selected: selectedPreview == 'visitante')),
      ],
    );
  }

  Widget _voteButton(
    String voto,
    String label, {
    String? logo,
    IconData? icon,
    bool selected = false,
  }) {
    return Material(
      color: _btnBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _submitting ? null : () => _onVote(voto),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _green : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo != null && logo.isNotEmpty)
                DecodedNetworkImage(logo, width: 36, height: 36, errorBuilder: (_, __, ___) => Icon(icon ?? Icons.shield, color: Colors.white38, size: 32))
              else
                Icon(icon ?? Icons.shield, color: _green, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _green : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultadosPremiumLock() {
    return Column(
      children: [
        const Text(
          'Resultados detallados con Premium',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final ok = await PaywallScreen.open(context);
            if (ok == true) await _loadPremium();
          },
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.black,
          ),
          child: const Text('EMPEZAR PRUEBA GRATIS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildResults(VotaTotals totals, String? userVote, {required bool destacarGanador}) {
    final winner = destacarGanador ? totals.winnerKey() : null;
    return Column(
      children: [
        _resultRow('Local', totals.percentFor('local'), userVote == 'local', winner == 'local'),
        const SizedBox(height: 10),
        _resultRow('Empate', totals.percentFor('empate'), userVote == 'empate', winner == 'empate'),
        const SizedBox(height: 10),
        _resultRow('Visitante', totals.percentFor('visitante'), userVote == 'visitante', winner == 'visitante'),
      ],
    );
  }

  Widget _resultRow(String label, int pct, bool esMiVoto, bool esGanador) {
    final barColor = esGanador ? _green : Colors.white24;
    final textColor = esGanador ? _green : Colors.white54;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: esMiVoto ? _green : Colors.white70,
                    fontSize: 12,
                    fontWeight: esMiVoto ? FontWeight.bold : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (esMiVoto) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle, color: _green, size: 14),
              ],
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFF0D1B2A),
              color: barColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
