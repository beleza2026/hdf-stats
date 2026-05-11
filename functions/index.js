/**
 * MatchGol Stats — Cloud Functions
 * Notificaciones automáticas de partidos en vivo.
 *
 * Envía a FCM a los mismos topics que usa la app Flutter:
 *   FREE:    mg_fixture_{fixtureId}, equipo_{teamId}
 *   PREMIUM: premium_fixture_{fixtureId}, premium_equipo_{teamId}
 *
 * Eventos FREE:    Inicio de partido, Inicio 2do tiempo, Goles, Resultado final
 * Eventos PREMIUM: 15 min antes + árbitro, Formaciones, Tarjeta roja, Resumen post-partido
 *
 * Requisitos: plan Blaze, secreto APISPORTS_KEY, deploy de functions.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

const apisportsKey = defineSecret("APISPORTS_KEY");

const API_BASE = "https://v3.football.api-sports.io";
const SEASON = 2026;

/** Liga Profesional + copas (130 = Copa Argentina, misma id que ApiService._copaArgentina) */
const LEAGUE_LIGA_ARG = 128;
const LEAGUE_COPA_ARGENTINA = 130;
const LEAGUE_LIBERTADORES = 13;
const LEAGUE_SUDAMERICANA = 14;
/** La Liga (España) — playoffs y fase regular suelen compartir league id en API-Sports */
const LEAGUE_LA_LIGA_ES = 140;

/**
 * Clubes argentinos (LPF + copas). Debe incluir a todos los que juegan Libertadores/Sudamericana
 * con filtro `filterArgentinaOnly`; si falta un id, ese partido NO entra al poll en vivo.
 * Rosario Central = 437 (antes faltaba → no llegaban alertas en copas).
 */
const ARG_TEAM_IDS = new Set([
  434, 435, 436, 437, 438, 440, 441, 442, 445, 446, 449, 450, 451, 452, 453, 455, 456, 457, 458,
  460, 463, 473, 474, 476, 478, 1064, 1065, 1066, 2424, 2432,
]);

/**
 * Varias competencias usan el año calendario del torneo distinto al nuestro (SEASON).
 * - Liga Profesional (128) y Copa Argentina (130): playoffs a veces quedan bajo season anterior.
 * - La Liga ES (140): en Europa season = año de inicio (p. ej. 2025 para 25/26).
 */
function seasonsForLeague(leagueId) {
  if (
    leagueId === LEAGUE_LIGA_ARG ||
    leagueId === LEAGUE_COPA_ARGENTINA ||
    leagueId === LEAGUE_LA_LIGA_ES
  ) {
    return [SEASON, SEASON - 1];
  }
  return [SEASON];
}

const STATE_COLLECTION = "auto_goal_notify";
const PRE_MATCH_COLLECTION = "pre_match_notified";

if (!admin.apps.length) {
  admin.initializeApp();
}

// ─── FCM conditions ───────────────────────────────────────────────────────────

/** FREE: hasta 5 topics; usamos 3. */
function topicCondition(fixtureId, homeTeamId, awayTeamId) {
  return (
    `'mg_fixture_${fixtureId}' in topics || ` +
    `'equipo_${homeTeamId}' in topics || ` +
    `'equipo_${awayTeamId}' in topics`
  );
}

/** PREMIUM: topics separados; la app los suscribe solo a usuarios premium. */
function premiumCondition(fixtureId, homeTeamId, awayTeamId) {
  return (
    `'premium_fixture_${fixtureId}' in topics || ` +
    `'premium_equipo_${homeTeamId}' in topics || ` +
    `'premium_equipo_${awayTeamId}' in topics`
  );
}

// ─── Helpers FCM ─────────────────────────────────────────────────────────────

async function sendFreeNotification(fixtureId, hid, aid, title, body, extraData = {}) {
  try {
    await admin.messaging().send({
      condition: topicCondition(fixtureId, hid, aid),
      notification: { title, body },
      data: { fixtureId: String(fixtureId), type: extraData.type || "general", ...extraData },
      android: {
        priority: "high",
        notification: { channelId: "hdf_partidos", sound: "default" },
      },
    });
    console.log(`FCM FREE enviado: ${title} | fixture=${fixtureId}`);
  } catch (e) {
    console.error(`FCM FREE falló fixture=${fixtureId}`, e);
  }
}

