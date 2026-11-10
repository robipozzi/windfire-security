# Windfire Security — one-shot test suite

## Context

After a code change, a new function or a merged PR (dependabot or other), there is no fast way to know whether windfire-security still works:

- `test/` holds two manual scripts. `testServer.py` and `testClient.py` need two terminals and interactive prompts. They only print colored text: nothing fails and the exit code is never non-zero.
- CI ([.github/workflows/ci.yml](../.github/workflows/ci.yml)) runs only `compileall` and `pip-audit`. A PyJWT, cryptography or FastAPI bump that changes behavior passes CI.
- Environment names don't match. The scripts use `dev|staging|prod`. The client lib maps only `dev` (localhost:8443) and `prod` (raspberry01:8444). `testClient.py` hardcodes localhost:8444 for dev and staging.
- `keycloak/test/testKeycloak.sh` is interactive curl only.
- To run the manual tests, you first have to start the auth server by hand.

The goal is one command, `./run-test-suite.sh`, that runs:
1. an **offline tier**: pytest with mocked Keycloak. No network. It also runs in CI on every PR.
2. a **live tier**: end-to-end tests against the chosen environment (dev, test or prod). Read-only. For dev, the runner starts the auth server itself in the background.

The environment comes from `-e`. If it's missing, the runner asks for it. The suite exits 0 only if everything passes.

Decisions taken:
- The `test` environment isn't defined yet. Host and port per environment go in a config file, and `test` stays a placeholder. Live tests skip it with a clear message until it's filled in.
- Credentials come from env vars `WINDFIRE_TEST_USERNAME` / `WINDFIRE_TEST_PASSWORD` / `WINDFIRE_TEST_SERVICE`. If any is missing, the runner prompts once using `getCredentials` from `common.sh`.
- The offline tier is added to GitHub Actions.
- Scope: the auth server plus live Keycloak checks. sops, SSL name-constraint and Ansible checks are out of scope for now.
- The runner starts and stops the local auth server for dev. It does not start Keycloak.

## Layout (new `tests/` dir, existing `test/` manual scripts kept)

```
run-test-suite.sh                 # one-shot entry point (repo root)
tests/
  requirements.txt                # -r ../server/requirements.txt, -r ../test/requirements.txt, pytest, httpx
  pytest.ini                      # markers: unit, live, client, flow; testpaths
  environments.json               # dev/test/prod targets (no secrets)
  conftest.py                     # --env option, env config + credential fixtures
  unit/
    conftest.py                   # hermetic env + import of server modules
    test_settings.py
    test_service_config_reader.py
    test_keycloak_auth.py         # JWT verification + JWKS cache with local RSA keys
    test_api.py                   # FastAPI TestClient: routes, middleware, CORS, errors
    test_shell_scripts.py         # bash -n (+ shellcheck if installed) on every *.sh
    test_server_main.py           # authServer.main() port selection (--port vs .env)
  live/
    test_keycloak.py              # OIDC discovery, issuer, JWKS, Keycloak cert expiry
    test_health_tls.py
    test_auth_endpoint.py
    test_verify_endpoint.py
    test_client_library.py        # windfire-security-client against live server
    test_protected_flow.py        # spawns test/testServer.py, full downstream flow
  reports/                        # junit xml + server logs (gitignored)
```

### `tests/environments.json`
```json
{
  "dev":  {"host": "localhost",   "port": 8444, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt",
           "keycloak_url": "https://localhost:8443",   "keycloak_ca": "~/opt/keycloak/ssl/truststore/WindfireKeycloakRootCA.crt",
           "realm": "windfire", "service": "windfire-calendar-srv"},
  "test": {"host": null,          "port": null, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt",
           "keycloak_url": null,                       "keycloak_ca": "~/opt/keycloak/ssl/truststore/WindfireKeycloakRootCA.crt",
           "realm": "windfire", "service": "windfire-calendar-srv"},
  "prod": {"host": "raspberry01", "port": 8444, "root_ca": "~/opt/windfire/ssl/truststore/WindfireRootCA.crt",
           "keycloak_url": "https://raspberry01:8443", "keycloak_ca": "~/opt/keycloak/ssl/truststore/WindfireKeycloakRootCA.crt",
           "realm": "windfire", "service": "windfire-calendar-srv"}
}
```
dev uses 8444 to match the local `server/.env` (`API_PORT_SECURE=8444`) and `testClient.py`. `WINDFIRE_SECURITY_HOST` / `WINDFIRE_SECURITY_PORT` override these values. They are the same variables the client lib honors, so no change to the client repo is needed. Check the dev `keycloak_url` against `KEYCLOAK_SERVER_URL` in the local `server/.env` while implementing.

