# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Windfire Security provides the authentication/authorization infrastructure for the Windfire application suite. It has four parts:

1. **`server/`** — a Python FastAPI "Windfire Security Authentication Service" that fronts Keycloak. Other Windfire services never talk to Keycloak directly; they call this service's `/v1/security/auth` and `/v1/security/verify` endpoints.
2. **`keycloak/`** — shell scripts and Ansible playbooks to run Keycloak locally (localhost or Docker), to install, upgrade, back up and uninstall it (raspberry01 or localhost), and to configure TLS on the Keycloak server.
3. **`ssl/`** — shell scripts to generate the Windfire self-signed Root CA and per-host server certificates used across the whole suite (not just this service).
4. **`sops/`** — `sops-crypt.sh`, a utility to encrypt/decrypt files with sops + age. The default file mode encrypts any file in binary mode to `<file>.sops.json`, with a round-trip check. `-i` encrypts structured YAML/JSON/.env files in place. The age key file defaults to `~/.config/sops/age/keys.txt` via `DEFAULT_SOPS_AGE_KEY_FILE` in `common.sh`. It takes getopts flags (`-e/-d -i -k -f -o -r -y`), and the legacy `encrypt-sops.sh` positional form `1|2 <in> [out]` is still accepted. Used e.g. for the Windfire Keycloak Root CA private key.