async function sendPremiumNotification(fixtureId, hid, aid, title, body, extraData = {}) {
  try {
    await admin.messaging().send({
      condition: premiumCondition(fixtureId, hid, aid),
      notification: { title, body },
      data: { fixtureId: String(fixtureId), type: extraData.type || "premium", ...extraData },
      android: {
        priority: "high",
        notification: { channelId: "hdf_partidos", sound: "default" },
      },
    });
    console.log(`FCM PREMIUM enviado: ${title} | fixture=${fixtureId}`);
  } catch (e) {
    console.error(`FCM PREMIUM falló fixture=${fixtureId}`, e);
  }
}

// ─── Helpers API ──────────────────────────────────────────────────────────────

async function fetchLiveForLeague(leagueId, season, apiKey, filterArgentinaOnly) {
  const url = `${API_BASE}/fixtures?league=${leagueId}&season=${season}&live=all`;
  const res = await fetch(url, { headers: { "x-apisports-key": apiKey } });
  if (!res.ok) {
    console.error(`API fixtures live league=${leagueId} HTTP ${res.status}`);
    return [];
  }
  const data = await res.json();
  const list = data.response || [];
  if (filterArgentinaOnly) {
    return list.filter((row) => {
      const hid = row.teams?.home?.id;
      const aid = row.teams?.away?.id;
      return ARG_TEAM_IDS.has(hid) || ARG_TEAM_IDS.has(aid);
    });
  }
  return list;
}

async function fetchAllLiveFixtures(apiKey) {
  const seen = new Map();
  const chunks = [
    ...seasonsForLeague(LEAGUE_LIGA_ARG).map((sea) =>
      fetchLiveForLeague(LEAGUE_LIGA_ARG, sea, apiKey, false)
    ),
    ...seasonsForLeague(LEAGUE_COPA_ARGENTINA).map((sea) =>
      fetchLiveForLeague(LEAGUE_COPA_ARGENTINA, sea, apiKey, false)
    ),
    fetchLiveForLeague(LEAGUE_LIBERTADORES, SEASON, apiKey, true),
    fetchLiveForLeague(LEAGUE_SUDAMERICANA, SEASON, apiKey, true),
    ...seasonsForLeague(LEAGUE_LA_LIGA_ES).map((sea) =>
      fetchLiveForLeague(LEAGUE_LA_LIGA_ES, sea, apiKey, false)
    ),
  ];
  const results = await Promise.all(chunks);
  for (const arr of results) {
    for (const row of arr) {
      const id = row.fixture?.id;
      if (id != null) seen.set(id, row);
    }
  }
  return [...seen.values()];
}

async function fetchFixtureEvents(fixtureId, apiKey) {
  const url = `${API_BASE}/fixtures/events?fixture=${fixtureId}`;
  const res = await fetch(url, { headers: { "x-apisports-key": apiKey } });
  if (!res.ok) return [];
  const data = await res.json();
  return data.response || [];
}

async function fetchFixtureStatistics(fixtureId, apiKey) {
  const url = `${API_BASE}/fixtures/statistics?fixture=${fixtureId}`;
  const res = await fetch(url, { headers: { "x-apisports-key": apiKey } });
  if (!res.ok) return [];
  const data = await res.json();
  return data.response || [];
}

async function fetchFixtureLineups(fixtureId, apiKey) {
  const url = `${API_BASE}/fixtures/lineups?fixture=${fixtureId}`;
  const res = await fetch(url, { headers: { "x-apisports-key": apiKey } });
  if (!res.ok) return [];
  const data = await res.json();
  return data.response || [];
}

/** Un fixture puntual (para cuando ya no está en live=all pero pasó a FT). */
async function fetchFixtureById(fixtureId, apiKey) {
  const url = `${API_BASE}/fixtures?id=${fixtureId}`;
  const res = await fetch(url, { headers: { "x-apisports-key": apiKey } });
  if (!res.ok) return null;
  const data = await res.json();
  const list = data.response || [];
  return list[0] ?? null;
}

