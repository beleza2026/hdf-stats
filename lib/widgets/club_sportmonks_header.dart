import 'package:flutter/material.dart';

import '../api_service.dart';
import '../image_decode_helper.dart';
import '../services/sportmonks_service.dart';

/// Cabecera del tab INFO del club: foto del estadio (Sportmonks + fallback API-Football).
class ClubSportmonksHeader extends StatefulWidget {
  const ClubSportmonksHeader({
    super.key,
    required this.apiFootballTeamId,
    required this.teamName,
    this.staticEstadio,
    this.staticCapacidad,
  });

  final int apiFootballTeamId;
  final String teamName;
  final String? staticEstadio;
  final String? staticCapacidad;

  @override
  State<ClubSportmonksHeader> createState() => _ClubSportmonksHeaderState();
}

class _ClubSportmonksHeaderState extends State<ClubSportmonksHeader> {
  late Future<({SportmonksClubProfile? sm, String? venueImageUrl})> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ClubSportmonksHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiFootballTeamId != widget.apiFootballTeamId ||
        oldWidget.teamName != widget.teamName) {
      _reload();
    }
  }

  void _reload() {
    final apiId =
        SportmonksService.reconcileLpfApiFootballTeamId(widget.apiFootballTeamId, widget.teamName);
    _future = _load(apiId, widget.teamName);
  }

  Future<({SportmonksClubProfile? sm, String? venueImageUrl})> _load(
    int apiId,
    String teamName,
  ) async {
    SportmonksClubProfile? sm;
    if (SportmonksService.hasConfiguredToken) {
      sm = await SportmonksService().fetchClubProfileForApiFootball(apiId, teamName);
    }
    var img = sm?.venueImageUrl?.trim();
    if (img == null || img.isEmpty) {
      img = (await ApiService.getVenueFotoForLpfTeam(apiId))?.trim();
    }
    if (img == null || img.isEmpty) {
      img = SportmonksService.stadiumPhotoFallbackForApiTeam(apiId);
    }
    if ((img == null || img.isEmpty) && sm != null && sm.hasVenueImage) {
      img = sm.venueImageUrl;
    }
    return (sm: sm, venueImageUrl: (img != null && img.isNotEmpty) ? img : null);
  }

  @override
  Widget build(BuildContext context) {
    if (!SportmonksService.hasConfiguredToken) {
      return _ApiFootballOnlyHeader(
        apiId: SportmonksService.reconcileLpfApiFootballTeamId(
          widget.apiFootballTeamId,
          widget.teamName,
        ),
        staticEstadio: widget.staticEstadio,
      );
    }

    return FutureBuilder<({SportmonksClubProfile? sm, String? venueImageUrl})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD700)),
              ),
            ),
          );
        }
        final data = snap.data;
        final sm = data?.sm;
        final imageUrl = data?.venueImageUrl;
        final estadioLabel = sm?.venueName?.trim().isNotEmpty == true
            ? sm!.venueName!
            : (widget.staticEstadio ?? '');
        final ciudad = sm?.venueCity;
        final capSm = sm?.venueCapacity;
        final capStatic =
            int.tryParse((widget.staticCapacidad ?? '').replaceAll('.', '').replaceAll(',', ''));

        if (imageUrl == null && estadioLabel.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) => DecodedNetworkImage(
                      imageUrl,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _stadiumPlaceholder(estadioLabel),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ] else if (estadioLabel.isNotEmpty) ...[
              _stadiumPlaceholder(estadioLabel),
              const SizedBox(height: 6),
            ],
            if (estadioLabel.isNotEmpty)
              Text(
                estadioLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (ciudad != null && ciudad.isNotEmpty)
              Text(ciudad, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            if (capSm != null && capSm > 0 && capSm != capStatic)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Capacidad: $capSm espectadores',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _stadiumPlaceholder(String label) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stadium, color: Colors.white24, size: 48),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApiFootballOnlyHeader extends StatelessWidget {
  const _ApiFootballOnlyHeader({
    required this.apiId,
    this.staticEstadio,
  });

  final int apiId;
  final String? staticEstadio;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ApiService.getVenueFotoForLpfTeam(apiId),
      builder: (context, snap) {
        final img = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD700)),
              ),
            ),
          );
        }
        if (img == null || img.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: LayoutBuilder(
                builder: (context, constraints) => DecodedNetworkImage(
                  img,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
