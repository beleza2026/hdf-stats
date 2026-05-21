/// Modelo FREE vs PREMIUM — fuente única para gates en la app.
abstract final class PremiumAccess {
  /// Hub Liga (`MainScreen._selectedIndex`).
  ///
  /// FREE: 0 HOY, 1 Tablas (solo POSICIONES), 2 Goleadores (solo tab goleadores),
  /// 4 Fixture, 5 En vivo, 7 Mundial, 8 Noticias, 15 Copa Argentina, 18 Tabla hinchas.
  ///
  /// PREMIUM: predicciones/VOTA, índice, monitor bajas, remontada, árbitros, stats
  /// avanzadas, cuerda floja, Libertadores, Sudamericana, etc.
  static const Set<int> ligaSectionIndicesPremium = {
    3, // Arqueros
    6, // Predicciones / VOTA
    9, // Copa Libertadores
    10, // Copa Sudamericana
    11, // Al filo (monitor bajas)
    12, // Expulsados
    13, // Tabla posesión
    14, // En la cuerda floja
    16, // Remontada
    17, // Lesionados
    19, // Árbitros
  };

  /// Tabs internas de Tablas (solo índice 0 POSICIONES es FREE).
  static const Set<int> ligaTablasIndicesPremium = {
    1, // Local
    2, // Visitante
    3, // Últimos 5
    4, // 1.er tiempo
    5, // 2.do tiempo
    6, // Moral
    7, // Cruces
    8, // Anual
    9, // Promedios
    10, // Equipo de la fecha
    11, // Rachas
  };

  /// Mundial 2026 — tabs FREE: HOY, FIXTURE, GRUPOS, CRUCES.
  static const Set<int> mundialTabIndicesFree = {0, 1, 2, 4};

  static bool ligaSectionRequiresPremium(int index) =>
      ligaSectionIndicesPremium.contains(index);

  static bool mundialTabIsFree(int index) => mundialTabIndicesFree.contains(index);

  static bool mundialTabRequiresPremium(int index) => !mundialTabIsFree(index);
}
