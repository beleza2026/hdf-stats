import 'package:flutter/material.dart';
import 'api_service.dart';
import 'nationality_flags.dart';
import 'widgets/datos_mercado_sportmonks_section.dart';

/// Bottom sheet: carrera (sum3a de temporadas consultadas) + club actual + edad.
Future<void> showPlayerCareerSheet(
  BuildContext context, {
  required int playerId,
  required int clubTeamId,
  String? playerName,
  String? clubTeamName,
}) async {
  final nombre = playerName?.trim();
  if (nombre == null || nombre.isEmpty) {
    if (playerId <= 0) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2A3B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _PlayerCareerBody(
        playerId: playerId,
        clubTeamId: clubTeamId,
        fallbackName: playerName,
        clubTeamName: clubTeamName,
      ),
    ),
  );
}

class _PlayerCareerBody extends StatefulWidget {
  final int playerId;
  final int clubTeamId;
  final String? fallbackName;
  final String? clubTeamName;

  const _PlayerCareerBody({
    required this.playerId,
    required this.clubTeamId,
    this.fallbackName,
    this.clubTeamName,
  });

  @override
  State<_PlayerCareerBody> createState() => _PlayerCareerBodyState();
}

class _PlayerCareerBodyState extends State<_PlayerCareerBody> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getPlayerCareerSnapshot(
      playerId: widget.playerId,
      clubTeamId: widget.clubTeamId,
      playerName: widget.fallbackName,
      clubTeamName: widget.clubTeamName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: maxH,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF00C853))),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.hasError
                      ? 'No se pudo cargar el perfil (${snap.error})'
                      : 'No se pudo cargar el perfil.',
                  style: const TextStyle(color: Colors.white54),
                ),
              );
            }
            final d = snap.data!;
            final nombre = (d['nombre'] as String?)?.trim().isNotEmpty == true
                ? d['nombre'] as String
                : (widget.fallbackName ?? 'Jugador');
            final foto = d['foto'] as String? ?? '';
            final edad = d['edad'] as int?;
            final nac = d['nacimiento'] as String?;
            final muestras = d['temporadasMuestra'] as int? ?? 0;
            final totalPares = d['temporadasTotal'] as int? ?? 0;
            final nacionalidad = (d['nacionalidad'] as String?)?.trim();
            final paisNac = (d['paisNacimiento'] as String?)?.trim();
            final flagNat = flagEmojiFromCountryName(nacionalidad);
            final flag = flagNat.isNotEmpty ? flagNat : flagEmojiFromCountryName(paisNac);
            final dorsal = (d['dorsal'] as num?)?.toInt() ?? 0;
            final tieneSel = d['tieneSeleccion'] == true;
            final selDetalle = (d['seleccionDetalle'] as String?)?.trim();
            final pjSelTotal = (d['seleccionPjTotal'] as num?)?.toInt() ?? 0;
            final golesSelTotal = (d['seleccionGolesTotal'] as num?)?.toInt() ?? 0;
            final clubNom = (d['clubActualNombre'] as String?)?.trim() ?? '';
            final clubLog = (d['clubActualLogo'] as String?)?.trim() ?? '';
            final clubesHist =
                List<Map<String, dynamic>>.from(d['clubesHistorial'] as List? ?? []);

            Widget fila(String label, String valor, {Color valColor = Colors.white}) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(valor, style: TextStyle(color: valColor, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white12,
                          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                          child: foto.isEmpty
                              ? const Icon(Icons.person, color: Colors.white38, size: 28)
                              : null,
                        ),
                        if (flag.isNotEmpty)
                          Positioned(
                            right: -4,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1B2A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                              child: Text(flag, style: const TextStyle(fontSize: 15, height: 1.1)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(nombre,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                        ),
                        if (dorsal > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1B2A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00C853), width: 1),
                            ),
                            child: Text('#$dorsal',
                                style: const TextStyle(
                                    color: Color(0xFF00C853),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                      if (nacionalidad != null && nacionalidad.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            nacionalidad,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        )
                      else if (paisNac != null && paisNac.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Nac. en $paisNac',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      if (edad != null || (nac != null && nac.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (edad != null) '$edad años',
                              if (nac != null && nac.isNotEmpty) 'Nac.: $nac',
                            ].join(' · '),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                DatosMercadoSportmonksSection(key: ValueKey(nombre), playerName: nombre),
                if (clubNom.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFF00C853), width: 1),
                    ),
                    child: Row(children: [
                      if (clubLog.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            clubLog,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 36, height: 36),
                          ),
                        )
                      else
                        const Icon(Icons.shield, color: Color(0xFF00C853), size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text(
                            'CLUB (equipo de esta pantalla)',
                            style: TextStyle(
                              color: Color(0xFF00C853),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            clubNom,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ],
                if (tieneSel) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFFFFD700), width: 1),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('⚽', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text(
                            'INTERNACIONAL — SELECCIÓN',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Totales (suma de competiciones de selección en la API): $pjSelTotal PJ · $golesSelTotal goles',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          if (selDetalle != null && selDetalle.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              selDetalle,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11, height: 1.35),
                            ),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Registros con competiciones de selecciones (API).',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                ],
                if (clubesHist.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('CLUBES (nombre · escudo · año)',
                      style: TextStyle(
                          color: Color(0xFF00C853),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text(
                    'Historial según API-Sports (temporada = año de la edición).',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 10),
                  ),
                  const SizedBox(height: 8),
                  ...clubesHist.take(32).map((c) {
                    final nom = c['nombre'] as String? ?? '';
                    final logo = c['logo'] as String? ?? '';
                    final anio = c['anio'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: logo.isNotEmpty
                              ? Image.network(logo,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                        width: 32,
                                        height: 32,
                                        color: Colors.white12,
                                        child: const Icon(Icons.shield,
                                            color: Colors.white24, size: 18),
                                      ))
                              : Container(
                                  width: 32,
                                  height: 32,
                                  color: Colors.white12,
                                  child: const Icon(Icons.shield,
                                      color: Colors.white24, size: 18),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(nom,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('$anio',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                      ]),
                    );
                  }),
                ],
                const SizedBox(height: 20),
                const Text('EN ESTE CLUB (temporadas consultadas)',
                    style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                fila('Partidos', '${d['pjClub']}'),
                fila('Goles', '${d['golesClub']}', valColor: const Color(0xFF00C853)),
                fila('Rojas', '${d['rojasClub']}', valColor: const Color(0xFFFF5252)),
                const SizedBox(height: 16),
                const Text('CARRERA (suma API, clubes consultados)',
                    style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  'Suma de hasta $muestras filas club+temporada (de $totalPares en el historial). Puede faltar data antigua por límite de consultas.',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 8),
                fila('Partidos (aprox.)', '${d['pjCarrera']}'),
                fila('Goles (aprox.)', '${d['golesCarrera']}', valColor: const Color(0xFF00C853)),
                fila('Rojas (aprox.)', '${d['rojasCarrera']}', valColor: const Color(0xFFFF5252)),
              ],
            );
        },
      ),
    );
  }
}
