"""
fix_ids_firestore.py — Corrige los IDs viejos de equipos en Firestore
Reemplaza homeId/awayId con los IDs reales de la temporada 2026

Uso: python fix_ids_firestore.py
"""
import json, requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleRequest

PROJECT_ID = 'hdf-stats'
SA_PATH    = 'service_account.json'

# Mapa: ID viejo -> ID nuevo (solo los que cambiaron)
ID_MAP = {
    '433': '451',  # Boca Juniors
    '437': '460',  # San Lorenzo
    '436': '453',  # Independiente -> ahora Racing usa 436
    '440': '436',  # Racing Club (viejo 440 era Racing, ahora es Belgrano)
    '438': '445',  # Huracán
    '442': '438',  # Vélez
    '443': '440',  # Belgrano
    '444': '450',  # Estudiantes L.P.
    '450': '446',  # Lanús (viejo 450 era Lanús, ahora es Estudiantes)
    '447': '457',  # Newell's
    '432': '456',  # Talleres
    '445': '434',  # Gimnasia L.P. (viejo 445 era Gimnasia)
    '451': '449',  # Banfield (viejo 451 era Banfield, ahora es Boca)
    '452': '452',  # Tigre — sin cambio
    '453': '458',  # Argentinos JRS (viejo 453)
    '454': '474',  # Sarmiento
    '455': '455',  # Atl. Tucumán — sin cambio
    '456': '441',  # Unión
    '458': '473',  # Ind. Rivadavia
    '460': '478',  # Instituto
    '461': '476',  # Riestra
    '462': '463',  # Aldosivi
    '464': '2432', # Barracas
    '465': '458',  # Argentinos (otro ID viejo)
}

# IDs que ya son correctos (no modificar)
CORRECT_IDS = {'435', '451', '460', '453', '436', '445', '438', '440', '450',
               '434', '457', '446', '449', '458', '474', '441', '456', '455',
               '478', '476', '463', '2432', '473', '2424', '1064', '1065', '1066', '452'}

def get_token():
    creds = service_account.Credentials.from_service_account_file(
        SA_PATH, scopes=['https://www.googleapis.com/auth/datastore'])
    creds.refresh(GoogleRequest())
    return creds.token

def main():
    print('🔑 Autenticando...')
    token = get_token()
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json',
    }

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

    print(f'Total documentos: {len(docs)}')

    to_fix = []
    for doc in docs:
        fields = doc.get('fields', {})
        home_id = fields.get('homeId', {}).get('stringValue', '')
        away_id = fields.get('awayId', {}).get('stringValue', '')
        
        new_home = ID_MAP.get(home_id, home_id)
        new_away = ID_MAP.get(away_id, away_id)
        
        if new_home != home_id or new_away != away_id:
            to_fix.append((doc['name'], fields, new_home, new_away, home_id, away_id))

    print(f'Documentos a corregir: {len(to_fix)}')
    if not to_fix:
        print('✅ Todos los IDs ya son correctos.')
        return

    # Preview
    print('\nPrimeros 5 a corregir:')
    for name, fields, nh, na, oh, oa in to_fix[:5]:
        hnom = fields.get('homeNombre', {}).get('stringValue', '?')
        anom = fields.get('awayNombre', {}).get('stringValue', '?')
        print(f'  {hnom} ({oh}→{nh}) vs {anom} ({oa}→{na})')

    print(f'\n🔧 Corrigiendo {len(to_fix)} documentos...')
    ok = err = 0
    for i, (name, fields, new_home, new_away, old_home, old_away) in enumerate(to_fix):
        # Solo actualizar los campos de ID
        patch_fields = {
            'fields': {
                **fields,
                'homeId': {'stringValue': new_home},
                'awayId': {'stringValue': new_away},
            }
        }
        mask = 'updateMask.fieldPaths=homeId&updateMask.fieldPaths=awayId'
        full_url = 'https://firestore.googleapis.com/v1/' + name
        resp = requests.patch(f'{full_url}?{mask}', headers=headers, data=json.dumps(patch_fields))
        if resp.status_code in (200, 201):
            ok += 1
            if i < 3 or i % 50 == 0:
                hnom = fields.get('homeNombre', {}).get('stringValue', '?')
                anom = fields.get('awayNombre', {}).get('stringValue', '?')
                print(f'  [{i+1}/{len(to_fix)}] ✅ {hnom} {old_home}→{new_home} | {anom} {old_away}→{new_away}')
        else:
            err += 1
            print(f'  [{i+1}] ❌ Error {resp.status_code}')

    print(f'\n✅ Corregidos: {ok} | ❌ Errores: {err}')

if __name__ == '__main__':
    main()

