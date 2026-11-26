"""keycloak_realm_copy (keycloak/deployment/raspberry/filter_plugins): partial export of windfire -> new windfire-dev realm"""
import importlib.util
import json
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "keycloak_realm", REPO_DIR / "keycloak/deployment/raspberry/filter_plugins/keycloak_realm.py")
keycloak_realm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(keycloak_realm)

INTERNAL = "https://raspberry01:8443"
EXPORT = {
    "id": "realm-uuid",
    "realm": "windfire",
    "displayName": "Windfire",
    "enabled": True,
    "attributes": {"frontendUrl": "https://auth.windfire.cc", "other": "kept"},
    "smtpServer": {"host": "smtp", "password": "**********"},
    "roles": {
        "realm": [{"id": "role-uuid", "name": "user", "containerId": "realm-uuid"}],
        "client": {"windfire-restaurants-api": [{"id": "r2", "name": "restaurants-reader", "containerId": "client-uuid"}]},
    },
    "clients": [
        {"id": "client-uuid", "clientId": "windfire-ui", "publicClient": True,
         "protocolMappers": [{"id": "mapper-uuid", "name": "audience"}]},
        {"id": "client2-uuid", "clientId": "windfire-calendar-srv", "publicClient": False, "secret": "**********",
         "authorizationSettings": {"resources": [{"_id": "res-uuid", "name": "Default Resource"}]}},
    ],
    "components": {
        "org.keycloak.keys.KeyProvider": [{"id": "key-uuid", "config": {"privateKey": ["**********"]}}],
        "org.keycloak.userprofile.UserProfileProvider": [{"id": "up-uuid", "parentId": "realm-uuid", "config": {}}],
    },
}


def copy():
    return keycloak_realm.keycloak_realm_copy(EXPORT, "windfire-dev", "Windfire DEV", INTERNAL)


def test_renames_and_pins_frontend_url():
    realm = copy()
    assert realm["realm"] == "windfire-dev"
    assert realm["displayName"] == "Windfire DEV"
    assert realm["enabled"] is True
    assert realm["attributes"] == {"frontendUrl": INTERNAL, "other": "kept"}


def test_drops_every_database_id():
    text = json.dumps(copy())
    for value in ("realm-uuid", "role-uuid", "client-uuid", "mapper-uuid", "res-uuid", "up-uuid", "r2"):
        assert value not in text
    for key in ('"id"', '"containerId"', '"_id"', '"parentId"'):
        assert key not in text


def test_drops_masked_secrets_and_key_providers():
    realm = copy()
    assert "**********" not in json.dumps(realm)
    assert "secret" not in realm["clients"][1]
    assert realm["smtpServer"] == {"host": "smtp"}
    assert "org.keycloak.keys.KeyProvider" not in realm["components"]
    assert "org.keycloak.userprofile.UserProfileProvider" in realm["components"]


def test_keeps_clients_roles_and_mappers():
    realm = copy()
    assert [c["clientId"] for c in realm["clients"]] == ["windfire-ui", "windfire-calendar-srv"]
    assert realm["clients"][0]["protocolMappers"] == [{"name": "audience"}]
    assert realm["roles"]["client"]["windfire-restaurants-api"] == [{"name": "restaurants-reader"}]


def test_source_export_unchanged():
    before = json.dumps(EXPORT, sort_keys=True)
    copy()
    assert json.dumps(EXPORT, sort_keys=True) == before
