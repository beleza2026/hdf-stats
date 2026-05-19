import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fila del ranking de hinchas.
class HinchasTeamRow {
  const HinchasTeamRow({
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.count,
  });

  final int teamId;
  final String teamName;
  final String teamLogo;
  final int count;
}

class HinchasService {
  static CollectionReference<Map<String, dynamic>> get _hinchas =>
      FirebaseFirestore.instance.collection('hinchas');

  static DocumentReference<Map<String, dynamic>> _hinchaDoc(int teamId) =>
      _hinchas.doc(teamId.toString());

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('usuarios').doc(uid);

  static int countFromData(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final c = data['count'];
    if (c is num) return c.toInt();
    final legacy = data['votos'];
    if (legacy is num) return legacy.toInt();
    return 0;
  }

  static String nameFromData(Map<String, dynamic>? data) =>
      data?['teamName'] as String? ?? data?['nombre'] as String? ?? 'Equipo';

  static String logoFromData(Map<String, dynamic>? data) =>
      data?['teamLogo'] as String? ?? data?['escudo'] as String? ?? '';

  /// Sin `orderBy` en Firestore: compatibilidad con docs legacy (`votos` sin `count`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRanking() => _hinchas.snapshots();

  static Map<int, HinchasTeamRow> rowsFromSnapshot(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <int, HinchasTeamRow>{};
    for (final d in docs) {
      final data = d.data();
      final teamId = (data['teamId'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0;
      if (teamId <= 0) continue;
      map[teamId] = HinchasTeamRow(
        teamId: teamId,
        teamName: nameFromData(data),
        teamLogo: logoFromData(data),
        count: countFromData(data),
      );
    }
    return map;
  }

  /// Registra o cambia el equipo favorito (transacción Firestore + prefs locales).
  static Future<void> setFavoriteTeam({
    required int teamId,
    required String teamName,
    required String teamLogo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Usuario no autenticado');
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsPrev = prefs.getInt('equipo_favorito_id');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userRef = _userDoc(uid);
      final userSnap = await tx.get(userRef);
      final prevFromUser = (userSnap.data()?['favoriteTeamId'] as num?)?.toInt();
      final prev = prevFromUser ?? prefsPrev;

      if (prev != null && prev != -1 && prev != teamId) {
        final prevRef = _hinchaDoc(prev);
        final prevSnap = await tx.get(prevRef);
        if (prevSnap.exists) {
          tx.update(prevRef, {
            'count': FieldValue.increment(-1),
            'votos': FieldValue.increment(-1),
          });
        }
      }

      if (prev != teamId) {
        final newRef = _hinchaDoc(teamId);
        final newSnap = await tx.get(newRef);
        final payload = {
          'teamId': teamId,
          'teamName': teamName,
          'teamLogo': teamLogo,
          'nombre': teamName,
          'escudo': teamLogo,
        };
        if (!newSnap.exists) {
          tx.set(newRef, {...payload, 'count': 1, 'votos': 1});
        } else {
          tx.update(newRef, {
            'teamId': teamId,
            'teamName': teamName,
            'teamLogo': teamLogo,
            'nombre': teamName,
            'escudo': teamLogo,
            'count': FieldValue.increment(1),
            'votos': FieldValue.increment(1),
          });
        }
      } else {
        tx.set(
          _hinchaDoc(teamId),
          {
            'teamId': teamId,
            'teamName': teamName,
            'teamLogo': teamLogo,
            'nombre': teamName,
            'escudo': teamLogo,
          },
          SetOptions(merge: true),
        );
      }

      tx.set(userRef, {'favoriteTeamId': teamId}, SetOptions(merge: true));
    });

    await prefs.setInt('equipo_favorito_id', teamId);
    await prefs.setString('equipo_favorito_nombre', teamName);
  }

  /// Quita equipo favorito (omitir) y descuenta el contador si correspondía.
  static Future<void> clearFavoriteTeam() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final prefsPrev = prefs.getInt('equipo_favorito_id');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userRef = _userDoc(uid);
      final userSnap = await tx.get(userRef);
      final prevFromUser = (userSnap.data()?['favoriteTeamId'] as num?)?.toInt();
      final prev = prevFromUser ?? prefsPrev;

      if (prev != null && prev != -1) {
        final prevRef = _hinchaDoc(prev);
        final prevSnap = await tx.get(prevRef);
        if (prevSnap.exists) {
          tx.update(prevRef, {
            'count': FieldValue.increment(-1),
            'votos': FieldValue.increment(-1),
          });
        }
      }
      tx.set(userRef, {'favoriteTeamId': FieldValue.delete()}, SetOptions(merge: true));
    });

    await prefs.setInt('equipo_favorito_id', -1);
    await prefs.remove('equipo_favorito_nombre');
  }

  static Future<int?> favoriteTeamIdFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('equipo_favorito_id');
    if (id == null || id == -1) return null;
    return id;
  }
}
