import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'live_match_rich_card.dart';
import 'live_section_mock.dart';

/// Sección completa "En vivo" con pull-to-refresh, skeleton inicial y pie de última actualización de lista.
class LiveMatchSectionView extends StatelessWidget {
  const LiveMatchSectionView({
    super.key,
    required this.partidos,
    required this.onRefresh,
    required this.onPartidoTap,
    this.loadingLista = false,
    this.lastListaUpdate,
  });

  final List<Map<String, dynamic>> partidos;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic> partido) onPartidoTap;
  final bool loadingLista;
  final DateTime? lastListaUpdate;

  static String _relativo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 55) return 'hace ${d.inSeconds}s';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (loadingLista && partidos.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: RefreshIndicator(
              color: const Color(0xFF00C853),
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerRow(lastListaUpdate),
                  const SizedBox(height: 14),
                  _skeletonCard(),
                  const SizedBox(height: 14),
                  _skeletonCard(),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (partidos.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: RefreshIndicator(
              color: const Color(0xFF00C853),
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                children: [
                  const SizedBox(height: 12),
                  const Icon(Icons.live_tv, color: Colors.white24, size: 48),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'No hay partidos en vivo ahora',
                      style: TextStyle(color: Colors.white54, fontSize: 17, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Liga Profesional · deslizá hacia abajo para actualizar',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_outlined, size: 16, color: Colors.white.withValues(alpha: 0.85)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Así se ve la tarjeta con datos de ejemplo (no usa la API)',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.3),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  LiveMatchRichCard(
                    partidoLista: LiveSectionMock.partidoEjemplo(),
                    previewMode: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00C853),
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _headerRow(lastListaUpdate),
          if (lastListaUpdate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Lista de partidos: actualizada ${_relativo(lastListaUpdate!)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Cada partido se actualiza solo cada 30 s (eventos, estadísticas y planteles).',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 10, height: 1.35),
            textAlign: TextAlign.center,
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 6),
            Text(
              'En la barra superior de cada partido, la campana activa alertas push solo de ese encuentro (máx. 40).',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 10, height: 1.35),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          ...partidos.map((p) {
            return LiveMatchRichCard(
              partidoLista: p,
              onTap: () => onPartidoTap(p),
            );
          }),
        ],
      ),
    );
  }

  Widget _headerRow(DateTime? listaAt) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'EN VIVO — LIGA PROFESIONAL',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              const Text('LIVE', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skeletonCard() {
    final br = BorderRadius.circular(12);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: br),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121e2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(120, 12),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              bar(56, 56),
              bar(100, 36),
              bar(56, 56),
            ],
          ),
          const SizedBox(height: 20),
          bar(double.infinity, 8),
          const SizedBox(height: 8),
          bar(double.infinity, 8),
        ],
      ),
    );
  }
}
