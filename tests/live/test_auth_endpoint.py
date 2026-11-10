"""POST /v1/security/auth against the live server (read-only: only logins)"""
from suite_helpers import INVALID_CREDENTIALS_DETAIL, NONEXISTENT_USERNAME, UNKNOWN_SERVICE


def test_valid_credentials_return_a_token(auth_response):
    assert auth_response["token_type"] == "Bearer"
    assert auth_response["expires_in"] > 0
    assert len(auth_response["access_token"].split(".")) == 3


def test_bad_credentials_are_rejected(http, base_url, service):
    # A username that does not exist: Keycloak's brute-force protection never locks a real user
    response = http.post(f"{base_url}/v1/security/auth", timeout=15, json={
        "username": NONEXISTENT_USERNAME, "password": "suite-wrong-password", "service": service})
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_CREDENTIALS_DETAIL


def test_unknown_service_is_rejected(http, base_url, service):
    response = http.post(f"{base_url}/v1/security/auth", timeout=15, json={
        "username": NONEXISTENT_USERNAME, "password": "suite-wrong-password", "service": UNKNOWN_SERVICE})
    assert response.status_code == 401
    assert service not in response.text


def test_missing_field_is_rejected(http, base_url):
    response = http.post(f"{base_url}/v1/security/auth", json={"username": NONEXISTENT_USERNAME}, timeout=15)
    assert response.status_code == 422
