"""Auth server TLS, certificate expiry, health endpoint and trusted hosts"""
from suite_helpers import CERT_MIN_DAYS_LEFT, cert_days_left


def test_tls_handshake_and_certificate_expiry(env_cfg):
    # The handshake verifies the chain against the Windfire Root CA and the hostname
    days = cert_days_left(env_cfg["host"], env_cfg["port"], env_cfg["root_ca"])
    assert days > CERT_MIN_DAYS_LEFT, f"server certificate expires in {days:.0f} days"


def test_health(http, base_url):
    response = http.get(f"{base_url}/v1/monitor/health", timeout=10)
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert body.get("service")


def test_unknown_host_header_is_rejected(http, base_url):
    response = http.get(f"{base_url}/v1/monitor/health", headers={"Host": "evil.com"}, timeout=10)
    assert response.status_code == 400