A companion sibling repo, `../windfire-security-client` (`$HOME/dev/windfire-security-client`), provides the `client.authClient` Python module that other services (and this repo's own `test/` scripts) use to call the auth server. It's installed into test/consumer virtualenvs via `pip3 install -e $HOME/dev/windfire-security-client`. If `client.authClient` imports are failing, check that sibling repo is present and installed, not this one.

## Running the authentication server

```bash
cd server
./start-auth-server.sh              # creates/activates venv, installs deps, runs on API_PORT (HTTP) or API_PORT_SECURE (HTTPS) from .env
./start-auth-server.sh -p 9000       # custom port (passed as authServer.py --port, overrides the .env port)
./start-auth-server.sh -v            # verbose/DEBUG logging
./start-auth-server-background.sh    # same, but backgrounded; console output to logs/windfire-security.log, app log stays in logs/windfire-security-server.log
./stop-auth-server.sh                # stops the authServer.py process (refuses if the windfire-security systemd service runs it)
```

First-time setup requires copying two placeholder files (both gitignored, never commit real values):
- `server/.env_PLACEHOLDER` → `server/.env` — sets `APP_NAME`, `API_HOST`, `API_PORT`/`API_PORT_SECURE`, `SSL_KEYFILE`/`SSL_CERTFILE`, `ENFORCE_HTTPS`, `ALLOWED_HOSTS`, `ENABLE_API_DOCS` (`true` in the placeholder for local runs, `false` in the Raspberry `windfire-security.env.j2`), `KEYCLOAK_SERVER_URL`.
- `server/config/service_config.json_PLACEHOLDER` → `server/config/service_config.json` — per-service Keycloak `realm`/`client_id`/`client_secret` map, keyed by service name (e.g. `windfire-calendar-srv`). This is how one auth server backs multiple Windfire client services.

`server/createPythonVenv.sh` / `activatePythonVenv.sh` / `deactivatePythonVenv.sh` manage a venv named `windfire-security-server` (see `PYTHON_SERVER_VIRTUAL_ENV` in `common.sh`); `server/installPrereqs.sh` installs the FastAPI/uvicorn/PyJWT/cryptography versions pinned in `server/requirements.txt`.

## Deploying to Raspberry

`deployment/deploy.sh [1]` / `deployment/undeploy.sh [1] [-y]` run the playbooks in `deployment/raspberry/` against the `security_service` inventory group (raspberry01), mirroring windfire-calendar's deployment. The server runs there as the `windfire-security` systemd unit (`templates/windfire-security.service.j2`, `Restart=on-failure`, enabled at boot) on port 8444 (Keycloak owns 8443 on that host). The playbooks use `become: yes` and `become_ask_pass=True` because sudo on the Pis needs the `pi` password. The Pi's `server/.env` is templated from `templates/windfire-security.env.j2` (the local `.env` is never copied; `deploy.sh` only asks for `KEYCLOAK_SERVER_URL`). `service_config.json` holds the client secrets, so it is never copied in plaintext: the playbook encrypts the local file with `systemd-creds` into `/etc/credstore.encrypted/windfire-security-service-config`, the unit loads it with `LoadCredentialEncrypted`, and `ServiceConfigReader` reads it through the `SERVICE_CONFIG_FILE` env var (default `config/service_config.json` for local runs). The service's stdout/stderr go to `server/logs/windfire-security.log`, alongside the app's own rotating `windfire-security-server.log`. The unit is sandboxed: `ProtectSystem=strict` and `ProtectHome=read-only` make the filesystem read-only except `ReadWritePaths=` `server/logs`, and it runs with `NoNewPrivileges`, an empty `CapabilityBoundingSet` (port 8444 needs none), private `/tmp` and `/dev`, protected kernel tunables, modules, logs, cgroups and clock, `RestrictNamespaces`, `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`, native syscalls only and `UMask=0077`. `MemoryDenyWriteExecute` is deliberately left out because it breaks JIT runtimes and some Python wheels. If the app ever needs to write somewhere else, add that path to `ReadWritePaths=`.

## Running tests

`./run-test-suite.sh [-e dev|test|prod] [-s unit|live|all] [-k expr] [-n] [-K] [-y] [-v]` is the one-shot pytest suite in `tests/`. It exits 0 only if every tier passed. With no `-e`, it asks for the environment through `common.sh`'s `selectEnvironment`.
- **Offline tier** (`tests/unit`, marker `unit`, also the CI `unit-tests` job): Keycloak is mocked, with no network or secrets. `tests/unit/hermetic.py` sets every env key the server reads and turns `dotenv.load_dotenv` into a no-op *before* `server/` goes on `sys.path`, so the real `server/.env` never leaks in. Server modules are imported by their bare names (`import authServer`, `from keycloakAuth import ...`).
- **Live tier** (`tests/live`, marker `live`, `--env`): read-only. Targets are in `tests/environments.json` (`test` has `host: null`, so it is skipped). Overrides: `WINDFIRE_SECURITY_HOST/PORT`, and `WINDFIRE_TEST_KEYCLOAK_URL`. dev's `keycloak_url` is null, which means `KEYCLOAK_SERVER_URL` from `server/.env`. Credentials come from `WINDFIRE_TEST_USERNAME/PASSWORD/SERVICE`, and one login is reused per session. Wrong-password tests use a username that doesn't exist (brute-force protection). `test_keycloak.py` is sorted first. The `client` and `flow` tests need the sibling client repo; `flow` spawns `test/testServer.py` on a free port.
- **Runner**: its venv is `tests/windfire-security-suite` (`PYTHON_SUITE_VIRTUAL_ENV`), reinstalled when the hash of `tests/`, `server/` or `test/requirements.txt` changes. For dev it reuses a server already answering on `localhost`. Otherwise it starts `authServer.py --port <port>` with the suite venv and stops only that PID on exit or Ctrl-C (`-n` never starts, `-K` keeps it running). It never uses `stop-auth-server.sh`, which would also kill a hand-started server. It doesn't prompt for credentials without a terminal. Its final summary lists every test of each tier with PASS/FAIL/SKIP and the reason: `tests/suite_report.py` builds it from the tier's JUnit XML (`<error>` counts as FAIL; parametrized cases that all end the same way are collapsed into one row). A live tier whose environment isn't configured still runs pytest with `--env`, so the tests skip with "not configured", and it is reported as `SKIPPED`.
- Shared constants and helpers are in `tests/suite_helpers.py` (`pytest.ini` sets `pythonpath = .`). Import from there, never `from conftest import`: there are two conftests.

The manual scripts in `test/` are still there: `./start-test-server.sh -e dev` runs `testServer.py`, a dummy service with one endpoint protected by the auth server, and `./run-test-client.sh -e dev` runs `testClient.py`, which hits the health endpoints, authenticates and calls the protected endpoint. Both prompt for username/password/service (`getCredentials`). `-e {dev|test|prod}` targets the auth server from `tests/environments.json` through `common.sh`'s `setWindfireSecurityTarget`, which exports the `WINDFIRE_SECURITY_HOST/PORT` the client library honors. They use a separate `windfire-security-test` venv; `test/installPrereqs.sh` installs `test/requirements.txt` plus the editable sibling `windfire-security-client`.

## Keycloak install, run, upgrade

All entry points are interactive shell scripts that take the menu choice as an optional argument:
- `keycloak/start-keycloak.sh [1|2|3]` runs Keycloak locally: 1 is `start-dev`, 2 is `start` with the localhost PEM cert, 3 is Docker.
- `keycloak/deployment/install-keycloak.sh [1|2] [--side-by-side]` does a fresh install: 1 on raspberry01 (`raspberry/keycloak-install.yaml`), 2 on localhost (`localhost/keycloak-install.yaml`, no sudo, own `localhost/ansible.cfg`).
- `upgrade-keycloak.sh` upgrades raspberry01 only (`raspberry/keycloak-upgrade.yaml`).
- `backup-keycloak.sh [-v <version>] [-y]` backs up raspberry01 to the Mac (`raspberry/keycloak-backup.yaml`, settings in `raspberry/conf/keycloak-backup-config.yml`).
- `uninstall-keycloak.sh [-y]` removes Keycloak from raspberry01.
- `deploy-keycloak-tls.sh` deploys a new raspberry01 certificate.

The local version has a single source, `KEYCLOAK_VERSION` in `common.sh`, from which `KEYCLOAK_HOME` (`~/software/keycloak-<v>`) and the Docker tag derive. The Pi's version is `keycloak_version` in `keycloak/deployment/raspberry/conf/raspberry-config.yml`.

Both install playbooks start with a pre-flight that, if Keycloak is already there, prints an ALERT pointing to the upgrade procedure and ends with `meta: end_host`/`end_play` (exit 0, nothing changed). On the Pi, "already there" means any of: the unit, `/etc/keycloak/keycloak.conf`, `/opt/keycloak/keycloak-*`, or the `keycloak` user. The Raspberry install is three plays plus two imports, each guarded by `when: not keycloak_already_installed`:
1. pre-flight;
2. `import_playbook: raspberry.yaml` (apt upgrade, headless JDK);
3. install: `keycloak` user, the tarball checked against its `.sha1`, `templates/keycloak.conf.j2` and `templates/keycloak.service.j2`, the cert copied to `/etc/keycloak/tls`, `kc.sh build`, `kc.sh bootstrap-admin user`;
4. `import_playbook: keycloak-tls-deploy.yaml` (first start and HTTPS check);
5. summary.

Gotchas verified against 26.8.1:
- `--config-file` is a `kc.sh` option and must come before the command (`kc.sh --config-file=X build|export|bootstrap-admin`); after it, it fails with "Unknown option".
- `bootstrap-admin` cannot run before the TLS files named in `keycloak.conf` exist.
- `bootstrap-admin` exits 0 even when it fails, so the playbook checks its output.
- `bootstrap-admin` gets its credentials through `WINDFIRE_KC_ADMIN_*` env vars, never `KC_BOOTSTRAP_ADMIN_*`, which Keycloak also reads as config and would use to create the user twice.

On raspberry01 Keycloak runs only as the `keycloak` systemd unit, and the unit must never carry admin credentials (`KEYCLOAK_ADMIN*`/`KC_BOOTSTRAP_ADMIN_*`). The upgrade playbook:
- installs the new version side by side in `/opt/keycloak/keycloak-<version>`, after backing up to `/opt/keycloak/backup-<ts>.tgz` and exporting to `/opt/keycloak/export-<ts>`;
- copies (never moves) `data/`, and points `ExecStart` at the new `kc.sh` via the drop-in `keycloak.service.d/10-keycloak-version.conf`;
- on failure, restores `keycloak.conf` and the drop-in and restarts the old version.

Its pre-flight:
- reads the old version from the install folder name and rejects downgrades;
- checks free disk space;
- rejects options removed in Keycloak 26 (hostname v1, `proxy=`);
- checks that the `windfire` issuer is unchanged (skipped with a warning if the realm returns 404).

It sets the old H2 credentials (`sa`/`password`) only when upgrading from a version older than 26.2. A database created by 26.2 or later uses the new defaults.

The backup playbook:
- fails in pre-flight, without stopping Keycloak, if the SSH client address is not `mac_ip` (192.168.1.27) or if the unit does not run `/opt/keycloak/keycloak-<keycloak_version>`;
- stops Keycloak (H2 is locked while it runs) and, in a 0700 staging folder, runs `kc.sh export --users realm_file` into `export/`, copies the install's `data/`, `conf/`, `providers/`, `themes/`, `/etc/keycloak` and the unit files into `files/` through a tar pipe (keeps absolute paths, owners, symlinks; `cp -a --parents` fails on the Pi under the 0700 staging folder), and writes `MANIFEST.txt`; it restarts Keycloak in `always`;
- warns in pre-flight about `kc-backup-*` leftovers of failed runs, never removes them;
- tars the folder, `fetch`es it to `~/opt/keycloak/backup`, compares the sha256 of both copies, and only then removes the archive from the Pi (a `rescue` keeps everything on any failure);
- writes the local archive path to `~/opt/keycloak/backup/.last-backup`, which `backup-keycloak.sh` reads to run `sops/sops-crypt.sh -e -f <archive> -r -y` (the plain archive is deleted only after a verified round trip).

The Mac's `local_backup_dir` is set in both `keycloak-backup-config.yml` and `backup-keycloak.sh` (passed with `-e`).

## Certificate / TLS setup

`ssl/createRootCA.sh` generates the Windfire self-signed Root CA (`WindfireRootCA.key`/`.crt`) and copies it into `~/opt/windfire/ssl/{keystore,truststore}`. `ssl/generateServerCert.sh` issues per-host server certs off that CA (uses `openssl_config_localhost.ext` / `openssl_config_raspberry.ext` as the SAN config depending on target). These certs are what `SSL_KEYFILE`/`SSL_CERTFILE` in `server/.env` point at, and what `ROOT_CA_PATH` in the test scripts verifies against.

Keycloak's own TLS is set up separately via `keycloak/security/setupTLS.sh`. That script creates a dedicated **Windfire Keycloak Root CA**: the certificate is `~/opt/keycloak/ssl/truststore/WindfireKeycloakRootCA.crt` and the AES-256 key is `~/opt/keycloak/ssl/keystore/WindfireKeycloakRootCA.key`, which the user encrypts with sops/age by hand. The same script issues PEM `windfire-keycloak.key`/`.crt` server certificates off that CA (SANs from `keycloak/security/openssl_config_{localhost,raspberry}.ext`) and checks their expiry. It is independent of the Windfire Root CA above. After functions 1 and 2 it prints a red reminder that the plain CA key must be sops-encrypted, saved in the Password Manager and then deleted from disk. For a local Keycloak, `keycloak/setupKeycloakMode.sh` option 1 copies the localhost `windfire-keycloak.crt/.key` into `$KEYCLOAK_HOME/conf/tls` (`KEYCLOAK_CONF_TLS_DIR`), and `start-keycloak.sh` option 2 starts Keycloak with `--https-certificate-file`/`--https-certificate-key-file`. The auth server trusts that separate CA when it calls Keycloak's token/userinfo/JWKS endpoints via `KEYCLOAK_VERIFY_SSL_CERTS`/`KEYCLOAK_CA_CERT_PATH` in `server/.env` (see `keycloakAuth.py`'s `KeycloakConfig.verify`) — without a correct `KEYCLOAK_CA_CERT_PATH`, calls to a self-signed Keycloak fail with `SSLCertVerificationError`, which `authRouters.py` surfaces as a misleading 401. `KEYCLOAK_CA_CERT_PATH` must be the Keycloak Root CA (not Keycloak's leaf `server.crt.pem`, which gives "unable to get local issuer certificate") and may use `~`; the Raspberry deploy playbook copies `WindfireKeycloakRootCA.crt` to `~/opt/keycloak/ssl/truststore` on the Pi.

Both private CAs carry a critical `nameConstraints` extension built from `WINDFIRE_CA_PERMITTED_NAMES` in `common.sh` (`DNS:raspberry01 DNS:raspberry02 DNS:localhost IP:127.0.0.1/255.255.255.255`), via the shared helpers `buildNameConstraints`, `verifyNameConstraints` and `testNameConstraints` there:
- Both scripts print the list before signing, and check the extension right after. If it is missing, `createRootCA.sh` deletes the new cert/key and `setupTLS.sh` lets its `cleanup()` trap remove the partial CA (`ROOT_CA_IN_PROGRESS`).
- `ssl/createRootCA.sh test` and `setupTLS.sh 5` issue a throwaway `example.com` cert from the existing CA, check that `openssl verify` rejects it with `permitted subtree violation`, then delete it. Both need the CA private key.
- A server cert SAN outside the list fails verification. The names are fixed when a CA is created, so adding a host means adding it to the variable, recreating both CAs and reissuing their server certs. CAs created before this change are unconstrained and must be recreated.
- On macOS, a CA is trusted in the login keychain only (`security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db <cert>`), never the System keychain. The old, unconstrained CA must be deleted by SHA-1 (`security delete-certificate -Z`), because it has the same CN as the new one. `printKeychainTrustInstructions` in `common.sh` prints these steps after CA creation. The repo's own scripts and the Python services don't read the keychain; they use the truststore files.

## Architecture of `server/`

Entry point is `authServer.py`: builds the FastAPI `app`, wires CORS/TrustedHost/GZip middleware, registers the custom `https_enforcement_middleware` (from `middlewares.py`) that redirects HTTP→HTTPS except for `/health`-suffixed paths and adds HSTS/security headers, and mounts `apiRouter.api`. `main()` reads `ENFORCE_HTTPS`/SSL paths from `settings` and decides whether `uvicorn.run` gets `ssl_keyfile`/`ssl_certfile`.
- **API docs**: `/docs`, `/redoc` and `/openapi.json` exist only when `ENABLE_API_DOCS` is true, because `FastAPI()` gets `docs_url`/`redoc_url`/`openapi_url=None` otherwise. The flag is read when the module is imported, so tests flip it with `importlib.reload(authServer)`. With docs off, `GET /` returns `{"service": APP_NAME}` instead of redirecting to `/docs`.
- **No forwarded headers**: the server is exposed directly with no reverse proxy. Every `uvicorn.run` call passes `proxy_headers=False`, and the middleware decides HTTPS from `request.url.scheme` only, so a client-sent `X-Forwarded-Proto`/`X-Forwarded-Ssl` doesn't bypass the redirect.
- **Error bodies**: they carry fixed details only, never exception text, `str(e)`, configured service names or stack traces. The cause goes to the module logger, and `global_exception_handler` uses `logger.exception`.

Routing is nested under a version prefix: `apiRouter.py` defines `api = APIRouter(prefix="/v1")` and includes `routers/healthRouters.py` (`/v1/monitor/health`) and `routers/authRouters.py` (`/v1/security/auth`, `/v1/security/verify`). A `v2` router is declared but unused — don't assume `/v2` endpoints exist.

Auth logic lives in `keycloakAuth.py`, independent of FastAPI:
- `KeycloakConfig` resolves per-service Keycloak realm/client credentials by looking up `service_config.json` via `config/service_config_reader.py` (`ServiceConfigReader`/`serviceConfig` singleton).
- `KeycloakAuth` wraps the Keycloak token/userinfo/introspect/JWKS endpoints (password grant, client-credentials grant, refresh, introspection, local JWT verification against JWKS).
- Module-level convenience functions `authenticate_user()`, `authenticate_service_account()`, `verify_token()` are what the routers call — prefer these over instantiating `KeycloakAuth` directly.
- `verify_token(..., method='local')` (the default, used by `/v1/security/verify`) validates the JWT locally against Keycloak's JWKS — no special Keycloak client permissions needed. It enforces the signature, audience (`aud` must contain the service's `client_id`), issuer (`iss` must equal `{KEYCLOAK_SERVER_URL}/realms/{realm}`, so `KEYCLOAK_SERVER_URL` must match the hostname Keycloak puts in its tokens) and the presence of `exp`/`iat`/`iss`/`aud`; there is no fallback that skips the audience check. Keycloak access tokens carry `aud: account` by default, so **each client in `service_config.json` needs an Audience mapper in Keycloak** (client scope or dedicated mapper adding its own client_id to `aud`), otherwise `/verify` returns 401. JWKS is held in a module-level cache keyed by `jwks_endpoint` (10-minute TTL); a token with an unknown `kid` triggers a refetch at most once every 30 seconds per endpoint. `/verify` logs the real failure reason but always answers 401 with the fixed detail `"Invalid or expired token"` (also for an unknown service, whose `ServiceConfigError` would otherwise list the configured services). `method='introspect'` calls Keycloak's introspection endpoint instead and requires the client to have service-account introspection rights.

