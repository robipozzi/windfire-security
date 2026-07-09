# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Windfire Security provides the authentication/authorization infrastructure for the Windfire application suite. It has three parts:

1. **`server/`** — a Python FastAPI "Windfire Security Authentication Service" that fronts Keycloak. Other Windfire services never talk to Keycloak directly; they call this service's `/v1/security/auth` and `/v1/security/verify` endpoints.
2. **`keycloak/`** — shell scripts to run Keycloak itself (localhost, Docker, or Raspberry Pi) and to configure TLS on the Keycloak server.
3. **`ssl/`** — shell scripts to generate the Windfire self-signed Root CA and per-host server certificates used across the whole suite (not just this service).

A companion sibling repo, `../windfire-security-client` (`$HOME/dev/windfire-security-client`), provides the `client.authClient` Python module that other services (and this repo's own `test/` scripts) use to call the auth server. It's installed into test/consumer virtualenvs via `pip3 install -e $HOME/dev/windfire-security-client`. If `client.authClient` imports are failing, check that sibling repo is present and installed, not this one.

## Running the authentication server

```bash
cd server
./start-auth-server.sh              # creates/activates venv, installs deps, runs on port 8000 (HTTP) or 8443 (HTTPS)
./start-auth-server.sh -p 9000       # custom port
./start-auth-server.sh -v            # verbose/DEBUG logging
./run-auth-server-background.sh      # same, but backgrounded, logs to logs/windfire-security-server.log
./stop-auth-server.sh                # kills the authServer.py process
```

First-time setup requires copying two placeholder files (both gitignored, never commit real values):
- `server/.env_PLACEHOLDER` → `server/.env` — sets `APP_NAME`, `API_HOST`, `API_PORT`/`API_PORT_SECURE`, `SSL_KEYFILE`/`SSL_CERTFILE`, `ENFORCE_HTTPS`, `ALLOWED_HOSTS`, `KEYCLOAK_SERVER_URL`.
- `server/config/service_config.json_PLACEHOLDER` → `server/config/service_config.json` — per-service Keycloak `realm`/`client_id`/`client_secret` map, keyed by service name (e.g. `windfire-calendar-srv`). This is how one auth server backs multiple Windfire client services.

`server/createPythonVenv.sh` / `activatePythonVenv.sh` / `deactivatePythonVenv.sh` manage a venv named `windfire-security-server` (see `PYTHON_SERVER_VIRTUAL_ENV` in `common.sh`); `server/installPrereqs.sh` pins the FastAPI/uvicorn/PyJWT/cryptography versions.

## Running tests

There's no automated test suite (no pytest) — `test/` contains manual/interactive integration scripts that exercise a running auth server end-to-end:

```bash
cd test
./start-test-server.sh -e dev       # runs testServer.py, a dummy service with one endpoint protected by the auth server
./run-test-client.sh -e dev         # runs testClient.py: hits health endpoints, authenticates via Keycloak, calls the protected endpoint
```

Both prompt interactively for username/password/service (`common.sh`'s `getCredentials`), defaulting service to `windfire-calendar-srv`. `-e {dev|staging|prod}` selects which auth server to target (`prod` points at `raspberry01:8443`, others at `localhost:8443`). Uses a separate `windfire-security-test` venv; `test/installPrereqs.sh` additionally does the editable install of the sibling `windfire-security-client` repo.

## Certificate / TLS setup

`ssl/createRootCA.sh` generates the Windfire self-signed Root CA (`WindfireRootCA.key`/`.crt`) and copies it into `~/opt/windfire/ssl/{keystore,truststore}`. `ssl/generateServerCert.sh` issues per-host server certs off that CA (uses `openssl_config_localhost.ext` / `openssl_config_raspberry.ext` as the SAN config depending on target). These certs are what `SSL_KEYFILE`/`SSL_CERTFILE` in `server/.env` point at, and what `ROOT_CA_PATH` in the test scripts verifies against.

Keycloak's own TLS is set up separately via `keycloak/security/setupTLS.sh` (generates a Java keystore) + `keycloak/setupKeycloakMode.sh` (enables/disables TLS on the Keycloak server) — this is independent of the Windfire Root CA above.

## Architecture of `server/`

Entry point is `authServer.py`: builds the FastAPI `app`, wires CORS/TrustedHost/GZip middleware, registers the custom `https_enforcement_middleware` (from `middlewares.py`) that redirects HTTP→HTTPS except for `/health`-suffixed paths and adds HSTS/security headers, and mounts `apiRouter.api`. `main()` reads `ENFORCE_HTTPS`/SSL paths from `settings` and decides whether `uvicorn.run` gets `ssl_keyfile`/`ssl_certfile`.

Routing is nested under a version prefix: `apiRouter.py` defines `api = APIRouter(prefix="/v1")` and includes `routers/healthRouters.py` (`/v1/monitor/health`) and `routers/authRouters.py` (`/v1/security/auth`, `/v1/security/verify`). A `v2` router is declared but unused — don't assume `/v2` endpoints exist.

Auth logic lives in `keycloakAuth.py`, independent of FastAPI:
- `KeycloakConfig` resolves per-service Keycloak realm/client credentials by looking up `service_config.json` via `config/service_config_reader.py` (`ServiceConfigReader`/`serviceConfig` singleton).
- `KeycloakAuth` wraps the Keycloak token/userinfo/introspect/JWKS endpoints (password grant, client-credentials grant, refresh, introspection, local JWT verification against JWKS).
- Module-level convenience functions `authenticate_user()`, `authenticate_service_account()`, `verify_token()` are what the routers call — prefer these over instantiating `KeycloakAuth` directly.
- `verify_token(..., method='local')` (the default, used by `/v1/security/verify`) validates the JWT signature locally against Keycloak's JWKS — no special Keycloak client permissions needed. `method='introspect'` calls Keycloak's introspection endpoint instead and requires the client to have service-account introspection rights.

Config loading: `config/settings.py` (`Settings`/`settings` singleton) reads `.env` via `python-dotenv`, with type coercion baked in for `ENFORCE_HTTPS` (→ bool) and `API_PORT`/`API_PORT_SECURE` (→ int) — other keys return raw strings. `config/service_config_reader.py` is the multi-tenant service registry described above.

Logging: every module gets its logger via `logger.loggerFactory.logger_factory.get_logger(<module_name>)` (never `logging.getLogger` directly) — this ensures consistent formatting (`ColorFormatter`) and routes to both a `TimedRotatingFileHandler` (`server/logs/windfire-security-server.log`, midnight rotation, 7 backups) and stdout. Level is controlled by the `LOG_LEVEL` env var (defaults to `DEBUG`).

Errors surface as `KeycloakAuthError` from `keycloakAuth.py`; routers translate them to HTTP 401 (bad credentials/invalid token) or 500 (unexpected).
