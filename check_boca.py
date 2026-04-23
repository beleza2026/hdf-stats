"""
check_boca.py — Muestra los resultados morales de Boca en Firestore
Uso: python check_boca.py
"""
import json
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleRequest

PROJECT_ID = 'hdf-stats'
SA_PATH    = 'service_account.json'
BOCA_ID    = '451'
BOCA_NAME  = 'Boca Juniors'

def get_token():
    creds = service_account.Credentials.from_service_account_file(
        SA_PATH, scopes=['https://www.googleapis.com/auth/datastore'])
    creds.refresh(GoogleRequest())
    return creds.token

def main():
    print('🔑 Autenticando...')
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    print('📡 Leyendo Firestore...')
    url = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/resultados_morales'
    
    docs = []
    page_token = None
    while True:
        params = {'pageSize': 300}
        if page_token:
            params['pageToken'] = page_token
        resp = requests.get(url, headers=headers, params=params)
        data = resp.json()
        docs.extend(data.get('documents', []))
        page_token = data.get('nextPageToken')
        if not page_token:
            break

    print(f'Total documentos: {len(docs)}\n')

    g = e = p = 0
    partidos = []

    for doc in docs:
        fields = doc.get('fields', {})
        home_id = fields.get('homeId', {}).get('stringValue', '')
        away_id = fields.get('awayId', {}).get('stringValue', '')
        
        if home_id != BOCA_ID and away_id != BOCA_ID:
            continue

        home_name  = fields.get('homeNombre', {}).get('stringValue', '?')
        away_name  = fields.get('awayNombre', {}).get('stringValue', '?')
        moral_l    = int(fields.get('moralLocal', {}).get('integerValue', 0))
        moral_v    = int(fields.get('moralVisitante', {}).get('integerValue', 0))
        fixture_id = fields.get('fixtureId', {}).get('integerValue', '?')

        es_local = home_id == BOCA_ID
        if es_local:
            boca_moral = moral_l
            rival_moral = moral_v
            rival = away_name
            condicion = 'L'
        else:
            boca_moral = moral_v
            rival_moral = moral_l
            rival = home_name
            condicion = 'V'

        if boca_moral > rival_moral:
            res = 'G'; g += 1
        elif boca_moral == rival_moral:
            res = 'E'; e += 1
        else:
            res = 'P'; p += 1

        partidos.append((fixture_id, condicion, rival, boca_moral, rival_moral, res))

    partidos.sort(key=lambda x: str(x[0]))

    print(f'{'#':<4} {'L/V':<3} {'Rival':<30} {'Boca':<5} {'Rival':<5} Res')
    print('-' * 60)
    for i, (fid, cond, rival, bm, rm, res) in enumerate(partidos, 1):
        print(f'{i:<4} {cond:<3} {rival:<30} {bm:<5} {rm:<5} {res}')

    pts = g * 3 + e
    print(f'\n📊 RESUMEN MORAL BOCA:')
    print(f'   PJ: {len(partidos)} | G: {g} | E: {e} | P: {p} | PTS: {pts}')

if __name__ == '__main__':
    main()