Config loading: `config/settings.py` (`Settings`/`settings` singleton) reads `.env` via `python-dotenv`, with type coercion baked in for `ENFORCE_HTTPS`, `KEYCLOAK_VERIFY_SSL_CERTS` and `ENABLE_API_DOCS` (→ bool, unset → `None`) and `API_PORT`/`API_PORT_SECURE` (→ int) — other keys return raw strings. `config/service_config_reader.py` is the multi-tenant service registry described above.

Logging: every module gets its logger via `logger.loggerFactory.logger_factory.get_logger(<module_name>)` (never `logging.getLogger` directly) — this ensures consistent formatting (`ColorFormatter`) and routes to both a `TimedRotatingFileHandler` (`server/logs/windfire-security-server.log`, midnight rotation, 7 backups) and stdout. Level is controlled by the `LOG_LEVEL` env var (defaults to `DEBUG`).

Errors surface as `KeycloakAuthError` from `keycloakAuth.py`; routers translate them to HTTP 401 (bad credentials/invalid token, and an unknown service on `/auth` too, without listing the configured services) or 500 (unexpected). `/auth` and `/verify` can also answer 429 (rate limiting, below).

### Login rate limiting (`/v1/security/auth`)

`server/rateLimit.py` protects the password grant against guessing. Both limits answer 429 with the same fixed detail `"Too many login attempts, try again later"` and a `Retry-After` header, so a caller can't tell which one fired:
- **Per client IP**: slowapi, `5/minute;30/hour` (`AUTH_RATE_LIMIT`), keyed on the TCP peer address (`X-Forwarded-For` is not trusted: there is no reverse proxy in front of uvicorn). Requests rejected with 422 by body validation don't count.
- **Per username**: after 10 failed logins (any 401, so a Keycloak outage counts too) for the same lowercased username within 15 minutes, that username gets 429 for 15 minutes and Keycloak is not called. A successful login resets the counter.

