"""
keycloakAuth: local JWT verification, JWKS cache and password login, with Keycloak mocked.

This is the regression net for PyJWT and cryptography bumps: tokens are signed with RSA keys
generated here and the JWKS is served through a mocked requests.Session.get.
"""
import base64
import hashlib
import hmac
import json
import os
import time
import types

import jwt
import pytest
import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

import keycloakAuth
from keycloakAuth import KeycloakAuth, KeycloakAuthError, KeycloakConfig, verify_token

from hermetic import CLIENT_ID, CLIENT_SECRET, KEYCLOAK_URL, REALM, SERVICE

KID = "suite-kid-1"
OTHER_KID = "suite-kid-2"
ISSUER = f"{KEYCLOAK_URL}/realms/{REALM}"
JWKS_URL = f"{ISSUER}/protocol/openid-connect/certs"
TOKEN_URL = f"{ISSUER}/protocol/openid-connect/token"


# ---------------------------------------------------------------------------
# Keys, JWKS and tokens
# ---------------------------------------------------------------------------
def new_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(scope="module")
def signing_key():
    return new_key()


@pytest.fixture(scope="module")
def other_key():
    return new_key()


def jwk(private_key, kid):
    key = RSAAlgorithm.to_jwk(private_key.public_key(), as_dict=True)
    key.update({"kid": kid, "alg": "RS256", "use": "sig"})
    return key


def claims(**overrides):
    now = int(time.time())
    data = {
        "iss": ISSUER,
        "aud": [CLIENT_ID, "account"],
        "exp": now + 300,
        "iat": now,
        "sub": "suite-user-id",
        "preferred_username": "suite-user",
    }
    data.update(overrides)
    return {k: v for k, v in data.items() if v is not None}


def mint(private_key, kid=KID, **overrides):
    headers = {"kid": kid} if kid else {}
    return jwt.encode(claims(**overrides), private_key, algorithm="RS256", headers=headers)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class FakeResponse:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload or {}

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.exceptions.HTTPError(f"{self.status_code} Client Error", response=self)


@pytest.fixture(autouse=True)
def clear_jwks_cache():
    keycloakAuth._jwks_cache.clear()
    yield
    keycloakAuth._jwks_cache.clear()


@pytest.fixture
def clock(monkeypatch):
    """Controllable time.monotonic for the JWKS cache, without touching the global time module"""
    state = {"now": 1000.0}
    monkeypatch.setattr(keycloakAuth, "time", types.SimpleNamespace(monotonic=lambda: state["now"]))
    return state


@pytest.fixture
def jwks_server(monkeypatch, signing_key):
    """Serves a JWKS on Session.get and counts the fetches; `keys` can be changed by the test"""
    server = {"keys": [jwk(signing_key, KID)], "calls": []}

    def fake_get(self, url, **kwargs):
        server["calls"].append((url, kwargs))
        return FakeResponse(200, {"keys": list(server["keys"])})

    monkeypatch.setattr(requests.Session, "get", fake_get)
    return server


# ---------------------------------------------------------------------------
# verify_token_locally
# ---------------------------------------------------------------------------
def test_valid_token_returns_claims(jwks_server, signing_key):
    decoded = verify_token(mint(signing_key), service=SERVICE)
    assert decoded["preferred_username"] == "suite-user"
    assert CLIENT_ID in decoded["aud"]
    assert jwks_server["calls"][0][0] == JWKS_URL


def test_audience_as_string_is_accepted(jwks_server, signing_key):
    assert verify_token(mint(signing_key, aud=CLIENT_ID), service=SERVICE)["sub"] == "suite-user-id"


def test_expired_token_is_rejected(jwks_server, signing_key):
    past = int(time.time()) - 3600
    with pytest.raises(KeycloakAuthError, match="expired"):
        verify_token(mint(signing_key, exp=past, iat=past - 300), service=SERVICE)


def test_wrong_audience_is_rejected(jwks_server, signing_key):
    # Keycloak's default aud is "account": without an Audience mapper the token must be refused
    with pytest.raises(KeycloakAuthError, match="audience"):
        verify_token(mint(signing_key, aud="account"), service=SERVICE)


def test_wrong_issuer_is_rejected(jwks_server, signing_key):
    with pytest.raises(KeycloakAuthError, match="issuer"):
        verify_token(mint(signing_key, iss="https://evil.test/realms/windfire"), service=SERVICE)


def test_token_signed_with_another_key_is_rejected(jwks_server, other_key):
    with pytest.raises(KeycloakAuthError):
        verify_token(mint(other_key, kid=KID), service=SERVICE)


def test_token_without_kid_is_rejected(jwks_server, signing_key):
    with pytest.raises(KeycloakAuthError, match="kid"):
        verify_token(mint(signing_key, kid=None), service=SERVICE)


def test_token_with_unknown_kid_is_rejected(jwks_server, signing_key):
    with pytest.raises(KeycloakAuthError, match="not found"):
        verify_token(mint(signing_key, kid="suite-unknown-kid"), service=SERVICE)


def test_alg_none_is_rejected(jwks_server):
    header = b64url(json.dumps({"alg": "none", "typ": "JWT", "kid": KID}).encode())
    payload = b64url(json.dumps(claims()).encode())
    with pytest.raises(KeycloakAuthError):
        verify_token(f"{header}.{payload}.", service=SERVICE)


def test_hs256_key_confusion_is_rejected(jwks_server, signing_key):
    # HS256 "signed" with the public key as HMAC secret: must never be accepted as RS256
    public_pem = signing_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT", "kid": KID}).encode())
    payload = b64url(json.dumps(claims()).encode())
    signature = b64url(hmac.new(public_pem, f"{header}.{payload}".encode(), hashlib.sha256).digest())
    with pytest.raises(KeycloakAuthError):
        verify_token(f"{header}.{payload}.{signature}", service=SERVICE)