## Offline tier (`tests/unit`, marker `unit`)

**Hermetic import** (`unit/conftest.py`): the server modules have side effects when imported:
- `settings` calls `load_dotenv()`, which finds the real `server/.env`;
- `serviceConfig` loads `service_config.json` and raises if the file is missing;
- the logger writes to `logs/`.

`load_dotenv` only skips variables that are already set. Any key not set explicitly would still come from your `.env`. Results would then differ between your machine and CI, which has no `.env`. So, before adding `server/` to `sys.path`, `unit/conftest.py`:
- replaces `dotenv.load_dotenv` with a no-op;
- sets **every** key the server reads:
  - `APP_NAME`, `ENFORCE_HTTPS=true`, `ALLOWED_HOSTS=localhost,testserver`;
  - `API_HOST`, `API_PORT`, `API_PORT_SECURE`, `SSL_KEYFILE`, `SSL_CERTFILE`;
  - `KEYCLOAK_SERVER_URL=https://kc.test`, `KEYCLOAK_VERIFY_SSL_CERTS=false`, `KEYCLOAK_CA_CERT_PATH`;
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
  - plain HTTP gets a 307 to https, except on `/health`-suffixed paths;
  - HSTS, nosniff, X-Frame-Options and X-XSS headers are present. Check them on a non-health path, such as `/docs` or `/v1/security/verify`, because the health exemption also skips the headers;
  - `Host: evil.com` returns 400 (TrustedHost);
  - `/` redirects to `/docs`;
  - `/v2/...` returns 404.
- CORS: `allow_origins` is set to `ALLOWED_HOSTS`, a list of bare host names, so it never matches a real `Origin` such as `https://localhost:9443`. The test pins down the intended behavior. If CORS is meant to work, this is bug #4 (see below).

**test_shell_scripts.py**: runs `bash -n` on every `*.sh`, so a broken script is caught too. It also runs `shellcheck -S error` when shellcheck is installed, and skips that part when it isn't.

**test_server_main.py**: monkeypatch `uvicorn.run` and check the port `authServer.main()` passes to it:
- `main()` uses `API_PORT` for HTTP and `API_PORT_SECURE` for HTTPS (SSL files pointing to tmp files);
- `main(port_override=9100)` uses 9100 in both modes.

### Bugs the offline tier will surface (fixed in this branch, each with its test)
1. [server/middlewares.py](middlewares.py) exempts only `path == "/health"`, but the real endpoint is `/v1/monitor/health`. CLAUDE.md says paths ending in `/health` should be exempt. Fix: `request.url.path.endswith("/health")`.
2. [server/config/settings.py](config/settings.py) uses `key in 'API_PORT' or key in 'API_PORT_SECURE'`. That's a substring match, so `get('PORT')` or `get('API')` gets coerced to int. Fix: `key in ('API_PORT', 'API_PORT_SECURE')`.
3. In [server/routers/authRouters.py](routers/authRouters.py), `/auth` for an unknown service raises `ServiceConfigError`. It falls into the generic handler and answers 500. Fix: catch it next to `KeycloakAuthError` and answer 401, matching `/verify`.
4. (To confirm) In [server/authServer.py](authServer.py), CORS `allow_origins` gets bare host names. If browser clients such as windfire-ui-react call the server directly, build origins as `https://<host>[:port]`, or add an `ALLOWED_ORIGINS` key. Ask before changing it.

## Live tier (`tests/live`, marker `live`, `--env dev|test|prod`)

Fixtures in `tests/conftest.py`:
- `env_cfg`: loads `environments.json[--env]`, applies the host/port overrides, and expands `~`. If `host` is null, every live test is **skipped** with "environment 'test' not configured in tests/environments.json".
- `base_url` = `https://{host}:{port}`. All requests use `verify=<Windfire Root CA>`, never `verify=False`.
- `credentials`: read from the env vars. If they're missing, the live tier is skipped with a message telling you how to set them. The runner prompts before pytest starts.
- `token` (session scope): authenticates once and is reused, to keep Keycloak logins to a minimum.

