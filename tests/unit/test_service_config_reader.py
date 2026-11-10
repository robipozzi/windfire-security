"""config.service_config_reader: the per-service Keycloak realm/client registry"""
import json

import pytest

from config.service_config_reader import ServiceConfigError, ServiceConfigReader


def write(tmp_path, content):
    path = tmp_path / "service_config.json"
    path.write_text(content if isinstance(content, str) else json.dumps(content))
    return str(path)


VALID = {
    "services": {
        "svc-a": {"realm": "windfire", "client_id": "client-a", "client_secret": "secret-a"},
        "svc-b": {"realm": "other", "client_id": "client-b", "client_secret": "secret-b"},
    }
}


def test_valid_file(tmp_path):
    reader = ServiceConfigReader(write(tmp_path, VALID))
    svc = reader.get_service("svc-a")
    assert (svc.realm, svc.client_id, svc.client_secret) == ("windfire", "client-a", "secret-a")
    assert sorted(reader.list_services()) == ["svc-a", "svc-b"]
    assert reader.service_exists("svc-b")
    assert not reader.service_exists("svc-c")


def test_default_path_comes_from_service_config_file(tmp_path, monkeypatch):
    monkeypatch.setenv("SERVICE_CONFIG_FILE", write(tmp_path, VALID))
    assert ServiceConfigReader().service_exists("svc-a")


def test_empty_services_is_allowed(tmp_path):
    assert ServiceConfigReader(write(tmp_path, {"services": {}})).list_services() == []


def test_missing_file(tmp_path):
    with pytest.raises(ServiceConfigError, match="not found"):
        ServiceConfigReader(str(tmp_path / "missing.json"))


def test_invalid_json(tmp_path):
    with pytest.raises(ServiceConfigError, match="Invalid JSON"):
        ServiceConfigReader(write(tmp_path, "{not json"))


@pytest.mark.parametrize("content", [{"other": {}}, [], {"services": []}])
def test_invalid_structure(tmp_path, content):
    with pytest.raises(ServiceConfigError):
        ServiceConfigReader(write(tmp_path, content))


@pytest.mark.parametrize("field", ["realm", "client_id"])
def test_missing_required_field(tmp_path, field):
    service = {"realm": "windfire", "client_id": "client-a", "client_secret": "s"}
    del service[field]
    with pytest.raises(ServiceConfigError, match=field):
        ServiceConfigReader(write(tmp_path, {"services": {"svc-a": service}}))


@pytest.mark.parametrize("field", ["realm", "client_id"])
@pytest.mark.parametrize("value", ["", "   ", 42])
def test_empty_or_wrong_type_field(tmp_path, field, value):
    service = {"realm": "windfire", "client_id": "client-a", "client_secret": "s", field: value}
    with pytest.raises(ServiceConfigError, match=field):
        ServiceConfigReader(write(tmp_path, {"services": {"svc-a": service}}))


def test_unknown_service(tmp_path):
    reader = ServiceConfigReader(write(tmp_path, VALID))
    with pytest.raises(ServiceConfigError, match="not found"):
        reader.get_service("svc-c")


def test_repr_masks_secret(tmp_path):
    svc = ServiceConfigReader(write(tmp_path, VALID)).get_service("svc-a")
    assert "secret-a" not in repr(svc)
    assert "***" in repr(svc)
