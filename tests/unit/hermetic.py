"""
Test values and hermetic environment for the offline tier, applied on import (see conftest.py)
"""
import json
import os
import sys
import tempfile
from pathlib import Path

import dotenv

SERVER_DIR = Path(__file__).resolve().parents[2] / "server"

KEYCLOAK_URL = "https://kc.test"
REALM = "windfire"
SERVICE = "windfire-calendar-srv"
CLIENT_ID = "windfire-calendar"
CLIENT_SECRET = "unit-test-client-secret"
OTHER_SERVICE = "windfire-other-srv"
API_PORT = 18000
API_PORT_SECURE = 18444

_TMP_DIR = Path(tempfile.mkdtemp(prefix="windfire-security-unit-"))
SERVICE_CONFIG = {
    "services": {
        SERVICE: {"realm": REALM, "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET},
        OTHER_SERVICE: {"realm": "other", "client_id": "other-client", "client_secret": "other-secret"},
    }
}
(_TMP_DIR / "service_config.json").write_text(json.dumps(SERVICE_CONFIG))

TEST_ENV = {
    "APP_NAME": "Windfire Security Test",
    "API_HOST": "127.0.0.1",
    "API_PORT": str(API_PORT),
    "API_PORT_SECURE": str(API_PORT_SECURE),
    "SSL_KEYFILE": str(_TMP_DIR / "missing.key"),
    "SSL_CERTFILE": str(_TMP_DIR / "missing.crt"),
    "ENFORCE_HTTPS": "true",
    "ALLOWED_HOSTS": "localhost,testserver",
    "KEYCLOAK_SERVER_URL": KEYCLOAK_URL,
    "KEYCLOAK_VERIFY_SSL_CERTS": "false",
    "KEYCLOAK_CA_CERT_PATH": "",
    "SERVICE_CONFIG_FILE": str(_TMP_DIR / "service_config.json"),
    "DEFAULT_LOG_FILE": str(_TMP_DIR / "windfire-security-server.log"),
    "LOG_LEVEL": "WARNING",
}
os.environ.update(TEST_ENV)
dotenv.load_dotenv = lambda *args, **kwargs: False

if str(SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(SERVER_DIR))

