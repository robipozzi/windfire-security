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
        {"id": "acc-uuid", "clientId": "account-console", "rootUrl": "${authBaseUrl}",
         "baseUrl": "/realms/windfire/account/", "redirectUris": ["/realms/windfire/account/*"]},
        {"id": "adm-uuid", "clientId": "security-admin-console", "baseUrl": "/admin/windfire/console/",
         "redirectUris": ["/admin/windfire/console/*"]},
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
    assert "secret" not in realm["clients"][3]
    assert realm["smtpServer"] == {"host": "smtp"}
    assert "org.keycloak.keys.KeyProvider" not in realm["components"]
    assert "org.keycloak.userprofile.UserProfileProvider" in realm["components"]


def test_keeps_clients_roles_and_mappers():
    realm = copy()
    assert [c["clientId"] for c in realm["clients"]] == [
        "account-console", "security-admin-console", "windfire-ui", "windfire-calendar-srv"]
    assert realm["clients"][2]["protocolMappers"] == [{"name": "audience"}]
    assert realm["roles"]["client"]["windfire-restaurants-api"] == [{"name": "restaurants-reader"}]


def test_source_export_unchanged():
    before = json.dumps(EXPORT, sort_keys=True)
    copy()
    assert json.dumps(EXPORT, sort_keys=True) == before


def test_rewrites_built_in_client_paths_to_the_new_realm():
    account, admin = copy()["clients"][:2]
    assert account["baseUrl"] == "/realms/windfire-dev/account/"
    assert account["redirectUris"] == ["/realms/windfire-dev/account/*"]
    assert account["rootUrl"] == "${authBaseUrl}"
    assert admin["baseUrl"] == "/admin/windfire-dev/console/"
    assert admin["redirectUris"] == ["/admin/windfire-dev/console/*"]


def test_leaves_other_urls_and_longer_realm_names_alone():
    rename = keycloak_realm._path_renamer("windfire", "windfire-dev")
    assert rename("https://app.windfire.cc/") == "https://app.windfire.cc/"
    assert rename("/realms/windfire-other/account/") == "/realms/windfire-other/account/"
    assert rename("https://localhost:3000/*") == "https://localhost:3000/*"


USERS = [
    {"id": "u1", "username": "alice", "email": "alice@example.com", "firstName": "Alice", "enabled": True,
     "emailVerified": True, "createdTimestamp": 1, "totp": True, "access": {"manage": True},
     "attributes": {"locale": ["it"]}, "requiredActions": ["CONFIGURE_TOTP"],
     "credentials": [{"type": "password"}], "federatedIdentities": [], "notBefore": 0},
    {"id": "u2", "username": "service-account-windfire-calendar-srv", "serviceAccountClientId": "windfire-calendar-srv"},
    {"id": "u3", "username": "bob"},
]
ROLE_MAPPINGS = [
    {"item": {"id": "u1"}, "json": {
        "realmMappings": [{"id": "r1", "name": "default-roles-windfire"}, {"id": "r2", "name": "admin"}],
        "clientMappings": {"windfire-restaurants-api": {"id": "c1", "client": "windfire-restaurants-api",
                                                        "mappings": [{"id": "r3", "name": "restaurants-writer"}]}}}},
    {"item": {"id": "u2"}, "json": {}},
    {"item": {"id": "u3"}, "json": {}},
]
GROUPS = [
    {"item": {"id": "u1"}, "json": [{"id": "g1", "name": "editors", "path": "/staff/editors"}]},
    {"item": {"id": "u2"}, "json": []},
    {"item": {"id": "u3"}, "json": []},
]


def users_copy():
    return keycloak_realm.keycloak_users_copy(USERS, ROLE_MAPPINGS, GROUPS, "default-roles-windfire",
                                              "default-roles-windfire-dev")


def test_users_copy_keeps_profile_roles_and_groups():
    alice = users_copy()[0]
    assert alice["username"] == "alice"
    assert alice["email"] == "alice@example.com"
    assert alice["attributes"] == {"locale": ["it"]}
    assert alice["requiredActions"] == ["CONFIGURE_TOTP"]
    assert alice["realmRoles"] == ["default-roles-windfire-dev", "admin"]
    assert alice["clientRoles"] == {"windfire-restaurants-api": ["restaurants-writer"]}
    assert alice["groups"] == ["/staff/editors"]


def test_users_copy_drops_ids_credentials_and_service_accounts():
    users = users_copy()
    assert [u["username"] for u in users] == ["alice", "bob"]
    for key in ("id", "createdTimestamp", "access", "credentials", "totp", "federatedIdentities", "notBefore"):
        assert key not in users[0]
    assert users[1] == {"username": "bob", "realmRoles": [], "clientRoles": {}, "groups": []}