/**
 * Partidos que seguíamos en vivo y desaparecieron del endpoint live=all (típico al pasar a FT).
 * Sin esto nunca se envía "Fin del partido" ni el último gol si el cron cae entre el gol y el cierre.
 */
async function reconcileFinishedNotInLive(col, liveIds, apiKey) {
  const cutoff = Date.now() - 4 * 60 * 60 * 1000;
  let snapshot;
  try {
    snapshot = await col.orderBy("updatedAt", "desc").limit(45).get();
  } catch (e) {
    console.error("reconcileFinishedNotInLive orderBy", e);
    return;
  }

  for (const doc of snapshot.docs) {
    const prev = doc.data();
    const fid = parseInt(doc.id, 10);
    if (!Number.isFinite(fid)) continue;
    const ts = prev.updatedAt?.toMillis?.() ?? 0;
    if (ts < cutoff) break;
    if (prev.status === "FT") continue;
    if (liveIds.has(fid)) continue;

    const row = await fetchFixtureById(fid, apiKey);
    if (!row) continue;

    const status = row.fixture?.status?.short;
    const gh = Number(row.goals?.home ?? 0);
    const ga = Number(row.goals?.away ?? 0);
    const hid = row.teams?.home?.id;
    const aid = row.teams?.away?.id;
    const homeName = row.teams?.home?.name ?? "Local";
    const awayName = row.teams?.away?.name ?? "Visitante";
    if (hid == null || aid == null) continue;

    const ref = col.doc(String(fid));
    const prevStatus = prev.status;
    const ph = Number(prev.home ?? 0);
    const pa = Number(prev.away ?? 0);
    const resumeSent = prev.resumeSent ?? false;

    if (status === "FT" && prevStatus !== "FT") {
      if (gh !== ph || ga !== pa) {
        const dh = gh - ph;
        const da = ga - pa;
        let title = "⚽ Gol";
        if (dh > 0 && da > 0) title = "⚽ Goles · Actualización";
        else if (dh > 0) title = `⚽ Gol · ${homeName}`;
        else if (da > 0) title = `⚽ Gol · ${awayName}`;
        await sendFreeNotification(fid, hid, aid, title, `${homeName} ${gh} - ${ga} ${awayName}`, { type: "goal" });
      }
      await sendFreeNotification(fid, hid, aid,
        "🏁 ¡Fin del partido!",
        `${homeName} ${gh} - ${ga} ${awayName}`,
        { type: "fulltime" }
      );
      console.log(`pollLiveGoals: FT detectado vía fixtures?id= fixture=${fid}`);
    }

    if (status === "FT" && !resumeSent) {
      try {
        const stats = await fetchFixtureStatistics(fid, apiKey.trim());
        const homeStats = stats.find((s) => s.team?.id === hid)?.statistics || [];
        const awayStats = stats.find((s) => s.team?.id === aid)?.statistics || [];
        const getStat = (statArr, name) =>
          statArr.find((s) => s.type === name)?.value ?? "-";
        const homePoss = getStat(homeStats, "Ball Possession");
        const awayPoss = getStat(awayStats, "Ball Possession");
        const homeShotsOn = getStat(homeStats, "Shots on Goal");
        const awayShotsOn = getStat(awayStats, "Shots on Goal");
        const body =
          `${homeName} ${gh} - ${ga} ${awayName}\n` +
          `Posesión: ${homePoss} - ${awayPoss} | ` +
          `Tiros al arco: ${homeShotsOn} - ${awayShotsOn}`;
        await sendPremiumNotification(fid, hid, aid, "📊 Resumen del partido", body, { type: "summary" });
        await ref.set({ resumeSent: true }, { merge: true });
      } catch (e) {
        console.error(`Resumen FT (reconcile) falló fixture=${fid}`, e);
      }
    }

    await ref.set(
      {
        home: gh,
        away: ga,
        status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
}

// ─── FUNCIÓN PRINCIPAL: cada 2 minutos ───────────────────────────────────────
// Detecta: Goles (FREE), Inicio/Final (FREE), Tarjeta Roja (PREMIUM), Resumen FT (PREMIUM)

exports.pollLiveGoals = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    secrets: [apisportsKey],
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const apiKey = apisportsKey.value();
    if (!apiKey || !String(apiKey).trim()) {
      console.error("APISPORTS_KEY vacío");
      return;
    }

    let fixtures;
    try {
      fixtures = await fetchAllLiveFixtures(apiKey.trim());
    } catch (e) {
      console.error("fetchAllLiveFixtures", e);
      return;
    }

    const db = admin.firestore();
    const col = db.collection(STATE_COLLECTION);
    const liveIds = new Set();

    if (fixtures.length === 0) {
      console.log("pollLiveGoals: sin partidos en live=all; revisando cierres recientes en Firestore");
    }

    for (const row of fixtures) {
      const fid = row.fixture?.id;
      if (fid == null) continue;
      liveIds.add(fid);

      const gh = Number(row.goals?.home ?? 0);
      const ga = Number(row.goals?.away ?? 0);
      const hid = row.teams?.home?.id;
      const aid = row.teams?.away?.id;
      const status = row.fixture?.status?.short; // NS, 1H, HT, 2H, ET, P, FT
      const homeName = row.teams?.home?.name ?? "Local";
      const awayName = row.teams?.away?.name ?? "Visitante";

      if (hid == null || aid == null) continue;

      const ref = col.doc(String(fid));
      const snap = await ref.get();
      const prev = snap.exists ? snap.data() : null;

      // ── Primer registro del partido ──────────────────────────────────────
      if (!prev) {
        await ref.set({
          home: gh,
          away: ga,
          status,
          redCardsHome: 0,
          redCardsAway: 0,
          resumeSent: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Arranque 0-0: aviso de inicio. Si ya hay goles, el tracker llegó tarde: aviso de marcador
        // (si no, ese primer gol nunca generaba push porque antes hacíamos `continue` sin comparar).
        if (gh === 0 && ga === 0 && status === "1H") {
          await sendFreeNotification(fid, hid, aid,
            "🟢 ¡Arranca el partido!",
            `${homeName} vs ${awayName}`,
            { type: "kickoff" }
          );
        } else if (gh > 0 || ga > 0) {
          const dh = gh;
          const da = ga;
          let title = "⚽ Gol";
          if (dh > 0 && da > 0) title = "⚽ Goles · Marcador";
          else if (dh > 0) title = `⚽ Gol · ${homeName}`;
          else if (da > 0) title = `⚽ Gol · ${awayName}`;
          await sendFreeNotification(fid, hid, aid, title,
            `${homeName} ${gh} - ${ga} ${awayName}`,
            { type: "goal" }
          );
          console.log(`pollLiveGoals: primer visto fixture=${fid} con marcador ${gh}-${ga} (push recuperado)`);
        }
        continue;
      }

      const prevStatus = prev.status;
      const ph = Number(prev.home ?? 0);
      const pa = Number(prev.away ?? 0);
      const prevRedHome = Number(prev.redCardsHome ?? 0);
      const prevRedAway = Number(prev.redCardsAway ?? 0);
      const resumeSent = prev.resumeSent ?? false;

      // ── INICIO DE PARTIDO (FREE) ─────────────────────────────────────────
      if (prevStatus === "NS" && status === "1H") {
        await sendFreeNotification(fid, hid, aid,
          "🟢 ¡Arranca el partido!",
          `${homeName} vs ${awayName}`,
          { type: "kickoff" }
        );
      }

      // ── INICIO 2DO TIEMPO (FREE) ─────────────────────────────────────────
      if (prevStatus === "HT" && status === "2H") {
        await sendFreeNotification(fid, hid, aid,
          "▶️ ¡Arranca el segundo tiempo!",
          `${homeName} ${gh} - ${ga} ${awayName}`,
          { type: "second_half" }
        );
      }

      // ── GOLES (FREE) ─────────────────────────────────────────────────────
      if (gh !== ph || ga !== pa) {
        const dh = gh - ph;
        const da = ga - pa;
        let title = "⚽ Gol";
        if (dh > 0 && da > 0) title = "⚽ Goles · Actualización";
        else if (dh > 0) title = `⚽ Gol · ${homeName}`;
        else if (da > 0) title = `⚽ Gol · ${awayName}`;
        const body = `${homeName} ${gh} - ${ga} ${awayName}`;
        await sendFreeNotification(fid, hid, aid, title, body, { type: "goal" });
      }

      // ── RESULTADO FINAL (FREE) ───────────────────────────────────────────
      if (prevStatus !== "FT" && status === "FT") {
        await sendFreeNotification(fid, hid, aid,
          "🏁 ¡Fin del partido!",
          `${homeName} ${gh} - ${ga} ${awayName}`,
          { type: "fulltime" }
        );
      }

      // ── TARJETAS ROJAS (PREMIUM) ─────────────────────────────────────────
      if (status === "1H" || status === "2H" || status === "ET") {
        try {
          const events = await fetchFixtureEvents(fid, apiKey.trim());
          const redCards = events.filter(
            (e) => e.type === "Card" && (e.detail === "Red Card" || e.detail === "Second Yellow Card")
          );
          const redHome = redCards.filter((e) => e.team?.id === hid).length;
          const redAway = redCards.filter((e) => e.team?.id === aid).length;

          if (redHome > prevRedHome || redAway > prevRedAway) {
            // La más reciente
            const newRed = redCards[redCards.length - 1];
            const playerName = newRed?.player?.name ?? "Jugador";
            const teamName = newRed?.team?.name ?? "";
            const minute = newRed?.time?.elapsed ?? "";
            const cardType = newRed?.detail === "Second Yellow Card" ? "🟨🟥" : "🟥";

            await sendPremiumNotification(fid, hid, aid,
              `${cardType} Tarjeta Roja — ${teamName}`,
              `${playerName} (${minute}') | ${homeName} ${gh} - ${ga} ${awayName}`,
              { type: "red_card" }
            );
            await ref.set(
              { redCardsHome: redHome, redCardsAway: redAway },
              { merge: true }
            );
          }
        } catch (e) {
          console.error(`fetchFixtureEvents falló fixture=${fid}`, e);
        }
      }

      // ── RESUMEN POST-PARTIDO (PREMIUM) ───────────────────────────────────
      if (status === "FT" && !resumeSent) {
        try {
          const stats = await fetchFixtureStatistics(fid, apiKey.trim());
          const homeStats = stats.find((s) => s.team?.id === hid)?.statistics || [];
          const awayStats = stats.find((s) => s.team?.id === aid)?.statistics || [];

          const getStat = (statArr, name) =>
            statArr.find((s) => s.type === name)?.value ?? "-";

          const homePoss = getStat(homeStats, "Ball Possession");
          const awayPoss = getStat(awayStats, "Ball Possession");
          const homeShotsOn = getStat(homeStats, "Shots on Goal");
          const awayShotsOn = getStat(awayStats, "Shots on Goal");

          const body =
            `${homeName} ${gh} - ${ga} ${awayName}\n` +
            `Posesión: ${homePoss} - ${awayPoss} | ` +
            `Tiros al arco: ${homeShotsOn} - ${awayShotsOn}`;

          await sendPremiumNotification(fid, hid, aid,
            "📊 Resumen del partido",
            body,
            { type: "summary" }
          );
          await ref.set({ resumeSent: true }, { merge: true });
        } catch (e) {
          console.error(`Resumen FT falló fixture=${fid}`, e);
        }
      }

      // ── Actualizar estado en Firestore ────────────────────────────────────
      await ref.set(
        {
          home: gh,
          away: ga,
          status,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    await reconcileFinishedNotInLive(col, liveIds, apiKey.trim());
  }
);

// ─── FUNCIÓN PRE-PARTIDO: cada 5 minutos ─────────────────────────────────────
// Detecta partidos que arrancan en ~15 minutos
// Envía: hora + árbitro + estadio (FREE), formaciones confirmadas (PREMIUM)

exports.pollPreMatch = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    secrets: [apisportsKey],
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const apiKey = apisportsKey.value();
    if (!apiKey || !String(apiKey).trim()) return;

    const db = admin.firestore();
    const notifiedCol = db.collection(PRE_MATCH_COLLECTION);

    const now = Date.now();
    const windowFrom = now + 13 * 60 * 1000; // 13 min desde ahora
    const windowTo = now + 20 * 60 * 1000;   // 20 min desde ahora

    const today = new Date().toISOString().split("T")[0];
    const leagueIds = [
      LEAGUE_LIGA_ARG,
      LEAGUE_COPA_ARGENTINA,
      LEAGUE_LIBERTADORES,
      LEAGUE_SUDAMERICANA,
      LEAGUE_LA_LIGA_ES,
    ];

    for (const leagueId of leagueIds) {
      for (const season of seasonsForLeague(leagueId)) {
      const url = `${API_BASE}/fixtures?league=${leagueId}&season=${season}&date=${today}`;
      try {
        const res = await fetch(url, { headers: { "x-apisports-key": apiKey.trim() } });
        if (!res.ok) continue;
        const data = await res.json();
        const fixtures = data.response || [];

        for (const row of fixtures) {
          const fid = row.fixture?.id;
          const status = row.fixture?.status?.short;
          if (status !== "NS") continue; // Solo no iniciados

          const kickoffMs = new Date(row.fixture?.date).getTime();
          if (kickoffMs < windowFrom || kickoffMs > windowTo) continue;

          // ¿Ya enviamos notificación pre-partido para este fixture?
          const notifRef = notifiedCol.doc(String(fid));
          const notifSnap = await notifRef.get();
          if (notifSnap.exists) continue;

          const homeName = row.teams?.home?.name ?? "Local";
          const awayName = row.teams?.away?.name ?? "Visitante";
          const hid = row.teams?.home?.id;
          const aid = row.teams?.away?.id;
          const referee = row.fixture?.referee
            ? row.fixture.referee.replace(/, \w+$/, "") // quita país del nombre
            : "Por confirmar";
          const venue = row.fixture?.venue?.name ?? "";
          const kickoffLocal = new Date(kickoffMs).toLocaleTimeString("es-AR", {
            hour: "2-digit",
            minute: "2-digit",
            timeZone: "America/Argentina/Buenos_Aires",
          });

          // ── Notificación pre-partido FREE ────────────────────────────────
          await sendFreeNotification(fid, hid, aid,
            `⏰ En 15 min — ${homeName} vs ${awayName}`,
            `${kickoffLocal}hs · ${venue} · Árbitro: ${referee}`,
            { type: "pre_match" }
          );

          // ── Formaciones (PREMIUM) ────────────────────────────────────────
          try {
            const lineups = await fetchFixtureLineups(fid, apiKey.trim());
            if (lineups.length >= 2) {
              const homeLineup = lineups.find((l) => l.team?.id === hid);
              const awayLineup = lineups.find((l) => l.team?.id === aid);
              const hForm = homeLineup?.formation ?? "?";
              const aForm = awayLineup?.formation ?? "?";

              // Titulares (primeros 11)
              const homePlayers = (homeLineup?.startXI || [])
                .slice(0, 3)
                .map((p) => p.player?.name?.split(" ").pop())
                .join(", ");
              const awayPlayers = (awayLineup?.startXI || [])
                .slice(0, 3)
                .map((p) => p.player?.name?.split(" ").pop())
                .join(", ");

              await sendPremiumNotification(fid, hid, aid,
                `📋 Formaciones — ${homeName} (${hForm}) vs ${awayName} (${aForm})`,
                `${homeName}: ${homePlayers}... | ${awayName}: ${awayPlayers}...`,
                { type: "lineups" }
              );
            }
          } catch (e) {
            console.error(`fetchLineups falló fixture=${fid}`, e);
          }

          // Marcar como notificado para no volver a enviar
          await notifRef.set({
            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            homeName,
            awayName,
          });
        }
      } catch (e) {
        console.error(`pollPreMatch league=${leagueId} season=${season}`, e);
      }
      }
    }
  }
);
