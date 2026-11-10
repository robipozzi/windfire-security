"""Constants and helpers shared by the conftest and the live tests (importable: pytest.ini sets pythonpath = .)"""
import json
import os
import socket
import ssl
import time
from pathlib import Path
from urllib.parse import urlparse

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
