"""
Shared configuration of the Windfire Security test suite.

- `--env dev|test|prod` selects the target of the live tier (tests/environments.json).
- Tests under unit/ get the `unit` marker, tests under live/ the `live` marker.
- Live fixtures: env_cfg, base_url, http (a requests session that trusts the Windfire Root CA),
  credentials (WINDFIRE_TEST_USERNAME / WINDFIRE_TEST_PASSWORD / WINDFIRE_TEST_SERVICE), auth_response and token.
"""
import os
from pathlib import Path

import pytest

from suite_helpers import TESTS_DIR, load_env_cfg


def pytest_addoption(parser):
    parser.addoption("--env", action="store", default=None, choices=("dev", "test", "prod"),
                     help="Windfire Security environment targeted by the live tests")


def pytest_collection_modifyitems(config, items):
    for item in items:
        parts = Path(item.path).relative_to(TESTS_DIR).parts
        if parts[0] == "unit":
            item.add_marker(pytest.mark.unit)
        elif parts[0] == "live":
            item.add_marker(pytest.mark.live)
    # Keycloak checks first: if Keycloak is down, its failure explains the 401s that follow
    items.sort(key=lambda item: 0 if Path(item.path).name == "test_keycloak.py" else 1)


# ---------------------------------------------------------------------------
# Environment configuration
# ---------------------------------------------------------------------------
@pytest.fixture(scope="session")
def env_cfg(request):
    name = request.config.getoption("--env")
    if not name:
        pytest.skip("live tests need --env dev|test|prod")
    cfg = load_env_cfg(name)
    if not cfg.get("host") or not cfg.get("port"):
        pytest.skip(f"environment '{name}' not configured in tests/environments.json")
    if not os.path.isfile(cfg["root_ca"]):
        pytest.fail(f"Windfire Root CA not found: {cfg['root_ca']}")
    return cfg


@pytest.fixture(scope="session")
def base_url(env_cfg):
    return f"https://{env_cfg['host']}:{env_cfg['port']}"


@pytest.fixture(scope="session")
def http(env_cfg):
    """requests session that verifies the server against the Windfire Root CA (never verify=False)"""
    import requests
    session = requests.Session()
    session.verify = env_cfg["root_ca"]
    yield session
    session.close()


@pytest.fixture(scope="session")
def service(env_cfg):
    return os.getenv("WINDFIRE_TEST_SERVICE", "").strip() or env_cfg["service"]


@pytest.fixture(scope="session")
def credentials(service):
    username = os.getenv("WINDFIRE_TEST_USERNAME", "").strip()
    password = os.getenv("WINDFIRE_TEST_PASSWORD", "")
    if not username or not password:
        pytest.skip("no credentials: export WINDFIRE_TEST_USERNAME and WINDFIRE_TEST_PASSWORD "
                    "(and optionally WINDFIRE_TEST_SERVICE), or run ./run-test-suite.sh, which asks for them")
    return {"username": username, "password": password, "service": service}


@pytest.fixture(scope="session")
def auth_response(http, base_url, credentials):
    """One login per session, reused by every test that needs a token"""
    response = http.post(f"{base_url}/v1/security/auth", json=credentials, timeout=15)
    if response.status_code != 200:
        pytest.fail(f"login of '{credentials['username']}' for '{credentials['service']}' failed: "
                    f"{response.status_code} {response.text}. Check the credentials, then the Keycloak tests.")
    return response.json()


@pytest.fixture(scope="session")
def token(auth_response):
    return auth_response["access_token"]
