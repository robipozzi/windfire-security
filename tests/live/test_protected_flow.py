"""
Full downstream flow, the automated version of the two-terminal manual test:
test/testServer.py (a dummy service) protects POST /test by asking the auth server to verify the token.
"""
import importlib.util
import os
import subprocess
import sys
import time

import pytest
import requests

from suite_helpers import REPO_DIR, REPORTS_DIR, free_port

pytestmark = pytest.mark.flow

if importlib.util.find_spec("client") is None:
    pytest.skip("client.authClient not installed (pip install -e $HOME/dev/windfire-security-client)",
                allow_module_level=True)

START_TIMEOUT_SECONDS = 20


@pytest.fixture(scope="module")
def test_server(env_cfg):
    """Starts test/testServer.py on a free port (plain HTTP) and stops it after the module"""
    port = free_port()
    env = dict(os.environ,
               ENVIRONMENT=env_cfg["name"],
               PORT=str(port),
               WINDFIRE_SECURITY_HOST=env_cfg["host"],
               WINDFIRE_SECURITY_PORT=str(env_cfg["port"]),
               ENFORCE_AUTH_SERVER_HTTPS="true",
               VERIFY_SSL_CERTS="true",
               ROOT_CA_PATH=env_cfg["root_ca"])
    REPORTS_DIR.mkdir(exist_ok=True)
    log_path = REPORTS_DIR / f"testServer-{env_cfg['name']}.log"
    with open(log_path, "w") as log:
        process = subprocess.Popen([sys.executable, "testServer.py"], cwd=REPO_DIR / "test", env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
    url = f"http://127.0.0.1:{port}"
    try:
        deadline = time.monotonic() + START_TIMEOUT_SECONDS
        while True:
            if process.poll() is not None:
                pytest.fail(f"test/testServer.py exited with {process.returncode}, see {log_path}")
            try:
                if requests.get(f"{url}/health", timeout=1).status_code == 200:
                    break
            except requests.exceptions.ConnectionError:
                pass
            if time.monotonic() > deadline:
                pytest.fail(f"test/testServer.py not ready after {START_TIMEOUT_SECONDS}s, see {log_path}")
            time.sleep(0.3)
        yield url
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def call_protected(url, token, service):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return requests.post(f"{url}/test", json={"service": service}, headers=headers, timeout=20)


def test_protected_endpoint_with_valid_token(test_server, token, service):
    response = call_protected(test_server, token, service)
    assert response.status_code == 200, response.text


def test_protected_endpoint_without_token(test_server, service):
    assert call_protected(test_server, None, service).status_code in (401, 403)


def test_protected_endpoint_with_bad_token(test_server, service):
    assert call_protected(test_server, "suite.garbage.token", service).status_code == 401
