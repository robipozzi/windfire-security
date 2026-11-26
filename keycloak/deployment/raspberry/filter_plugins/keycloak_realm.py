# Ansible filter used by keycloak-dev-realm.yaml: turns a Keycloak partial export of one realm into the
# representation of a new realm that can be POSTed to /admin/realms on the same Keycloak.
import copy

# Keycloak masks every secret in a partial export with this value: importing it would set it as the real secret
MASKED = "**********"
# Database ids of the source realm's entities: they are global primary keys, so the copy must not reuse them
ID_KEYS = ("id", "containerId", "_id", "internalId")


def _strip(node, source_realm_id):
    if isinstance(node, dict):
        out = {}
        for key, value in node.items():
            if key in ID_KEYS or value == MASKED:
                continue
            # Top-level components point at the realm id: left out, the import attaches them to the new realm
            if key == "parentId" and value == source_realm_id:
                continue
            out[key] = _strip(value, source_realm_id)
        return out
    if isinstance(node, list):
        return [_strip(item, source_realm_id) for item in node]
    return node


def keycloak_realm_copy(export, realm, display_name, frontend_url):
    """Copy of a partial export as a new realm named `realm`, with its Frontend URL pinned to `frontend_url`.

    - drops every database id and every masked secret: confidential clients get new secrets on import;
    - drops the key providers (their private keys are masked): the new realm generates its own keys;
    - users are not in a partial export, so the new realm has none.
    """
    source = copy.deepcopy(export)
    source_realm_id = source.get("id")
    components = source.get("components") or {}
    components.pop("org.keycloak.keys.KeyProvider", None)
    new = _strip(source, source_realm_id)
    new["realm"] = realm
    new["displayName"] = display_name
    new["enabled"] = True
    attributes = dict(new.get("attributes") or {})
    attributes["frontendUrl"] = frontend_url
    new["attributes"] = attributes
    return new


class FilterModule(object):
    def filters(self):
        return {"keycloak_realm_copy": keycloak_realm_copy}
