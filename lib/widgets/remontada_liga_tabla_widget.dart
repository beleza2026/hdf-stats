import 'package:flutter/material.dart';



import '../api_service.dart';

import '../services/remontada_service.dart';



class _FilaRemontadaTabla {

  const _FilaRemontadaTabla({

    required this.teamId,

    required this.nombre,

    required this.porcentaje,

    required this.muestra,

  });



  final int teamId;

  final String nombre;

  final double porcentaje;

  final int muestra;

}



/// Tabla tipo «TABLA MORAL»: % de victorias al recibir el 1.er gol (LPF), equipos de la tabla anual.

/// [StatefulWidget]: el `Future` se crea una sola vez; si no, cada `build` del padre relanzaba

/// decenas de llamadas a la API y vaciaba / corrompía datos (rate limit + race).

class RemontadaLigaTablaWidget extends StatefulWidget {

  const RemontadaLigaTablaWidget({

    super.key,

    this.onVerFixture,

  });



  final VoidCallback? onVerFixture;



  static const int _equiposAConsultar = 18;

  static const int _mostrarEnTabla = 12;

  /// Equipos en paralelo bajo (cada uno dispara muchos `/fixtures/events`).

  static const int _concurrencia = 2;



  static Future<List<_FilaRemontadaTabla>> _cargarTabla() async {

    final orden = await ApiService.getStandingsRowsParaRemontadaLpf();

    if (orden.isEmpty) return [];

    int pts(Map<String, dynamic> row) {

      final v = row['points'];

      if (v is int) return v;

      if (v is num) return v.toInt();

      return int.tryParse('$v') ?? 0;

    }

    orden.sort((a, b) => pts(b).compareTo(pts(a)));



    final season = ApiService.temporadaLigaPrincipal;

    final svc = RemontadaService();

    final acum = <_FilaRemontadaTabla>[];



    final slice = orden.take(_equiposAConsultar).toList();

    for (var i = 0; i < slice.length; i += _concurrencia) {

      final chunk = slice.skip(i).take(_concurrencia).toList();

      final parciales = await Future.wait(chunk.map((eq) async {

        final teamRaw = eq['team'];

        if (teamRaw is! Map) return null;

        final team = Map<String, dynamic>.from(teamRaw);

        final idRaw = team['id'];

        final teamId = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw') ?? 0);

        if (teamId <= 0) return null;

        final nombre = team['name'] as String? ?? '';

        final st = await svc.getRemontadaStats(teamId, season);

        return _FilaRemontadaTabla(

          teamId: teamId,

          nombre: nombre,

          porcentaje: st.porcentajeRemontada,

          muestra: st.totalPartidosAbajo,

        );

      }));

      for (final r in parciales) {

        if (r != null) acum.add(r);

      }

    }



    acum.sort((a, b) => b.porcentaje.compareTo(a.porcentaje));

    return acum.take(_mostrarEnTabla).toList();

  }



  @override

  State<RemontadaLigaTablaWidget> createState() => _RemontadaLigaTablaWidgetState();

}



class _RemontadaLigaTablaWidgetState extends State<RemontadaLigaTablaWidget> {

  late final Future<List<_FilaRemontadaTabla>> _future = RemontadaLigaTablaWidget._cargarTabla();



  @override

  Widget build(BuildContext context) {

    return FutureBuilder<List<_FilaRemontadaTabla>>(

      future: _future,

      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {

          return Container(

            width: double.infinity,

            padding: const EdgeInsets.all(20),

            decoration: BoxDecoration(

              color: const Color(0xFF1B2A3B),

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.35)),

            ),

            child: const Column(

              children: [

                SizedBox(height: 8),

                CircularProgressIndicator(color: Color(0xFF00C853), strokeWidth: 2),

                SizedBox(height: 12),

                Text('Cargando tabla de remontadas…', style: TextStyle(color: Colors.white38, fontSize: 12)),

              ],

            ),

          );

        }



        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {

          return Container(

            width: double.infinity,

            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(

              color: const Color(0xFF1B2A3B),

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: Colors.white12),

            ),

            child: Text(

              snapshot.hasError

                  ? 'No se pudo armar la tabla de remontadas.'

                  : 'Sin datos de tabla de posiciones para listar equipos.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),

            ),

          );

        }



        final filas = snapshot.data!;

        return Container(

          width: double.infinity,

          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(

            color: const Color(0xFF1B2A3B),

            borderRadius: BorderRadius.circular(14),

            border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.45)),

            boxShadow: [

              BoxShadow(

                color: const Color(0xFF00C853).withValues(alpha: 0.08),

                blurRadius: 18,

                offset: const Offset(0, 6),

              ),

            ],

          ),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Row(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Container(

                    padding: const EdgeInsets.all(8),

                    decoration: BoxDecoration(

                      color: const Color(0xFF00C853).withValues(alpha: 0.12),

                      borderRadius: BorderRadius.circular(10),

                    ),

                    child: const Icon(Icons.trending_up_rounded, color: Color(0xFF00C853), size: 22),

                  ),

                  const SizedBox(width: 10),

                  Expanded(

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        const Text(

                          'REMONTADA',

                          style: TextStyle(

                            color: Color(0xFF00C853),

                            fontSize: 12,

                            fontWeight: FontWeight.bold,

                            letterSpacing: 1.8,

                          ),

                        ),

                        const SizedBox(height: 2),

                        Text(

                          '% victorias al recibir el 1.er gol · LPF ${ApiService.temporadaLigaPrincipal}',

                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, height: 1.25),

                        ),

                      ],

                    ),

                  ),

                  if (widget.onVerFixture != null)

                    GestureDetector(

                      onTap: widget.onVerFixture,

                      child: const Padding(

                        padding: EdgeInsets.only(left: 4, top: 2),

                        child: Text('Fixture ›', style: TextStyle(color: Colors.white38, fontSize: 10)),

                      ),

                    ),

                ],

              ),

              const SizedBox(height: 6),

              Text(

                'Mín. ${RemontadaStats.minPartidosRecibePrimerGol} partidos abajo para mostrar % · Top ${filas.length} equipos',

                style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 9),

              ),

              const SizedBox(height: 12),

              Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),

              const SizedBox(height: 8),

              ...filas.asMap().entries.map((e) {

                final idx = e.key;

                final f = e.value;

                final medals = ['🥇', '🥈', '🥉'];

                final suf = idx < 3 ? medals[idx] : '${idx + 1}.';

                final ok = f.muestra >= RemontadaStats.minPartidosRecibePrimerGol;

                final valor = ok ? '${f.porcentaje.toStringAsFixed(0)}%' : '—';

                final sub = ok ? '${f.muestra} PJ' : '${f.muestra} muestra';

                return Padding(

                  padding: const EdgeInsets.symmetric(vertical: 5),

                  child: Row(

                    children: [

                      SizedBox(

                        width: 28,

                        child: Text(suf, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center),

                      ),

                      const SizedBox(width: 6),

                      Expanded(

                        child: Text(

                          f.nombre,

                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                        ),

                      ),

                      Column(

                        crossAxisAlignment: CrossAxisAlignment.end,

                        children: [

                          Text(

                            valor,

                            style: TextStyle(

                              color: ok ? const Color(0xFF00C853) : Colors.white38,

                              fontSize: 15,

                              fontWeight: FontWeight.w800,

                            ),

                          ),

                          Text(

                            sub,

                            style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 9),

                          ),

                        ],

                      ),

                    ],

                  ),

                );

              }),

            ],

          ),

        );

      },

    );

  }

}