Tests (all read-only, safe for prod):
- **test_keycloak.py**: runs first, so a Keycloak problem is reported as such and not as a 401 on every auth test.
  - `GET {keycloak_url}/realms/{realm}/.well-known/openid-configuration` returns 200, verified against `keycloak_ca` (the Windfire **Keycloak** Root CA, not the Windfire Root CA);
  - its `issuer` equals `{keycloak_url}/realms/{realm}`. This is the value the server's issuer check expects, so a hostname mismatch is caught here;
  - its `jwks_uri` returns at least one RS256 key;
  - the Keycloak certificate expires more than 14 days from now.
  - This supersedes `keycloak/test/testKeycloak.sh`.
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
  - The fixture starts `test/testServer.py` as a subprocess on a free port. It passes the same env plus `PORT` and `VERIFY_SSL_CERTS`; `testServer.py` crashes without them. It then polls `http://` (not https) `/health`, because `testServer.py` runs plain uvicorn.
  - `POST /test` with the token returns 200;
  - without a token it returns 401 or 403;
  - with a bad token it returns 401;
  - the fixture tears the subprocess down.

## Runner: `run-test-suite.sh` (repo root)

```
./run-test-suite.sh [-e dev|test|prod] [-s unit|live|all] [-k <pytest expr>] [-n] [-K] [-y] [-v] [-h]
```

| Option | Meaning |
|---|---|
| `-e` | environment. If missing and the live tier runs, the runner asks for it |
| `-s` | tier, default `all` |
| `-k` | pytest `-k` expression |
| `-n` | never start the local auth server; fail if none is running |
| `-K` | keep the auth server the runner started running after the tests |
| `-y` | skip the prod confirmation |
| `-v` | verbose pytest output |
| `-h` | help |

**Environment selection**
- If `-e` is missing, the runner calls `selectEnvironment` from `common.sh` (menu 1 Development / 2 Test / 3 Production) and sets `ENVIRONMENT` from the answer. So `./run-test-suite.sh` with no options asks for the environment and then runs everything.
- An invalid `-e` value prints the valid options and exits 1. It does not prompt.
- With `-s unit`, no environment is needed, so the runner doesn't ask.
- Credentials: if the `WINDFIRE_TEST_*` env vars are missing, `getCredentials` asks for them. It asks only when the live tier will run and the environment is configured: not for `-s unit`, and not for `-e test` while its host is `null`.

**Setup**
- Sources `common.sh` and reuses its colors, `selectEnvironment`, `getCredentials` and `getEnvFileValue`.
- Uses a venv `tests/windfire-security-suite` (add `PYTHON_SUITE_VIRTUAL_ENV` to `common.sh`). It is created on first run. Dependencies are reinstalled when `tests/requirements.txt`, `server/requirements.txt` or `test/requirements.txt` change (hash stamp file), so a merged dependabot bump is really what gets tested. It also does the editable install of `$HOME/dev/windfire-security-client` when that repo is present.
- `prod`: prints a red banner, "read-only tests against raspberry01:8444", and asks for confirmation unless `-y` is given.

**Auth server lifecycle (live tier)**

For `dev` (the target is `localhost`), you don't need to start the server first:
1. **Pre-check:** `GET https://localhost:<port>/v1/monitor/health`, verified with the Windfire Root CA. If a server already answers, the runner reuses it and leaves it running afterwards.
2. **Otherwise it starts the server in the background**, from `server/`, with the suite venv: `"$SUITE_VENV/bin/python" authServer.py --port <port> > tests/reports/server-dev-<ts>.log 2>&1 &`. It saves `$!`. It does not use `start-auth-server.sh` / `run-auth-server-background.sh`, because their venv installs dependencies only when it's created, so a dependabot bump would never be tested.
3. **Port:** read `API_PORT_SECURE` from `server/.env` with `getEnvFileValue`. If it differs from `environments.json` `dev.port`, warn, and export `WINDFIRE_SECURITY_PORT` so the tests use the port the server really listens on.
4. **Wait for ready:** poll health every second for up to 30 s. If the process exits or doesn't come up in time, print the last 30 lines of the server log and fail the live tier. The offline result is still reported.
5. **Stop on exit:** a `trap ... EXIT INT TERM` kills **only the PID the runner started**: first TERM, then KILL after 10 s. It never runs `stop-auth-server.sh`, whose `pgrep -f authServer.py` would also kill a server you started yourself. With `-K`, the runner leaves the server running and prints its PID and log path.
6. The runner doesn't start local **Keycloak**. If it's down, `test_keycloak.py` fails first, with "start Keycloak with keycloak/start-keycloak.sh".

