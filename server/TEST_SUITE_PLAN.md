# Windfire Security — one-shot test suite

## Context

After a code change, a new function or a merged PR (dependabot or other), there is no fast way to know whether windfire-security still works:

- `test/` holds two manual scripts. `testServer.py` and `testClient.py` need two terminals and interactive prompts. They only print colored text: nothing fails and the exit code is never non-zero.
- CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs only `compileall` and `pip-audit`. A PyJWT, cryptography or FastAPI bump that changes behavior passes CI.
- Environment names don't match. The scripts use `dev|staging|prod`. The client lib maps only `dev` (localhost:8443) and `prod` (raspberry01:8444). `testClient.py` hardcodes localhost:8444 for dev and staging.
- `keycloak/test/testKeycloak.sh` is interactive curl only.

The goal is one command, `./run-test-suite.sh -e dev|test|prod`, that runs:
1. an **offline tier**: pytest with mocked Keycloak. No network. It also runs in CI on every PR.
2. a **live tier**: end-to-end tests against the chosen environment. Read-only.

It exits 0 only if everything passes.

Decisions taken:
- The `test` environment isn't defined yet. Host and port per environment go in a config file, and `test` stays a placeholder. Live tests skip it with a clear message until it's filled in.
- Credentials come from env vars `WINDFIRE_TEST_USERNAME` / `WINDFIRE_TEST_PASSWORD` / `WINDFIRE_TEST_SERVICE`. If any is missing, the runner prompts once using `getCredentials` from `common.sh`.
- The offline tier is added to GitHub Actions.

## Layout (new `tests/` dir, existing `test/` manual scripts kept)

```
run-test-suite.sh                 # one-shot entry point (repo root)
tests/
  requirements.txt                # -r ../server/requirements.txt + pytest, httpx
  pytest.ini                      # markers: unit, live, client, flow; testpaths
  environments.json               # dev/test/prod targets (no secrets)
  conftest.py                     # --env option, env config + credential fixtures
  unit/
    conftest.py                   # hermetic env + import of server modules
    test_settings.py
    test_service_config_reader.py
    test_keycloak_auth.py         # JWT verification + JWKS cache with local RSA keys
    test_api.py                   # FastAPI TestClient: routes, middleware, errors
  live/
    test_health_tls.py
    test_auth_endpoint.py
    test_verify_endpoint.py
    test_client_library.py        # windfire-security-client against live server
    test_protected_flow.py        # spawns test/testServer.py, full downstream flow
  reports/                        # junit xml (gitignored)
```

### `tests/environments.json`
```json
{
  "dev":  {"host": "localhost",   "port": 8444, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt", "service": "windfire-calendar-srv"},
  "test": {"host": null,          "port": null, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt", "service": "windfire-calendar-srv"},
  "prod": {"host": "raspberry01", "port": 8444, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt", "service": "windfire-calendar-srv"}
}
```
dev uses 8444 to match the local `server/.env` (`API_PORT_SECURE=8444`) and `testClient.py`. `WINDFIRE_SECURITY_HOST` / `WINDFIRE_SECURITY_PORT` override these values. They are the same variables the client lib honors, so no change to the client repo is needed.

## Offline tier (`tests/unit`, marker `unit`)

**Hermetic import** (`unit/conftest.py`): the server modules have side effects when imported:
- `settings` calls `load_dotenv()`, which would read the real `server/.env`;
- `serviceConfig` loads `service_config.json` and raises if the file is missing;
- the logger writes to `logs/`.

So before adding `server/` to `sys.path`, `unit/conftest.py` sets every env var explicitly. `load_dotenv` doesn't override variables that are already set. The variables are:
- `APP_NAME`, `ENFORCE_HTTPS=true`, `ALLOWED_HOSTS=localhost,testserver`;
- `KEYCLOAK_SERVER_URL=https://kc.test`, `KEYCLOAK_VERIFY_SSL_CERTS=false`;
- `SERVICE_CONFIG_FILE` pointing to a tmp JSON with a fake `windfire-calendar-srv`;
- `DEFAULT_LOG_FILE` pointing to a tmp path, and `LOG_LEVEL=WARNING`.

No real secrets or network are needed.

**test_settings.py**:
- bool coercion of `ENFORCE_HTTPS` / `KEYCLOAK_VERIFY_SSL_CERTS`;
- int coercion of the ports;
- unknown keys return the raw string.

**test_service_config_reader.py**: covers `ServiceConfigReader`:
- a valid file;
- missing file, invalid JSON, no `services`, missing or empty `realm`/`client_id`;
- `get_service` of an unknown service;
- `repr` masks the secret.

