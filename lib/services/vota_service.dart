import 'package:cloud_firestore/cloud_firestore.dart';

/// Totales de votación de un fixture.
class VotaTotals {
  const VotaTotals({
    required this.local,
    required this.empate,
    required this.visitante,
    required this.total,
  });

  final int local;
  final int empate;
  final int visitante;
  final int total;

  static const empty = VotaTotals(local: 0, empate: 0, visitante: 0, total: 0);

  factory VotaTotals.fromMap(Map<String, dynamic>? data) {
    if (data == null) return VotaTotals.empty;
    int n(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return VotaTotals(
      local: n(data['local']),
      empate: n(data['empate']),
      visitante: n(data['visitante']),
      total: n(data['total']),
    );
  }

  int countFor(String voto) {
    switch (voto) {
      case 'local':
        return local;
      case 'empate':
        return empate;
      case 'visitante':
        return visitante;
      default:
        return 0;
    }
  }

  int percentFor(String voto) {
    if (total <= 0) return 33;
    return ((countFor(voto) / total) * 100).round();
  }

  String? winnerKey() {
    if (total <= 0) return null;
    final m = {
      'local': local,
      'empate': empate,
      'visitante': visitante,
    };
    return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class VotaAlreadyVotedException implements Exception {}

class VotaService {
  static const String collectionLiga = 'votos';

  static DocumentReference<Map<String, dynamic>> _fixtureDoc(
    String fixtureId, {
    String collection = collectionLiga,
  }) =>
      FirebaseFirestore.instance.collection(collection).doc(fixtureId);

  static DocumentReference<Map<String, dynamic>> _userDoc(
    String fixtureId,
    String uid, {
    String collection = collectionLiga,
  }) =>
      _fixtureDoc(fixtureId, collection: collection).collection('usuarios').doc(uid);

  static Stream<VotaTotals> watchTotals(
    String fixtureId, {
    String collection = collectionLiga,
  }) {
    return _fixtureDoc(fixtureId, collection: collection)
        .snapshots()
        .map((s) => VotaTotals.fromMap(s.data()));
  }

  static Stream<String?> watchUserVote(
    String fixtureId,
    String uid, {
    String collection = collectionLiga,
  }) {
    return _userDoc(fixtureId, uid, collection: collection)
        .snapshots()
        .map((s) => s.data()?['voto'] as String?);
  }

  /// Partido próximo: se puede votar. En juego o finalizado: solo resultados.
  static bool puedeVotar({
    required bool jugado,
    required bool isLive,
    String? statusShort,
  }) {
    if (jugado || isLive) return false;
    final s = (statusShort ?? '').toUpperCase();
    if (s == 'NS' || s == 'TBD' || s == 'PST' || s.isEmpty) return true;
    return false;
  }

  static bool soloResultados({
    required bool jugado,
    required bool isLive,
    String? statusShort,
  }) =>
      !puedeVotar(jugado: jugado, isLive: isLive, statusShort: statusShort);

  static Future<void> castVote({
    required String fixtureId,
    required String uid,
    required String voto,
    String collection = collectionLiga,
  }) async {
    if (voto != 'local' && voto != 'empate' && voto != 'visitante') {
      throw ArgumentError('voto inválido');
    }
    final fixtureRef = _fixtureDoc(fixtureId, collection: collection);
    final userRef = _userDoc(fixtureId, uid, collection: collection);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      if (userSnap.exists && (userSnap.data()?['voto'] as String?)?.isNotEmpty == true) {
        throw VotaAlreadyVotedException();
      }

      final docSnap = await tx.get(fixtureRef);
      if (!docSnap.exists) {
        tx.set(fixtureRef, {
          'local': voto == 'local' ? 1 : 0,
          'empate': voto == 'empate' ? 1 : 0,
          'visitante': voto == 'visitante' ? 1 : 0,
          'total': 1,
        });
      } else {
        tx.update(fixtureRef, {
          voto: FieldValue.increment(1),
          'total': FieldValue.increment(1),
        });
      }
      tx.set(userRef, {'voto': voto});
    });
  }
}
