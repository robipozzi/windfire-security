"""windfire-security-client (client.authClient) against the live server"""
import importlib.util
import os
from pathlib import Path

import pytest

from suite_helpers import free_port

pytestmark = pytest.mark.client

if importlib.util.find_spec("client") is None:
    pytest.skip("client.authClient not installed (pip install -e $HOME/dev/windfire-security-client)",
                allow_module_level=True)


@pytest.fixture(scope="module")
def client_env(env_cfg):
    """Environment the client library reads, pointed at the environment under test"""
    (Path.home() / "logs").mkdir(exist_ok=True)  # the client logger writes to ~/logs
    values = {
        "ENVIRONMENT": env_cfg["name"],
        "WINDFIRE_SECURITY_HOST": env_cfg["host"],
        "WINDFIRE_SECURITY_PORT": str(env_cfg["port"]),
        "ENFORCE_AUTH_SERVER_HTTPS": "true",
        "VERIFY_SSL_CERTS": "true",
        "ROOT_CA_PATH": env_cfg["root_ca"],
    }
    with pytest.MonkeyPatch.context() as mp:
        for key, value in values.items():
            mp.setenv(key, value)
        yield values


@pytest.fixture(scope="module")
def auth_client_module(client_env):
    import client.authClient as module
    return module


@pytest.fixture
def auth_client(auth_client_module):
    # A new instance reads the environment now, whatever it was when the module was first imported
    return auth_client_module.AuthClient()


def test_authenticate_returns_token(auth_client, credentials):
    token = auth_client.authenticate(credentials["username"], credentials["password"], credentials["service"])
    assert token and len(token.split(".")) == 3


def test_verify_or_raise_valid_token(auth_client, token, service):
    assert auth_client.verify_or_raise(token, service) is True


def test_verify_or_raise_garbage_token(auth_client, service):
    assert auth_client.verify_or_raise("suite.garbage.token", service) is False


def test_unreachable_server_raises(auth_client_module, client_env, service, monkeypatch):
    monkeypatch.setenv("WINDFIRE_SECURITY_HOST", "127.0.0.1")
    monkeypatch.setenv("WINDFIRE_SECURITY_PORT", str(free_port()))
    with pytest.raises(auth_client_module.AuthServerError):
        auth_client_module.AuthClient().verify_or_raise("suite.garbage.token", service)
