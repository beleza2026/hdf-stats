import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleRequest

creds = service_account.Credentials.from_service_account_file(
    'service_account.json',
    scopes=['https://www.googleapis.com/auth/datastore']
)
creds.refresh(GoogleRequest())

url = 'https://firestore.googleapis.com/v1/projects/hdf-stats/databases/(default)/documents/resultados_morales'
r = requests.get(url, headers={'Authorization': f'Bearer {creds.token}'}, params={'pageSize': 300})
docs = r.json().get('documents', [])

equipos = set()
for d in docs:
    f = d.get('fields', {})
    equipos.add((f.get('homeId',{}).get('stringValue','?'), f.get('homeNombre',{}).get('stringValue','?')))
    equipos.add((f.get('awayId',{}).get('stringValue','?'), f.get('awayNombre',{}).get('stringValue','?')))

print(f"Total equipos: {len(equipos)}")
print()
for id_, nombre in sorted(equipos, key=lambda x: x[1]):
    print(f"  {id_:>6}  {nombre}")
