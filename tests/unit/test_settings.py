"""config.settings: type coercion of the .env values"""
import pytest

from config.settings import settings


@pytest.mark.parametrize("key", ["ENFORCE_HTTPS", "KEYCLOAK_VERIFY_SSL_CERTS"])
@pytest.mark.parametrize("raw, expected", [
    ("true", True), ("TRUE", True), (" True ", True), ("1", True), ("yes", True), ("on", True),
    ("false", False), ("0", False), ("no", False), ("", False), ("anything", False),
])
def test_bool_keys_are_coerced(monkeypatch, key, raw, expected):
    monkeypatch.setenv(key, raw)
    assert settings.get(key) is expected


@pytest.mark.parametrize("key", ["ENFORCE_HTTPS", "KEYCLOAK_VERIFY_SSL_CERTS"])
def test_bool_key_unset_is_none(monkeypatch, key):
    monkeypatch.delenv(key, raising=False)
    assert settings.get(key) is None


@pytest.mark.parametrize("key", ["API_PORT", "API_PORT_SECURE"])
@pytest.mark.parametrize("raw, expected", [("8444", 8444), (" 8000 ", 8000), ("abc", None), ("", None), ("  ", None)])
def test_port_keys_are_coerced(monkeypatch, key, raw, expected):
    monkeypatch.setenv(key, raw)
    assert settings.get(key) == expected


@pytest.mark.parametrize("key", ["API_PORT", "API_PORT_SECURE"])
def test_port_key_unset_is_none(monkeypatch, key):
    monkeypatch.delenv(key, raising=False)
    assert settings.get(key) is None


def test_unknown_key_returns_raw_string(monkeypatch):
    monkeypatch.setenv("SUITE_SOME_KEY", "some value")
    assert settings.get("SUITE_SOME_KEY") == "some value"


@pytest.mark.parametrize("key", ["PORT", "API", "API_POR", "SECURE"])
def test_only_exact_port_keys_are_coerced(monkeypatch, key):
    # Regression: a substring match ("key in 'API_PORT'") turned any part of the name into an int key
    monkeypatch.setenv(key, "9000")
    assert settings.get(key) == "9000"


def test_missing_key_is_none(monkeypatch):
    monkeypatch.delenv("SUITE_MISSING_KEY", raising=False)
    assert settings.get("SUITE_MISSING_KEY") is None
