"""
Hermetic import of the server modules for the offline tier.

Importing the server has side effects: config.settings calls load_dotenv() (which would read the real
server/.env), config.service_config_reader loads service_config.json, and the logger opens a log file.
Before server/ goes on sys.path, this module:
- turns dotenv.load_dotenv into a no-op, so nothing comes from server/.env, on a laptop or in CI;
- sets every environment key the server reads to a test value;
- points SERVICE_CONFIG_FILE and DEFAULT_LOG_FILE to a temporary folder.
No secrets and no network are needed.
"""
import shutil

import pytest

# Must run before any server module is imported
from hermetic import TEST_ENV, _TMP_DIR  # noqa: E402


@pytest.fixture(autouse=True)
def _restore_test_env(monkeypatch):
    """Each test starts from TEST_ENV, whatever the previous one changed"""
    for key, value in TEST_ENV.items():
        monkeypatch.setenv(key, value)


@pytest.fixture(autouse=True)
def _reset_login_rate_limits():
    """Each test starts with empty /v1/security/auth rate limits (per-IP and per-username)"""
    from rateLimit import failure_tracker, limiter  # imported here so hermetic runs first
    limiter.reset()
    failure_tracker.reset_all()
    yield


def pytest_sessionfinish(session, exitstatus):
    shutil.rmtree(_TMP_DIR, ignore_errors=True)
