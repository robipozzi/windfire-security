"""authServer.app through FastAPI's TestClient: routes, error mapping, middleware and CORS"""
import pytest
from fastapi.testclient import TestClient

import authServer
import routers.authRouters as authRouters
from keycloakAuth import KeycloakAuthError

from hermetic import OTHER_SERVICE, SERVICE

INVALID_TOKEN_DETAIL = "Invalid or expired token"
SECURITY_HEADERS = {
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
    "x-xss-protection": "1; mode=block",
}
LOGIN = {"username": "suite-user", "password": "pw", "service": SERVICE}
BEARER = {"Authorization": "Bearer a.b.c"}


@pytest.fixture
def client():
    with TestClient(authServer.app, base_url="https://localhost", follow_redirects=False) as c:
        yield c


@pytest.fixture
def http_client():
    with TestClient(authServer.app, base_url="http://localhost", follow_redirects=False) as c:
        yield c


def raise_(exc):
    def _raise(*args, **kwargs):
        raise exc
    return _raise


# ---------------------------------------------------------------------------
# Health and routing
# ---------------------------------------------------------------------------
def test_health(client):
    response = client.get("/v1/monitor/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_root_redirects_to_docs(client):
    response = client.get("/")
    assert response.status_code == 307
    assert response.headers["location"] == "/docs"


def test_v2_does_not_exist(client):
    assert client.get("/v2/monitor/health").status_code == 404


# ---------------------------------------------------------------------------
# POST /v1/security/auth
# ---------------------------------------------------------------------------
def test_auth_success(client, monkeypatch):
    calls = []

    def fake_authenticate_user(username, password, service):
        calls.append((username, password, service))
        return {"access_token": "a.b.c", "expires_in": 300, "refresh_token": "r",
                "refresh_expires_in": 1800, "scope": "openid profile"}

    monkeypatch.setattr(authRouters, "authenticate_user", fake_authenticate_user)
    response = client.post("/v1/security/auth", json=LOGIN)
    assert response.status_code == 200
    assert response.json() == {"access_token": "a.b.c", "token_type": "Bearer", "expires_in": 300,
                               "refresh_token": "r", "refresh_expires_in": 1800, "scope": "openid profile"}
    assert calls == [("suite-user", "pw", SERVICE)]


def test_auth_bad_credentials(client, monkeypatch):
    monkeypatch.setattr(authRouters, "authenticate_user", raise_(KeycloakAuthError("401 Unauthorized")))
    response = client.post("/v1/security/auth", json=LOGIN)
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid username or password"


def test_auth_unexpected_error(client, monkeypatch):
    monkeypatch.setattr(authRouters, "authenticate_user", raise_(RuntimeError("boom")))
    response = client.post("/v1/security/auth", json=LOGIN)
    assert response.status_code == 500
    assert "boom" not in response.text


def test_auth_unknown_service(client):
    # Real authenticate_user: the unknown service fails in the service registry, before any call to Keycloak
    response = client.post("/v1/security/auth", json={**LOGIN, "service": "suite-unknown-service"})
    assert response.status_code == 401
    assert SERVICE not in response.text
    assert OTHER_SERVICE not in response.text


@pytest.mark.parametrize("missing", ["username", "password", "service"])
def test_auth_missing_field(client, missing):
    body = {k: v for k, v in LOGIN.items() if k != missing}
    assert client.post("/v1/security/auth", json=body).status_code == 422


# ---------------------------------------------------------------------------
# POST /v1/security/verify
# ---------------------------------------------------------------------------
def test_verify_valid_token(client, monkeypatch):
    calls = []

    def fake_verify_token(token, service, method):
        calls.append((token, service, method))
        return {"sub": "suite-user-id"}

    monkeypatch.setattr(authRouters, "verify_token", fake_verify_token)
    response = client.post("/v1/security/verify", json={"service": SERVICE}, headers=BEARER)
    assert response.status_code == 200
    assert response.json() == {"status": "valid"}
    assert calls == [("a.b.c", SERVICE, "local")]


@pytest.mark.parametrize("exc", [KeycloakAuthError("Token has expired"), RuntimeError("boom")])
def test_verify_invalid_token(client, monkeypatch, exc):
    monkeypatch.setattr(authRouters, "verify_token", raise_(exc))
    response = client.post("/v1/security/verify", json={"service": SERVICE}, headers=BEARER)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_TOKEN_DETAIL


def test_verify_unknown_service_hides_configured_services(client):
    response = client.post("/v1/security/verify", json={"service": "suite-unknown-service"}, headers=BEARER)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_TOKEN_DETAIL
    assert SERVICE not in response.text
    assert OTHER_SERVICE not in response.text


def test_verify_without_bearer(client):
    assert client.post("/v1/security/verify", json={"service": SERVICE}).status_code in (401, 403)


def test_verify_missing_service(client):
    assert client.post("/v1/security/verify", json={}, headers=BEARER).status_code == 422


# ---------------------------------------------------------------------------
# Middleware: HTTPS enforcement, security headers, trusted hosts
# ---------------------------------------------------------------------------
def test_plain_http_is_redirected_to_https(http_client):
    response = http_client.get("/docs")
    assert response.status_code == 307
    assert response.headers["location"] == "https://localhost/docs"


def test_plain_http_is_redirected_for_api_calls(http_client):
    response = http_client.post("/v1/security/verify", json={"service": SERVICE}, headers=BEARER)
    assert response.status_code == 307
    assert response.headers["location"].startswith("https://")


def test_health_is_exempt_from_https_enforcement(http_client):
    # Load balancers probe /health over plain HTTP: paths ending in /health are not redirected
    response = http_client.get("/v1/monitor/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.parametrize("path", ["/docs", "/v1/security/verify"])
def test_security_headers(client, path):
    # Checked on non-health paths: the health exemption skips the headers too
    response = client.get(path) if path == "/docs" else client.post(path, json={"service": SERVICE})
    for header, value in SECURITY_HEADERS.items():
        assert response.headers.get(header) == value, header


def test_unknown_host_is_rejected(client):
    response = client.get("/v1/monitor/health", headers={"host": "evil.com"})
    assert response.status_code == 400


# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------
def test_cors_does_not_allow_foreign_origins(client):
    # No browser client calls the server directly (the UIs go through their own backends), so
    # no origin gets CORS access. allow_origins is ALLOWED_HOSTS (bare host names), which never
    # matches an Origin: if a browser client is ever added, this test must change with the fix.
    for origin in ("https://evil.com", "https://localhost:9443"):
        response = client.options("/v1/security/auth", headers={
            "Origin": origin, "Access-Control-Request-Method": "POST"})
        assert response.headers.get("access-control-allow-origin") is None, origin
