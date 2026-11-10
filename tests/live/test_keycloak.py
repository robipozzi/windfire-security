"""
Keycloak behind the environment: reachable over TLS, the issuer the server expects, a usable JWKS.

These tests run first. If they fail, the 401s in the other live tests come from Keycloak, not from
the auth server.
"""
import os

import pytest
import requests

from suite_helpers import CERT_MIN_DAYS_LEFT, cert_days_left, url_host_port


@pytest.fixture(scope="module")
def keycloak(env_cfg):
    url = env_cfg.get("keycloak_url")
    if not url:
        pytest.fail(f"no Keycloak URL for '{env_cfg['name']}': set keycloak_url in tests/environments.json "
                    "or KEYCLOAK_SERVER_URL in server/.env")
    if not os.path.isfile(env_cfg["keycloak_ca"]):
        pytest.fail(f"Windfire Keycloak Root CA not found: {env_cfg['keycloak_ca']}")
    return {"url": url, "realm_url": f"{url}/realms/{env_cfg['realm']}", "ca": env_cfg["keycloak_ca"]}


@pytest.fixture(scope="module")
def discovery(keycloak):
    url = f"{keycloak['realm_url']}/.well-known/openid-configuration"
    try:
        response = requests.get(url, verify=keycloak["ca"], timeout=10)
    except requests.exceptions.SSLError as e:
        pytest.fail(f"TLS error from Keycloak at {url} (is keycloak_ca the Windfire Keycloak Root CA?): {e}")
    except requests.exceptions.ConnectionError as e:
        pytest.fail(f"Keycloak not reachable at {url}. For a local Keycloak, start it with "
                    f"keycloak/start-keycloak.sh. ({e})")
    assert response.status_code == 200, f"{url} -> {response.status_code}"
    return response.json()


def test_discovery_document(discovery):
    for key in ("issuer", "token_endpoint", "jwks_uri"):
        assert discovery.get(key), key


def test_issuer_matches_server_configuration(discovery, keycloak):
    # The server checks iss == {KEYCLOAK_SERVER_URL}/realms/{realm}: a hostname mismatch makes every /verify fail
    assert discovery["issuer"] == keycloak["realm_url"]


def test_jwks_has_rs256_signing_key(discovery, keycloak):
    response = requests.get(discovery["jwks_uri"], verify=keycloak["ca"], timeout=10)
    assert response.status_code == 200
    keys = response.json().get("keys", [])
    assert any(k.get("kty") == "RSA" and k.get("alg") == "RS256" and k.get("use", "sig") == "sig" for k in keys), keys


def test_keycloak_certificate_not_expiring(keycloak):
    host, port = url_host_port(keycloak["url"])
    days = cert_days_left(host, port, keycloak["ca"])
    assert days > CERT_MIN_DAYS_LEFT, f"Keycloak certificate on {host}:{port} expires in {days:.0f} days"
