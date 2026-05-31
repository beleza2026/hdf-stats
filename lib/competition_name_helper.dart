/// Nombres de competencia tal como los muestra la UI (API-Sports / Sportmonks).
String sanitizarNombreCompetencia(String nombre) {
  final t = nombre.trim();
  final lower = t.toLowerCase();
  if (lower.contains('world cup') || lower.contains('copa mundial')) {
    return 'Mundial 2026';
  }
  return t;
}
