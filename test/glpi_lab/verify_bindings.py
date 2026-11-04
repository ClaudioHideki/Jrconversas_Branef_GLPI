"""Assert actual Docker host publication for the disposable JRC services."""
import json
import subprocess
import sys


def validate_bindings(service, port, ports):
    expected = {f'{port}/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(port)}]}
    if ports != expected:
        raise ValueError(f'{service}: expected only {expected!r}, actual {ports!r}')
    return ports


if __name__ == '__main__':
    postgres_id, redis_id = sys.argv[1:]
    for service, port, container_id in [('postgres', 5432, postgres_id), ('redis', 6379, redis_id)]:
        actual = subprocess.check_output(
            ['docker', 'inspect', '--format', '{{json .NetworkSettings.Ports}}', container_id], text=True)
        ports = validate_bindings(service, port, json.loads(actual))
        print(f'Verified actual {service} host bindings: {json.dumps(ports, sort_keys=True)}')