State is in memory and per process: a restart clears it, and running more than one uvicorn worker would need shared storage (e.g. slowapi's Redis backend and a shared failure store). Unit tests reset both limits (and the `/verify` counters) in an autouse fixture (`tests/unit/conftest.py`). The live tier logs in 4 times per run, so back-to-back runs can be rate limited: its negative `/auth` tests skip on 429.

Logging: a failed login is one WARNING with the username (`!r`) and client IP only (the cause is at DEBUG), a success is INFO without the token, and `keycloakAuth.authenticate_with_password` logs at DEBUG only. Passwords and tokens are never logged.

The Windfire UIs no longer call this endpoint: its callers are back-end services and the test tools, through `windfire-security-client` (whose `authenticate()` returns `None` on any non-200, 429 included). The request/response contract is unchanged.

### `/v1/security/verify` rate limit

The limit is per client IP only: slowapi, `300/minute` (`VERIFY_RATE_LIMIT`), keyed like `/auth` on the TCP peer address. It is deliberately generous because windfire-calendar calls `/verify` from a single IP for every request it serves, so tighten it only with that traffic in mind. Over the limit, the shared `rate_limit_exceeded_handler` answers 429 with `Retry-After` and the fixed detail `"Too many requests, try again later"` (`TOO_MANY_REQUESTS_DETAIL`). Only the `/auth` path gets the login detail. As on `/auth`, requests rejected with 422 or without a bearer token don't count. `windfire-security-client`'s `verify_or_raise` raises `AuthServerError` on a 429.
