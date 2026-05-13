/// Marcador e incidencias de **tanda de penales** (API-Football: `score.penalty` + eventos).
class PenalesShootoutHelper {
  PenalesShootoutHelper._();

  static int? _toIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Lee `partido['score']['penalty']` (mismo nodo que en listados y en `fixtures?id=`).
  static Map<String, int>? leerMarcadorPenales(Map<String, dynamic>? partidoRoot) {
    if (partidoRoot == null) return null;
    final sc = partidoRoot['score'];
    if (sc is! Map<String, dynamic>) return null;
    final pen = sc['penalty'];
    if (pen is! Map<String, dynamic>) return null;
    final h = _toIntNullable(pen['home']);
    final a = _toIntNullable(pen['away']);
    if (h == null || a == null) return null;
    return {'home': h, 'away': a};
  }

  /// Texto tipo ` (4-5 pen)` para mostrar junto al resultado reglamentario.
  static String? sufijoMarcadorParentesis(Map<String, dynamic>? partidoRoot) {
    final m = leerMarcadorPenales(partidoRoot);
    if (m == null) return null;
    return ' (${m['home']}-${m['away']} pen)';
  }

  static String statusShortDesdePartido(Map<String, dynamic>? partidoRoot) {
    if (partidoRoot == null) return '';
    final fx = partidoRoot['fixture'];
    if (fx is! Map<String, dynamic>) return '';
    final st = fx['status'];
    if (st is! Map) return '';
    return (st['short'] as String?) ?? '';
  }

  static bool haySeriePenalesDefinida(Map<String, dynamic>? partidoRoot) =>
      leerMarcadorPenales(partidoRoot) != null;

  /// Si el evento corresponde a un tiro de la tanda (no penal en juego normal).
  static bool esEventoTandaPenales(
    Map<String, dynamic> e,
    String statusShort,
    Map<String, dynamic>? partidoRoot,
  ) {
    final hayP = haySeriePenalesDefinida(partidoRoot);
    final tipo = (e['type'] ?? '').toString();
    final detail = (e['detail'] ?? '').toString().toLowerCase();
    final comments = ((e['comments'] ?? '') ?? '').toString().toLowerCase();

    if (detail.contains('penalty shootout') || comments.contains('penalty shootout')) return true;
    if (comments.contains('shootout') && detail.contains('penal')) return true;

    if (!hayP || statusShort != 'PEN') return false;

    final rawElapsed = (e['time'] as Map?)?['elapsed'];
    final el = rawElapsed is int ? rawElapsed : int.tryParse('$rawElapsed') ?? 0;

    if (tipo == 'Goal') {
      if (detail.contains('missed')) return true;
      if (detail.contains('shootout')) return true;
      if (detail == 'penalty' && el >= 119) return true;
    }
    return false;
  }

  /// Texto de incidencia: quién pateó y resultado del tiro.
  static String textoIncidenciaSeriePenales(Map<String, dynamic> e) {
    final nombre = (e['player'] as Map?)?['name']?.toString().trim();
    final jugador = (nombre == null || nombre.isEmpty) ? '?' : nombre;
    final detail = (e['detail'] ?? '').toString();
    final dl = detail.toLowerCase();
    final comments = ((e['comments'] ?? '') ?? '').toString().toLowerCase();

    if (dl.contains('miss') || dl.contains('missed')) {
      if (comments.contains('save') ||
          comments.contains('keeper') ||
          comments.contains('goalkeeper') ||
          comments.contains('atajad')) {
        return 'Penales — $jugador: atajado';
      }
      return 'Penales — $jugador: afuera';
    }
    return 'Penales — $jugador: gol';
  }

  /// Minuto a mostrar: en tanda usamos etiqueta corta.
  static String minutoIncidenciaSerie(Map<String, dynamic> e, String minutoRegla) {
    final detail = (e['detail'] ?? '').toString().toLowerCase();
    if (detail.contains('shootout')) return 'Pen.';
    final elRaw = (e['time'] as Map?)?['elapsed'];
    final el = elRaw is int ? elRaw : int.tryParse('$elRaw') ?? 0;
    if (el >= 91) return 'Pen.';
    return minutoRegla;
  }

  /// Prefer el mapa que traiga `score.penalty` (lista o detalle).
  static Map<String, dynamic>? refPartidoConScorePen(
    Map<String, dynamic>? lista,
    Map<String, dynamic>? det,
  ) {
    if (haySeriePenalesDefinida(lista)) return lista;
    if (haySeriePenalesDefinida(det)) return det;
    return lista ?? det;
  }

  static String resultadoConPenales(
    String resultadoBase,
    Map<String, dynamic>? partidoLista,
    Map<String, dynamic>? detallePartido,
  ) {
    final t = resultadoBase.trim();
    if (t.contains(' pen)')) return t;
    final suf = sufijoMarcadorParentesis(partidoLista) ?? sufijoMarcadorParentesis(detallePartido);
    if (suf == null) return t;
    return t + suf;
  }
}
