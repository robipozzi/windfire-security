"""
Shared configuration of the Windfire Security test suite.

- `--env dev|test|prod` selects the target of the live tier (tests/environments.json).
- Tests under unit/ get the `unit` marker, tests under live/ the `live` marker.
- Live fixtures: env_cfg, base_url, http (a requests session that trusts the Windfire Root CA),
  credentials (WINDFIRE_TEST_USERNAME / WINDFIRE_TEST_PASSWORD / WINDFIRE_TEST_SERVICE), auth_response and token.
"""
import json
import os
import socket
import ssl
import time
from pathlib import Path
from urllib.parse import urlparse

import pytest

TESTS_DIR = Path(__file__).resolve().parent
REPO_DIR = TESTS_DIR.parent
SERVER_DIR = REPO_DIR / "server"
ENVIRONMENTS_FILE = TESTS_DIR / "environments.json"
REPORTS_DIR = TESTS_DIR / "reports"

# Username that never exists in Keycloak: wrong-password tests use it, so brute-force protection never locks a real user
NONEXISTENT_USERNAME = "suite-nonexistent-user"
UNKNOWN_SERVICE = "suite-unknown-service"
INVALID_TOKEN_DETAIL = "Invalid or expired token"
INVALID_CREDENTIALS_DETAIL = "Invalid username or password"
SECURITY_HEADERS = {
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
    "x-xss-protection": "1; mode=block",
}
CERT_MIN_DAYS_LEFT = 14


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
def _env_file_value(key):
    """Read one key from server/.env (python-dotenv parses inline comments and quotes)"""
    env_file = SERVER_DIR / ".env"
    if not env_file.is_file():
        return None
    from dotenv import dotenv_values
    return dotenv_values(env_file).get(key)


def load_env_cfg(name):
    """Target of environment `name`, with the env var overrides applied and `~` expanded"""
    with open(ENVIRONMENTS_FILE) as f:
        environments = json.load(f)
    cfg = dict(environments[name])
    cfg["name"] = name
    if os.getenv("WINDFIRE_SECURITY_HOST", "").strip():
        cfg["host"] = os.environ["WINDFIRE_SECURITY_HOST"].strip()
    if os.getenv("WINDFIRE_SECURITY_PORT", "").strip():
        cfg["port"] = int(os.environ["WINDFIRE_SECURITY_PORT"].strip())
    if os.getenv("WINDFIRE_TEST_KEYCLOAK_URL", "").strip():
        cfg["keycloak_url"] = os.environ["WINDFIRE_TEST_KEYCLOAK_URL"].strip()
    elif cfg.get("keycloak_url") is None and cfg.get("host"):
        cfg["keycloak_url"] = _env_file_value("KEYCLOAK_SERVER_URL")
    if cfg.get("keycloak_url"):
        cfg["keycloak_url"] = cfg["keycloak_url"].rstrip("/")
    for key in ("root_ca", "keycloak_ca"):
        if cfg.get(key):
            cfg[key] = os.path.expanduser(cfg[key])
    return cfg


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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def cert_days_left(host, port, cafile):
    """Days before the server certificate expires; the handshake verifies the chain and the hostname"""
    context = ssl.create_default_context(cafile=cafile)
    with socket.create_connection((host, port), timeout=10) as sock:
        with context.wrap_socket(sock, server_hostname=host) as tls:
            not_after = tls.getpeercert()["notAfter"]
    return (ssl.cert_time_to_seconds(not_after) - time.time()) / 86400


def url_host_port(url):
    parsed = urlparse(url)
    return parsed.hostname, parsed.port or 443


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]
