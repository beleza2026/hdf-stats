/// Nombres de competencia tal como los muestra la UI (API-Sports / Sportmonks).
String sanitizarNombreCompetencia(String nombre) {
  return nombre
      .replaceAll('FIFA World Cup', 'Mundial 2026')
      .replaceAll('FIFA ', '');
}