@pytest.mark.parametrize("claim", ["exp", "iat", "iss", "aud"])
def test_token_missing_required_claim_is_rejected(jwks_server, signing_key, claim):
    with pytest.raises(KeycloakAuthError):
        verify_token(mint(signing_key, **{claim: None}), service=SERVICE)


def test_garbage_token_is_rejected(jwks_server):
    with pytest.raises(KeycloakAuthError):
        verify_token("not-a-jwt", service=SERVICE)


def test_jwks_fetch_failure_is_reported(monkeypatch, signing_key):
    def failing_get(self, url, **kwargs):
        raise requests.exceptions.ConnectionError("Keycloak down")
    monkeypatch.setattr(requests.Session, "get", failing_get)
    with pytest.raises(KeycloakAuthError, match="public keys"):
        verify_token(mint(signing_key), service=SERVICE)


# ---------------------------------------------------------------------------
# JWKS cache
# ---------------------------------------------------------------------------
def test_second_verify_uses_the_cache(jwks_server, signing_key, clock):
    verify_token(mint(signing_key), service=SERVICE)
    verify_token(mint(signing_key), service=SERVICE)
    assert len(jwks_server["calls"]) == 1


def test_unknown_kid_refetch_is_throttled(jwks_server, signing_key, other_key, clock):
    verify_token(mint(signing_key), service=SERVICE)
    assert len(jwks_server["calls"]) == 1

    # Keycloak rotates its key, but the cache was filled less than 30s ago: no refetch, token refused
    jwks_server["keys"].append(jwk(other_key, OTHER_KID))
    clock["now"] += 10
    with pytest.raises(KeycloakAuthError):
        verify_token(mint(other_key, kid=OTHER_KID), service=SERVICE)
    assert len(jwks_server["calls"]) == 1

    # After 30s the unknown kid triggers one refetch, and the new key is accepted
    clock["now"] += 21
    verify_token(mint(other_key, kid=OTHER_KID), service=SERVICE)
    assert len(jwks_server["calls"]) == 2


def test_cache_expires_after_ttl(jwks_server, signing_key, clock):
    verify_token(mint(signing_key), service=SERVICE)
    clock["now"] += 599
    verify_token(mint(signing_key), service=SERVICE)
    assert len(jwks_server["calls"]) == 1
    clock["now"] += 2
    verify_token(mint(signing_key), service=SERVICE)
    assert len(jwks_server["calls"]) == 2


# ---------------------------------------------------------------------------
# Password login
# ---------------------------------------------------------------------------
@pytest.fixture
def token_endpoint(monkeypatch):
    server = {"status": 200, "calls": []}

    def fake_post(self, url, **kwargs):
        server["calls"].append((url, kwargs))
        return FakeResponse(server["status"], {"access_token": "a.b.c", "expires_in": 300, "token_type": "Bearer"})

    monkeypatch.setattr(requests.Session, "post", fake_post)
    return server


def test_password_login_sends_client_secret(token_endpoint):
    tokens = KeycloakAuth(KeycloakConfig(service=SERVICE)).authenticate_with_password("suite-user", "pw")
    assert tokens["access_token"] == "a.b.c"
    url, kwargs = token_endpoint["calls"][0]
    assert url == TOKEN_URL
    assert kwargs["data"] == {"grant_type": "password", "client_id": CLIENT_ID, "username": "suite-user",
                              "password": "pw", "client_secret": CLIENT_SECRET}


def test_password_login_verifies_keycloak_with_expanded_ca_path(token_endpoint, monkeypatch):
    monkeypatch.setenv("KEYCLOAK_VERIFY_SSL_CERTS", "true")
    monkeypatch.setenv("KEYCLOAK_CA_CERT_PATH", "~/suite/WindfireKeycloakRootCA.crt")
    KeycloakAuth(KeycloakConfig(service=SERVICE)).authenticate_with_password("suite-user", "pw")
    assert token_endpoint["calls"][0][1]["verify"] == os.path.expanduser("~/suite/WindfireKeycloakRootCA.crt")


def test_password_login_rejected_by_keycloak(token_endpoint):
    token_endpoint["status"] = 401
    with pytest.raises(KeycloakAuthError):
        KeycloakAuth(KeycloakConfig(service=SERVICE)).authenticate_with_password("suite-user", "wrong")


# ---------------------------------------------------------------------------
# KeycloakConfig.verify (TLS verification of the calls to Keycloak)
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("verify_ssl, ca_path, expected", [
    ("false", "", False),
    ("false", "~/ca.crt", False),
    ("true", "", True),
    ("true", "~/ca.crt", os.path.expanduser("~/ca.crt")),
    (None, "", True),  # unset: secure by default
])
def test_keycloak_config_verify(monkeypatch, verify_ssl, ca_path, expected):
    if verify_ssl is None:
        monkeypatch.delenv("KEYCLOAK_VERIFY_SSL_CERTS", raising=False)
    else:
        monkeypatch.setenv("KEYCLOAK_VERIFY_SSL_CERTS", verify_ssl)
    monkeypatch.setenv("KEYCLOAK_CA_CERT_PATH", ca_path)
    assert KeycloakConfig(service=SERVICE).verify == expected


def test_keycloak_config_endpoints_strip_trailing_slash(monkeypatch):
    monkeypatch.setenv("KEYCLOAK_SERVER_URL", KEYCLOAK_URL + "/")
    config = KeycloakConfig(service=SERVICE)
    assert config.jwks_endpoint == JWKS_URL
    assert config.token_endpoint == TOKEN_URL
