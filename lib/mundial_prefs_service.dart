import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias locales del Mundial: filtros, quiniela y alertas (sin backend).
class MundialPrefsService {
  MundialPrefsService._();

  static const _filterTeamId = 'mundial_filter_team_id_v1';
  static const _filterTeamName = 'mundial_filter_team_name_v1';
  static const _quinielaJson = 'mundial_quiniela_v1';
  static const _alertSelectionId = 'mundial_alert_selection_id_v1';
  static const _alertSelectionName = 'mundial_alert_selection_name_v1';
  static const _remindersEnabled = 'mundial_local_reminders_v1';

  static Future<int?> getFilterTeamId() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_filterTeamId);
    if (id == null || id <= 0) return null;
    return id;
  }

  static Future<String?> getFilterTeamName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_filterTeamName);
  }

  static Future<void> setFilterTeam(int? teamId, String? name) async {
    final p = await SharedPreferences.getInstance();
    if (teamId == null || teamId <= 0) {
      await p.remove(_filterTeamId);
      await p.remove(_filterTeamName);
      return;
    }
    await p.setInt(_filterTeamId, teamId);
    await p.setString(_filterTeamName, name ?? '');
  }

  static Future<void> clearFilterTeam() => setFilterTeam(null, null);

  static Future<Map<int, String>> getQuiniela() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_quinielaJson);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(int.tryParse(k) ?? 0, v.toString())).entries
          .where((e) => e.key > 0)
          .fold<Map<int, String>>({}, (acc, e) => acc..[e.key] = e.value);
    } catch (_) {
      return {};
    }
  }

  static Future<void> setQuinielaPrediction(int fixtureId, String score) async {
    if (fixtureId <= 0) return;
    final all = await getQuiniela();
    if (score.trim().isEmpty) {
      all.remove(fixtureId);
    } else {
      all[fixtureId] = score.trim();
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _quinielaJson,
      json.encode(all.map((k, v) => MapEntry('$k', v))),
    );
  }

  /// Puntos quiniela: 3 exacto, 1 acierto de resultado (1X2).
  static int puntosQuiniela(String prediccion, int golesLocal, int golesVisit) {
    final parts = prediccion.split(RegExp(r'[-:xX\s]+'));
    if (parts.length < 2) return 0;
    final ph = int.tryParse(parts[0].trim()) ?? -1;
    final pa = int.tryParse(parts[1].trim()) ?? -1;
    if (ph < 0 || pa < 0) return 0;
    if (ph == golesLocal && pa == golesVisit) return 3;
    final rPred = ph == pa ? 0 : (ph > pa ? 1 : -1);
    final rReal = golesLocal == golesVisit ? 0 : (golesLocal > golesVisit ? 1 : -1);
    return rPred == rReal ? 1 : 0;
  }

  static Future<int> totalPuntosQuiniela(List<Map<String, dynamic>> partidosFt) async {
    final q = await getQuiniela();
    var pts = 0;
    for (final p in partidosFt) {
      final fid = (p['fixture']?['id'] as num?)?.toInt();
      if (fid == null || !q.containsKey(fid)) continue;
      final gh = (p['goals']?['home'] as num?)?.toInt() ?? 0;
      final ga = (p['goals']?['away'] as num?)?.toInt() ?? 0;
      pts += puntosQuiniela(q[fid]!, gh, ga);
    }
    return pts;
  }

  static Future<int?> getAlertSelectionId() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_alertSelectionId);
    if (id != null && id > 0) return id;
    return p.getInt('equipo_favorito_id');
  }

  static Future<String?> getAlertSelectionName() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString(_alertSelectionName);
    if (n != null && n.isNotEmpty) return n;
    return p.getString('equipo_favorito_nombre');
  }

  static Future<void> setAlertSelection(int teamId, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_alertSelectionId, teamId);
    await p.setString(_alertSelectionName, name);
  }

  static Future<bool> remindersEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_remindersEnabled) ?? false;
  }

  static Future<void> setRemindersEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_remindersEnabled, v);
  }
}
