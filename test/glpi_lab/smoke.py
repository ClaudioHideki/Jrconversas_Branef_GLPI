"""Read-only smoke against the synthetic lab. Never prints credentials or response bodies."""
from pathlib import Path
import json
import ssl
import urllib.request
import urllib.error

root = Path(__file__).resolve().parent
fixtures = json.loads((root/'.runtime/out/fixtures.json').read_text())
assert fixtures['version'] == '10.0.18'
base = 'https://glpi.example.invalid:14443/apirest.php/'
context = ssl.create_default_context(cafile=str(root/'.runtime/tls/ca.crt'))
session = None
def get(path, user_token=None):
    headers = {'App-Token': fixtures['app_token'], 'Content-Type': 'application/json'}
    if user_token:
        headers['Authorization'] = 'user_token ' + user_token
    else:
        headers['Session-Token'] = session
    request = urllib.request.Request(base+path, headers=headers)
    try:
        with urllib.request.urlopen(request, context=context, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, None

checks = []
try:
    status, data = get('initSession/', fixtures['user_token'])
    assert status == 200, 'Synthetic authentication failed'
    session = data['session_token']
    checks.append('technical authentication')
    status, data = get('getGlpiConfig/')
    assert status == 200 and data['cfg_glpi']['version'] == '10.0.18', 'Wrong GLPI runtime'
    checks.append('GLPI 10.0.18 runtime')
    status, data = get('getMyEntities/?is_recursive=true')
    assert status == 200 and {0, *fixtures['entities'].values()}.issubset({int(row['id']) for row in data['myentities']})
    checks.append('root and synthetic entities')
    status, data = get(f'Ticket/{fixtures["tickets"]["root"]}')
    assert status == 200 and data['entities_id'] == 0
    checks.append('root ticket readable')
    get('killSession/')
    session = None
    status, data = get('initSession/', fixtures['limited_token'])
    assert status == 200
    session = data['session_token']
    status, _ = get(f'Ticket/{fixtures["tickets"]["root"]}')
    assert status == 403, 'Limited profile must not read technical tickets'
    checks.append('limited profile denied')
finally:
    if session:
        get('killSession/')
(root/'.runtime/smoke-results.json').write_text(json.dumps({'version': '10.0.18', 'checks': checks, 'customer_requests': 0}, indent=2))
print(json.dumps({'version': '10.0.18', 'checks': len(checks), 'customer_requests': 0}))
