"""POST /v1/security/auth against the live server (read-only: only logins)"""
import pytest

from suite_helpers import INVALID_CREDENTIALS_DETAIL, NONEXISTENT_USERNAME, UNKNOWN_SERVICE


def skip_if_rate_limited(response):
    # The server limits logins per client IP (5/minute, 30/hour) and locks a username after 10 failures
    # in 15 minutes: back-to-back runs can hit those limits, which is not a failure of the endpoint
    if response.status_code == 429:
        pytest.skip(f"rate limited (429, Retry-After {response.headers.get('Retry-After')}s): run the suite again later")


def test_valid_credentials_return_a_token(auth_response):
    assert auth_response["token_type"] == "Bearer"
    assert auth_response["expires_in"] > 0
    assert len(auth_response["access_token"].split(".")) == 3


def test_bad_credentials_are_rejected(http, base_url, service):
    # A username that does not exist: Keycloak's brute-force protection never locks a real user
    response = http.post(f"{base_url}/v1/security/auth", timeout=15, json={
        "username": NONEXISTENT_USERNAME, "password": "suite-wrong-password", "service": service})
    skip_if_rate_limited(response)
    assert response.status_code == 401
    assert response.json()["detail"] == INVALID_CREDENTIALS_DETAIL


def test_unknown_service_is_rejected(http, base_url, service):
    response = http.post(f"{base_url}/v1/security/auth", timeout=15, json={
        "username": NONEXISTENT_USERNAME, "password": "suite-wrong-password", "service": UNKNOWN_SERVICE})
    skip_if_rate_limited(response)
    assert response.status_code == 401
    assert service not in response.text


def test_missing_field_is_rejected(http, base_url):
    response = http.post(f"{base_url}/v1/security/auth", json={"username": NONEXISTENT_USERNAME}, timeout=15)
    assert response.status_code == 422