**test_keycloak_auth.py**: the core regression net for PyJWT and cryptography bumps. Each test generates RSA keys with `cryptography`, serves a JWKS through a monkeypatched `requests.Session.get`, and mints tokens with PyJWT.
- `verify_token_locally` accepts a valid token and returns its claims.
- It rejects:
  - an expired token;
  - a wrong `aud` (the Audience-mapper case);
  - a wrong `iss`;
  - a token signed with another key;
  - a token with no `kid` or an unknown `kid`;
  - `alg=none` or HS256 confusion;
  - a token missing `exp`/`iat`.
- JWKS cache:
  - a second verify doesn't refetch;
  - an unknown kid refetches, but the refetch is throttled within 30s;
  - the TTL expires after 600s (monkeypatch `time.monotonic`).
- `authenticate_with_password`:
  - the payload carries `client_secret`;
  - it passes `verify=` with the expanded CA path;
  - a 401 from Keycloak raises `KeycloakAuthError`.
- `KeycloakConfig.verify` resolution: `~` expansion and `false`.

**test_api.py**: `fastapi.testclient.TestClient(authServer.app, base_url="https://localhost")`. The `authenticate_user` / `verify_token` names imported into `routers.authRouters` are monkeypatched.
- `GET /v1/monitor/health` returns 200 with `{"status":"healthy",...}`.
- `POST /v1/security/auth`:
  - success returns a token response in the `KeycloakTokenResponse` shape;
  - `KeycloakAuthError` returns 401 `"Invalid username or password"`;
  - an unexpected error returns 500;
  - a missing field returns 422.
- `POST /v1/security/verify`:
  - a valid token returns `{"status":"valid"}`;
  - an invalid token returns 401 with the fixed detail `"Invalid or expired token"`;
  - an unknown service returns 401, and the response body doesn't contain the list of configured services;
  - with no bearer it returns 401 or 403.
- Middleware:
  - plain HTTP gets a 307 to https;
  - HSTS, nosniff, X-Frame-Options and X-XSS headers are present;
  - `Host: evil.com` returns 400 (TrustedHost);
  - `/` redirects to `/docs`;
  - `/v2/...` returns 404.

**Shell sanity** (`unit/test_shell_scripts.py`): `bash -n` on every `*.sh`, so a broken script is caught too.

### Bugs the offline tier will surface (fixed in this branch, each with its test)
1. [server/middlewares.py](server/middlewares.py) exempts only `path == "/health"`, but the real endpoint is `/v1/monitor/health`. CLAUDE.md says paths ending in `/health` should be exempt. Fix: `request.url.path.endswith("/health")`.
2. [server/config/settings.py](server/config/settings.py) uses `key in 'API_PORT' or key in 'API_PORT_SECURE'`. That's a substring match, so `get('PORT')` or `get('API')` gets coerced to int. Fix: `key in ('API_PORT', 'API_PORT_SECURE')`.
3. In [server/routers/authRouters.py](server/routers/authRouters.py), `/auth` for an unknown service raises `ServiceConfigError`. It falls into the generic handler and answers 500. Fix: catch it next to `KeycloakAuthError` and answer 401, matching `/verify`.

## Live tier (`tests/live`, marker `live`, `--env dev|test|prod`)

Fixtures in `tests/conftest.py`:
- `env_cfg`: loads `environments.json[--env]`, applies the host/port overrides, and expands `~`. If `host` is null, every live test is **skipped** with "environment 'test' not configured in tests/environments.json".
- `base_url` = `https://{host}:{port}`. All requests use `verify=<Windfire Root CA>`, never `verify=False`.
- `credentials`: read from the env vars. If they're missing, the live tier is skipped with a message telling you how to set them. The runner prompts before pytest starts.
- `token` (session scope): authenticates once and is reused, to keep Keycloak logins to a minimum.

Tests (all read-only, safe for prod):
- **test_health_tls.py**:
  - TLS handshake succeeds against the Windfire Root CA, with hostname check;
  - the cert expires more than 14 days from now;
  - health returns 200 with the expected body;
  - an unknown `Host` header returns 400.
- **test_auth_endpoint.py**:
  - valid credentials return 200 with `token_type=Bearer`, `expires_in>0` and a JWT with 3 segments;
  - bad credentials return 401 with the fixed detail. This uses a **non-existent username** (`suite-nonexistent-user`), so Keycloak's brute-force protection never locks the real user;
  - an unknown service returns 401 and its body doesn't contain the list of configured services;
  - a missing field returns 422.
- **test_verify_endpoint.py**:
  - a valid token returns 200 `{"status":"valid"}`. This catches a wrong `KEYCLOAK_SERVER_URL` (issuer mismatch) or a missing Audience mapper;
  - a tampered signature returns 401;
  - a garbage token returns 401;
  - a valid token sent with a wrong service returns 401;
  - no Authorization header returns 401 or 403;
  - the security headers are present.
