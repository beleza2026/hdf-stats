import 'vota_service.dart';

/// Votación Mundial — colección `votos_mundial` (separada de liga).
class VotaMundialService {
  VotaMundialService._();

  static const String collection = 'votos_mundial';

  static Stream<VotaTotals> watchTotals(String fixtureId) =>
      VotaService.watchTotals(fixtureId, collection: collection);

  static Stream<String?> watchUserVote(String fixtureId, String uid) =>
      VotaService.watchUserVote(fixtureId, uid, collection: collection);

  static bool puedeVotar({
    required bool jugado,
    required bool isLive,
    String? statusShort,
  }) =>
      VotaService.puedeVotar(
        jugado: jugado,
        isLive: isLive,
        statusShort: statusShort,
      );

  static Future<void> castVote({
    required String fixtureId,
    required String uid,
    required String voto,
  }) =>
      VotaService.castVote(
        fixtureId: fixtureId,
        uid: uid,
        voto: voto,
        collection: collection,
      );
}
