// lib/racha_model.dart
// Modelo de rachas por equipo — sin ganar / sin perder general, local, visitante

class PartidoRacha {
  final DateTime fecha;
  final String resultado; // 'W', 'D', 'L'
  final bool esLocal;

  const PartidoRacha({
    required this.fecha,
    required this.resultado,
    required this.esLocal,
  });
}

class RachaEquipo {
  final int teamId;
  final String teamName;
  final String teamLogo;

  // Sin ganar (partidos consecutivos sin victoria desde el último)
  final int sinGanarGeneral;
  final int sinGanarLocal;
  final int sinGanarVisitante;

  // Sin perder (partidos consecutivos sin derrota desde el último)
  final int sinPerderGeneral;
  final int sinPerderLocal;
  final int sinPerderVisitante;

  // Últimos 5 resultados (más reciente primero)
  final List<String> ultimos5; // ['W','D','L','W','W']

  // Racha actual de resultados consecutivos iguales
  final String rachaActualTipo; // 'W', 'D', 'L'
  final int rachaActualCount;

  const RachaEquipo({
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.sinGanarGeneral,
    required this.sinGanarLocal,
    required this.sinGanarVisitante,
    required this.sinPerderGeneral,
    required this.sinPerderLocal,
    required this.sinPerderVisitante,
    required this.ultimos5,
    required this.rachaActualTipo,
    required this.rachaActualCount,
  });

  /// Calcula rachas a partir de la lista de partidos jugados (ordenados desc por fecha)
  factory RachaEquipo.fromPartidos({
    required int teamId,
    required String teamName,
    required String teamLogo,
    required List<PartidoRacha> partidos, // ya ordenados desc
  }) {
    int _calcSinGanar(List<PartidoRacha> lista) {
      int count = 0;
      for (final p in lista) {
        if (p.resultado == 'W') break;
        count++;
      }
      return count;
    }

    int _calcSinPerder(List<PartidoRacha> lista) {
      int count = 0;
      for (final p in lista) {
        if (p.resultado == 'L') break;
        count++;
      }
      return count;
    }

    final locales = partidos.where((p) => p.esLocal).toList();
    final visitantes = partidos.where((p) => !p.esLocal).toList();

    final ultimos5 = partidos.take(5).map((p) => p.resultado).toList();

    // Racha actual consecutiva
    String rachaActualTipo = partidos.isNotEmpty ? partidos.first.resultado : '-';
    int rachaActualCount = 0;
    for (final p in partidos) {
      if (p.resultado == rachaActualTipo) {
        rachaActualCount++;
      } else {
        break;
      }
    }

    return RachaEquipo(
      teamId: teamId,
      teamName: teamName,
      teamLogo: teamLogo,
      sinGanarGeneral: _calcSinGanar(partidos),
      sinGanarLocal: _calcSinGanar(locales),
      sinGanarVisitante: _calcSinGanar(visitantes),
      sinPerderGeneral: _calcSinPerder(partidos),
      sinPerderLocal: _calcSinPerder(locales),
      sinPerderVisitante: _calcSinPerder(visitantes),
      ultimos5: ultimos5,
      rachaActualTipo: rachaActualTipo,
      rachaActualCount: rachaActualCount,
    );
  }
}