- **test_client_library.py** (marker `client`): skipped if `client.authClient` can't be imported.
  - The fixture sets `ENVIRONMENT`, `WINDFIRE_SECURITY_HOST/PORT`, `VERIFY_SSL_CERTS=true` and `ROOT_CA_PATH`, and creates `~/logs` (the client logger needs it). It then imports the client.
  - `authenticate()` returns a token;
  - `verify_or_raise()` returns True, and returns False for a garbage token;
  - with an unreachable port it raises `AuthServerError`.
- **test_protected_flow.py** (marker `flow`): automates today's two-terminal manual test.
  - The fixture starts `test/testServer.py` as a subprocess on a free port, with the same env, and waits for `/health`.
  - `POST /test` with the token returns 200;
  - without a token it returns 401 or 403;
  - with a bad token it returns 401;
  - the fixture tears the subprocess down.

## Runner: `run-test-suite.sh` (repo root)

```
./run-test-suite.sh [-e dev|test|prod] [-s unit|live|all] [-k <pytest expr>] [-v] [-h]
```
- Sources `common.sh` and reuses the colors, `selectEnvironment` (prompts if `-e` is missing) and `getCredentials`.
- Uses a venv `tests/windfire-security-suite` (add `PYTHON_SUITE_VIRTUAL_ENV` to `common.sh`). It is created on first run. Dependencies are reinstalled when `tests/requirements.txt` or `server/requirements.txt` change (hash stamp file), so a merged dependabot bump is really what gets tested. It also does the editable install of `$HOME/dev/windfire-security-client` when that repo is present.
- `-s` defaults to `all`. The offline tier runs first. If it fails, the live tier is still run, and the summary reports both.
- `prod`: prints a red banner, "read-only tests against raspberry01:8444", and asks for confirmation unless `-y` is given.
- Runs `pytest --env $ENV -m <markers> --junitxml=tests/reports/<env>-<timestamp>.xml` and then prints a colored PASS/FAIL summary per tier. The exit code is pytest's.

## Consistency changes

- Rename `staging` to `test` everywhere:
  - `common.sh` `setEnvironment` (option 2);
  - `validate_environment` in `test/run-test-client.sh` and `test/start-test-server.sh`;
  - `test/testClient.py`. The manual client also reads the target from `tests/environments.json`, which replaces its hardcoded URL.
- `.gitignore`: add `tests/windfire-security-suite/`, `tests/reports/` and `tests/**/__pycache__/`.
- `.github/dependabot.yml`: add a pip entry for `/tests`.
- `.github/workflows/ci.yml`: new job `unit-tests` on Python 3.11.2. It runs `pip install -r tests/requirements.txt` then `pytest tests/unit -m unit`. Add `tests` to the pip-audit matrix.
- Docs: replace the "There's no automated test suite" section in CLAUDE.md, and the README testing section, with how to use the suite.

## Files

New: `run-test-suite.sh`, `tests/**`.
Modified: `common.sh`, `server/middlewares.py`, `server/config/settings.py`, `server/routers/authRouters.py`, `test/testClient.py`, `test/run-test-client.sh`, `test/start-test-server.sh`, `.gitignore`, `.github/workflows/ci.yml`, `.github/dependabot.yml`, `CLAUDE.md`, `README.md`.
Reused: `common.sh` (`selectEnvironment`, `getCredentials`, colors, `WINDFIRE_DEFAULT_TRUSTSTORE_DIR`), `test/testServer.py`, `client.authClient`, and the `SERVICE_CONFIG_FILE` / `DEFAULT_LOG_FILE` env hooks in the server.

Work on the current branch `test/test-suite`. Use separate commits: suite scaffold, offline tests, bug fixes, live tests, runner, CI and docs.

## Verification

1. `./run-test-suite.sh -s unit` passes locally with no network. To confirm the tests have teeth, temporarily drop `audience=` in `verify_token_locally`: the audience tests must fail.
2. Bug-fix tests fail before each fix and pass after it.
3. Start the local server (`server/start-auth-server.sh`), then run `./run-test-suite.sh -e dev`: everything passes, including the client and flow tests.
4. `./run-test-suite.sh -e test`: the live tests are skipped with the "not configured" message, and the exit code is 0.
5. `./run-test-suite.sh -e prod -y`: passes against raspberry01:8444. Check the Keycloak admin console: no lockout on the real user.
6. Push the branch and open the PR: the CI `unit-tests` job is green. A deliberate failing test makes it go red.
