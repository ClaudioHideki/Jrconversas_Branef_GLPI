"""Prepare disposable credentials and a trusted local TLS CA; no client configuration is read."""
from pathlib import Path
import os
import secrets
import subprocess

root = Path(__file__).resolve().parent / '.runtime'
(root / 'out').mkdir(parents=True, exist_ok=True)
tls = root / 'tls'
tls.mkdir(exist_ok=True)
values = {'LAB_DB_PASSWORD': secrets.token_hex(24), 'LAB_ROOT_PASSWORD': secrets.token_hex(24), 'LAB_HOST_UID': str(os.getuid())}
env = root / 'compose.env'
env.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
env.chmod(0o600)
commands = [
    ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(tls/'ca.key'), '-out', str(tls/'ca.crt'),
     '-days', '2', '-subj', '/CN=Branef Synthetic GLPI Lab CA'],
    ['openssl', 'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(tls/'server.key'), '-out', str(tls/'server.csr'),
     '-subj', '/CN=glpi.example.invalid'],
]
for command in commands:
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
(tls/'extensions.cnf').write_text('subjectAltName=DNS:glpi.example.invalid\nextendedKeyUsage=serverAuth\n')
subprocess.run(['openssl', 'x509', '-req', '-in', str(tls/'server.csr'), '-CA', str(tls/'ca.crt'), '-CAkey', str(tls/'ca.key'),
                '-CAcreateserial', '-out', str(tls/'server.crt'), '-days', '2', '-extfile', str(tls/'extensions.cnf')],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('Synthetic credentials and local TLS CA prepared')
