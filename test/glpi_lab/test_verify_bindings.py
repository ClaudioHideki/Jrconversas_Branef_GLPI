import unittest

from verify_bindings import validate_bindings


class HostBindingsTest(unittest.TestCase):
    def test_accepts_only_expected_loopback_publication(self):
        ports = {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '5432'}]}
        self.assertEqual(ports, validate_bindings('postgres', 5432, ports))

    def test_rejects_missing_or_any_other_publication(self):
        invalid = [
            {},
            {'5432/tcp': None},
            {'5432/tcp': [{'HostIp': '', 'HostPort': '5432'}]},
            {'5432/tcp': [{'HostIp': '0.0.0.0', 'HostPort': '5432'}]},
            {'5432/tcp': [{'HostIp': '::', 'HostPort': '5432'}]},
            {'5432/tcp': [{'HostIp': '192.0.2.1', 'HostPort': '5432'}]},
            {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '9999'}]},
            {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '5432'},
                          {'HostIp': '::', 'HostPort': '5432'}]},
            {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '5432'}],
             '9999/tcp': [{'HostIp': '0.0.0.0', 'HostPort': '9999'}]},
        ]
        for ports in invalid:
            with self.subTest(ports=ports), self.assertRaises(ValueError):
                validate_bindings('postgres', 5432, ports)

    def test_checks_redis_with_its_own_port(self):
        ports = {'6379/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '6379'}]}
        self.assertEqual(ports, validate_bindings('redis', 6379, ports))


if __name__ == '__main__':
    unittest.main()
