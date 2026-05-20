import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paywall_screen.dart';
import 'services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Partidos marcados manualmente para notificaciones push.
///
/// **FCM topic por partido:** `mg_fixture_{fixtureId}` (API-Football fixture id).
/// **Equipo favorito** sigue usando `equipo_{teamId}` en [MainScreen._inicializarFCM].
///
/// El backend debe enviar a:
/// - `equipo_{id}` → alertas ligadas al club favorito del usuario
/// - `mg_fixture_{id}` → alertas solo para quien marcó ese partido
class MatchFollowService {
  MatchFollowService._();

  static const String prefsKey = 'followed_fixture_ids_v1';
  static const int maxFollows = 40;

  static String fcmTopicForFixture(int fixtureId) => 'mg_fixture_$fixtureId';

  static Future<List<int>> getFollowedIds() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(prefsKey) ?? [];
    final set = raw.map((s) => int.tryParse(s) ?? 0).where((x) => x > 0).toSet();
    return set.toList()..sort();
  }

  static Future<bool> isFollowing(int fixtureId) async {
    final ids = await getFollowedIds();
    return ids.contains(fixtureId);
  }

  /// Llamar al iniciar FCM tras permisos (re-suscribe topics guardados).
  static Future<void> subscribeAllSavedTopics() async {
    if (kIsWeb) return;
    final ids = await getFollowedIds();
    final m = FirebaseMessaging.instance;
    for (final id in ids) {
      try {
        await m.subscribeToTopic(fcmTopicForFixture(id));
      } catch (e) {
        debugPrint('FCM subscribe ${fcmTopicForFixture(id)}: $e');
      }
    }
  }

  static Future<FollowToggleOutcome> toggle(int fixtureId) async {
    if (kIsWeb || fixtureId <= 0) return FollowToggleOutcome.none;
    final p = await SharedPreferences.getInstance();
    var ids = await getFollowedIds();
    final m = FirebaseMessaging.instance;
    final topic = fcmTopicForFixture(fixtureId);

    if (ids.contains(fixtureId)) {
      ids = List<int>.from(ids)..remove(fixtureId);
      try {
        await m.unsubscribeFromTopic(topic);
      } catch (_) {}
      await _saveIds(p, ids);
      return FollowToggleOutcome.unfollowed;
    }

    if (ids.length >= maxFollows) return FollowToggleOutcome.limitReached;

    ids = [...ids, fixtureId];
    try {
      await m.subscribeToTopic(topic);
    } catch (_) {}
    await _saveIds(p, ids);
    return FollowToggleOutcome.followed;
  }

  static Future<void> _saveIds(SharedPreferences p, List<int> ids) async {
    await p.setStringList(prefsKey, ids.map((e) => '$e').toList());
  }
}

enum FollowToggleOutcome { followed, unfollowed, limitReached, none }

/// Campanita en filas de partido: suscripción a [MatchFollowService.fcmTopicForFixture].
class MatchFollowToggle extends StatefulWidget {
  final int fixtureId;

  const MatchFollowToggle({super.key, required this.fixtureId});

  @override
  State<MatchFollowToggle> createState() => _MatchFollowToggleState();
}

class _MatchFollowToggleState extends State<MatchFollowToggle> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await MatchFollowService.isFollowing(widget.fixtureId);
    if (mounted) setState(() => _on = v);
  }

  Future<void> _tap() async {
    if (_busy) return;
    if (!PremiumService.unlockAllForPreview && !await PremiumService.isPremium()) {
      if (!mounted) return;
      final ok = await PaywallScreen.open(context);
      if (!mounted || ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await MatchFollowService.toggle(widget.fixtureId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == FollowToggleOutcome.followed) {
      setState(() => _on = true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Recibirás alertas de este partido (además de tu equipo favorito, si aplica).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (r == FollowToggleOutcome.unfollowed) {
      setState(() => _on = false);
    } else if (r == FollowToggleOutcome.limitReached) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Máximo ${MatchFollowService.maxFollows} partidos con alertas manuales.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    if (_on == null) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: _on! ? 'Quitar alertas push de este partido' : 'Activar alertas push de este partido',
      icon: Icon(
        _on! ? Icons.notifications_active : Icons.notifications_none_outlined,
        color: _on! ? const Color(0xFF00C853) : Colors.white38,
        size: 22,
      ),
      onPressed: _busy ? null : _tap,
    );
  }
}