For `prod` and `test`, the runner never starts anything, because prod runs as the `windfire-security` systemd unit on raspberry01. It runs the same health pre-check. If that fails, the live tier fails with "server not reachable at host:port". `test` is skipped anyway while its host is `null`.

**Execution and exit code**
- `-s all`: the offline tier runs first, then the live tier, as **two separate pytest runs**. If the offline tier fails, the live tier still runs.
- Each run: `pytest --env $ENV -m <markers> --junitxml=tests/reports/<env>-<tier>-<timestamp>.xml`.
- At the end the runner prints a colored PASS/FAIL summary per tier. It exits 0 only if every tier that ran passed. Otherwise it exits with the first non-zero pytest code.

## Consistency changes

- Rename `staging` to `test` everywhere:
  - `common.sh` `setEnvironment` (option 2);
  - `validate_environment` in `test/run-test-client.sh` and `test/start-test-server.sh`;
  - `test/testClient.py`. The manual client also reads the target from `tests/environments.json`, which replaces its hardcoded URL.
- `.gitignore`: add `tests/windfire-security-suite/`, `tests/reports/` and `tests/**/__pycache__/`.
- `.github/dependabot.yml`: add a pip entry for `/tests`.
- `.github/workflows/ci.yml`: new job `unit-tests` on Python 3.11.2. It runs `pip install -r tests/requirements.txt` then `pytest tests/unit -m unit`. Add `tests` to the pip-audit matrix.
- Docs: replace the "There's no automated test suite" section in CLAUDE.md, and the README testing section, with how to use the suite. Say that the client and flow tests are live only and don't run in CI, because the sibling client repo isn't checked out there.
- Delete this plan file in the docs commit, as done with earlier plans (`397ebf6`).

## Files

New: `run-test-suite.sh`, `tests/**`.
Modified: `common.sh`, `server/middlewares.py`, `server/config/settings.py`, `server/routers/authRouters.py`, `test/testClient.py`, `test/run-test-client.sh`, `test/start-test-server.sh`, `.gitignore`, `.github/workflows/ci.yml`, `.github/dependabot.yml`, `CLAUDE.md`, `README.md`. `server/authServer.py` only if bug #4 is confirmed.
Reused: `common.sh` (`selectEnvironment`, `getCredentials`, `getEnvFileValue`, colors, `WINDFIRE_DEFAULT_TRUSTSTORE_DIR`, `KEYCLOAK_DEFAULT_TRUSTSTORE_DIR`), `test/testServer.py`, `client.authClient`, and the `SERVICE_CONFIG_FILE` / `DEFAULT_LOG_FILE` env hooks in the server.

Work on the current branch `test/test-suite`. Use separate commits: suite scaffold, offline tests, bug fixes, live tests, runner, CI and docs.

## Verification

1. `./run-test-suite.sh -s unit` passes locally with no network. To confirm the tests have teeth, temporarily drop `audience=` in `verify_token_locally`: the audience tests must fail.
2. The offline tier still passes with `server/.env` temporarily renamed, which proves the import is hermetic.
3. Bug-fix tests fail before each fix and pass after it.
4. `./run-test-suite.sh` with no options shows the environment menu. Choosing 1 runs everything against dev.
5. With local Keycloak running and **no** auth server running, `./run-test-suite.sh -e dev` starts the server, and everything passes, including the Keycloak, client and flow tests. Afterwards `pgrep -f authServer.py` is empty.
6. With an auth server already running, `-e dev` reuses it and leaves it running.
7. `-e dev -K` leaves the server it started running. `-e dev -n` with no server running fails with a clear message. Ctrl-C during the live tier still stops the server the runner started.
8. With local Keycloak stopped, `-e dev` fails in `test_keycloak.py` with the "start Keycloak" message.
9. `./run-test-suite.sh -e test`: the live tests are skipped with the "not configured" message, there is no credentials prompt, and the exit code is 0.
10. `./run-test-suite.sh -e prod -y`: passes against raspberry01:8444, and nothing is started. Check the Keycloak admin console: no lockout on the real user.
11. Push the branch and open the PR: the CI `unit-tests` job is green. A deliberate failing test makes it go red.
