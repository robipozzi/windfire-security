"""POST /v1/security/verify against the live server"""
import pytest

from suite_helpers import INVALID_TOKEN_DETAIL, SECURITY_HEADERS, UNKNOWN_SERVICE


def verify(http, base_url, token, service):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return http.post(f"{base_url}/v1/security/verify", json={"service": service}, headers=headers, timeout=15)


def tamper(token):
    header, payload, signature = token.split(".")
    i = len(signature) // 2
    signature = signature[:i] + ("A" if signature[i] != "A" else "B") + signature[i + 1:]
    return f"{header}.{payload}.{signature}"


def test_valid_token(http, base_url, token, service):
    # Fails on a KEYCLOAK_SERVER_URL that doesn't match the token issuer, or a missing Audience mapper
    response = verify(http, base_url, token, service)
    assert response.status_code == 200, response.text
    assert response.json() == {"status": "valid"}


def test_tampered_signature(http, base_url, token, service):
    response = verify(http, base_url, tamper(token), service)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_TOKEN_DETAIL


def test_garbage_token(http, base_url, service):
    response = verify(http, base_url, "suite.garbage.token", service)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_TOKEN_DETAIL


def test_valid_token_for_wrong_service(http, base_url, token, service):
    response = verify(http, base_url, token, UNKNOWN_SERVICE)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_TOKEN_DETAIL
    assert service not in response.text


def test_missing_authorization_header(http, base_url, service):
    assert verify(http, base_url, None, service).status_code in (401, 403)


@pytest.mark.parametrize("header, value", SECURITY_HEADERS.items())
def test_security_headers(http, base_url, service, header, value):
    assert verify(http, base_url, "suite.garbage.token", service).headers.get(header) == value
