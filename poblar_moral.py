"""
poblar_moral.py — Pobla la Tabla Moral en Firestore usando Service Account
Uso:
    python poblar_moral.py           # todas las fechas (~20 min)
    python poblar_moral.py --ultima  # solo la última fecha (~2 min)

Requiere:
    pip install requests google-auth
"""

import json, sys, time, requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleRequest

# ── Configuración ─────────────────────────────────────────────────────────────
API_KEY       = 'e41f25b121cc73bca63f00b362424fff'
API_BASE      = 'https://v3.football.api-sports.io'
LIGA          = 128
SEASON        = 2026
PROJECT_ID    = 'hdf-stats'
SA_PATH       = 'service_account.json'
FIRESTORE_URL = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/resultados_morales'
API_HEADERS   = {'x-apisports-key': API_KEY}
# ──────────────────────────────────────────────────────────────────────────────

def get_token():
    creds = service_account.Credentials.from_service_account_file(
        SA_PATH,
        scopes=['https://www.googleapis.com/auth/datastore']
    )
    creds.refresh(GoogleRequest())
    return creds.token

def main():
    solo_ultima = '--ultima' in sys.argv

    print()
    print('╔══════════════════════════════════════════════╗')
    if solo_ultima:
        print('║   POBLAR TABLA MORAL — ÚLTIMA FECHA         ║')
    else:
        print('║   POBLAR TABLA MORAL — COMPLETO (~20 min)   ║')
    print('╚══════════════════════════════════════════════╝')
    print()

    # Token OAuth2
    print('🔑 Autenticando con Service Account...')
    try:
        token = get_token()
        print('✅ Token OK\n')
    except Exception as e:
        print(f'❌ Error de autenticación: {e}')
        print('   Verificá que service_account.json esté en la raíz del proyecto.')
        sys.exit(1)

    auth_headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json',
    }

    # Fixtures
    print('📡 Trayendo fixtures...')
    resp = requests.get(f'{API_BASE}/fixtures?league={LIGA}&season={SEASON}', headers=API_HEADERS)
    if resp.status_code != 200:
        print(f'❌ Error fixtures: {resp.status_code}')
        sys.exit(1)

    all_fixtures = resp.json()['response']
    todos_jugados = [f for f in all_fixtures
                     if f['fixture']['status']['short'] in ('FT', 'AET', 'PEN')]

    if solo_ultima:
        max_round = 0
        for f in todos_jugados:
            rnd = f['league'].get('round', '')
            if 'Regular Season' in rnd:
                parts = rnd.split('- ')
                if len(parts) == 2:
                    n = int(parts[1].strip()) if parts[1].strip().isdigit() else 0
                    if n > max_round:
                        max_round = n
        round_str = f'Regular Season - {max_round}'
        jugados = [f for f in todos_jugados if f['league']['round'] == round_str]
        print(f'Última fecha: Fecha {max_round} — {len(jugados)} partidos\n')
    else:
        jugados = todos_jugados

    print(f'{len(jugados)} partidos a procesar')
    print('Procesando con algoritmo moral completo...\n')

    ok = errores = sin_stats = 0
    token_refresh_at = time.time() + 3000  # refrescar token cada 50 min

    for i, f in enumerate(jugados):
        # Refrescar token si está por vencer
        if time.time() > token_refresh_at:
            token = get_token()
            auth_headers['Authorization'] = f'Bearer {token}'
            token_refresh_at = time.time() + 3000

        fId       = f['fixture']['id']
        home_id   = str(f['teams']['home']['id'])
        away_id   = str(f['teams']['away']['id'])
        home_name = f['teams']['home']['name']
        away_name = f['teams']['away']['name']
        gl_local  = f['goals']['home'] or 0
        gl_visit  = f['goals']['away'] or 0

        moral_l = gl_local
        moral_v = gl_visit

        # Stats del partido
        stats_resp = requests.get(
            f'{API_BASE}/fixtures/statistics?fixture={fId}',
            headers=API_HEADERS
        )

        if stats_resp.status_code == 200:
            stats_list = stats_resp.json().get('response', [])
            if len(stats_list) >= 2:
                pos_l = pos_v = 50.0
                tiros_l = tiros_v = corners_l = corners_v = 0

                for s in stats_list[0].get('statistics', []):
                    v = str(s.get('value') or '0').replace('%', '')
                    if s['type'] == 'Ball Possession':
                        pos_l = float(v) if v.replace('.','').isdigit() else 50.0
                    elif s['type'] == 'Shots on Goal':
                        tiros_l = int(v) if v.isdigit() else 0
                    elif s['type'] == 'Corner Kicks':
                        corners_l = int(v) if v.isdigit() else 0

                for s in stats_list[1].get('statistics', []):
                    v = str(s.get('value') or '0').replace('%', '')
                    if s['type'] == 'Ball Possession':
                        pos_v = float(v) if v.replace('.','').isdigit() else 50.0
                    elif s['type'] == 'Shots on Goal':
                        tiros_v = int(v) if v.isdigit() else 0
                    elif s['type'] == 'Corner Kicks':
                        corners_v = int(v) if v.isdigit() else 0

                # Algoritmo moral
                dif_pos    = pos_l - pos_v
                dif_tiros  = tiros_l - tiros_v
                dif_corners= corners_l - corners_v
                dominio = 0.0
                if abs(dif_pos) > 25:    dominio += 1.5 if dif_pos > 0 else -1.5
                elif abs(dif_pos) > 15:  dominio += 1.0 if dif_pos > 0 else -1.0
                if abs(dif_tiros) >= 3:  dominio += 1.0 if dif_tiros > 0 else -1.0
                elif abs(dif_tiros) >= 1:dominio += 0.5 if dif_tiros > 0 else -0.5
                if abs(dif_corners) >= 5:dominio += 0.5 if dif_corners > 0 else -0.5

                ajuste = max(-1, min(1, round(dominio)))
                moral_l = max(0, gl_local + ajuste)
                moral_v = max(0, gl_visit - ajuste)

                dif_goles = abs(gl_local - gl_visit)
                if dif_goles == 1:
                    if gl_local > gl_visit and moral_l < moral_v: moral_l = moral_v
                    if gl_visit > gl_local and moral_v < moral_l: moral_v = moral_l
                if gl_local == gl_visit:
                    if moral_l > moral_v + 1: moral_l = moral_v + 1
                    if moral_v > moral_l + 1: moral_v = moral_l + 1

        elif stats_resp.status_code == 429:
            print(f'  ⏳ Rate limit en {fId} — esperando 5s...')
            time.sleep(5)
            sin_stats += 1
        else:
            sin_stats += 1

        # Guardar en Firestore
        doc_url = f'{FIRESTORE_URL}/{fId}'
        fields = {
            'fields': {
                'fixtureId':      {'integerValue': str(fId)},
                'homeId':         {'stringValue': home_id},
                'awayId':         {'stringValue': away_id},
                'homeNombre':     {'stringValue': home_name},
                'awayNombre':     {'stringValue': away_name},
                'moralLocal':     {'integerValue': str(moral_l)},
                'moralVisitante': {'integerValue': str(moral_v)},
            }
        }
        mask_params = '&'.join([
            'updateMask.fieldPaths=fixtureId',
            'updateMask.fieldPaths=homeId',
            'updateMask.fieldPaths=awayId',
            'updateMask.fieldPaths=homeNombre',
            'updateMask.fieldPaths=awayNombre',
            'updateMask.fieldPaths=moralLocal',
            'updateMask.fieldPaths=moralVisitante',
        ])
        fs_resp = requests.patch(
            f'{doc_url}?{mask_params}',
            headers=auth_headers,
            data=json.dumps(fields)
        )

        if fs_resp.status_code in (200, 201):
            ok += 1
            if i < 3 or i % 30 == 0:
                print(f'[{i+1}/{len(jugados)}] {home_name} {moral_l} - {moral_v} {away_name}')
        else:
            errores += 1
            print(f'[{i+1}] ❌ Firestore ERROR {fs_resp.status_code}: {fs_resp.text[:100]}')

        time.sleep(1.2)  # respetar rate limit API-Football

    print()
    print('╔══════════════════════════════════════════════╗')
    print(f'║  ✅ OK: {ok} partidos                          ')
    print(f'║  ⚠️  Sin stats (solo goles): {sin_stats}        ')
    print(f'║  ❌ Errores Firestore: {errores}               ')
    print('╚══════════════════════════════════════════════╝')
    if errores == 0:
        print('\n🎉 Tabla Moral actualizada con algoritmo completo.')

if __name__ == '__main__':
    main()
