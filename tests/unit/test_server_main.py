"""authServer.main(): which port and TLS settings reach uvicorn.run (--port vs .env)"""
import pytest

import authServer

from hermetic import API_PORT, API_PORT_SECURE


@pytest.fixture
def uvicorn_run(monkeypatch):
    calls = []
    monkeypatch.setattr(authServer.uvicorn, "run", lambda app, **kwargs: calls.append(kwargs))
    return calls


@pytest.fixture
def https(monkeypatch, tmp_path):
    key, cert = tmp_path / "server.key", tmp_path / "server.crt"
    key.write_text("key")
    cert.write_text("cert")
    monkeypatch.setenv("SSL_KEYFILE", str(key))
    monkeypatch.setenv("SSL_CERTFILE", str(cert))
    monkeypatch.setattr(authServer, "ENFORCE_HTTPS", True)
    return str(key), str(cert)


@pytest.fixture
def plain_http(monkeypatch):
    monkeypatch.setattr(authServer, "ENFORCE_HTTPS", False)


def test_https_uses_api_port_secure(uvicorn_run, https):
    authServer.main()
    assert uvicorn_run == [{"host": "127.0.0.1", "port": API_PORT_SECURE,
                            "ssl_keyfile": https[0], "ssl_certfile": https[1]}]


def test_https_port_override(uvicorn_run, https):
    authServer.main(port_override=9100)
    assert uvicorn_run[0]["port"] == 9100
    assert uvicorn_run[0]["ssl_certfile"] == https[1]


def test_http_uses_api_port(uvicorn_run, plain_http):
    authServer.main()
    assert uvicorn_run == [{"host": "127.0.0.1", "port": API_PORT}]


def test_http_port_override(uvicorn_run, plain_http):
    authServer.main(port_override=9100)
    assert uvicorn_run == [{"host": "127.0.0.1", "port": 9100}]


def test_https_with_missing_cert_files_exits(uvicorn_run, monkeypatch, tmp_path):
    monkeypatch.setattr(authServer, "ENFORCE_HTTPS", True)
    monkeypatch.setenv("SSL_KEYFILE", str(tmp_path / "missing.key"))
    monkeypatch.setenv("SSL_CERTFILE", str(tmp_path / "missing.crt"))
    with pytest.raises(SystemExit):
        authServer.main()
    assert uvicorn_run == []
