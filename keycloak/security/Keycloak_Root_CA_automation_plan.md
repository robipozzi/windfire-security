# Keycloak Root CA — Automation Plan for Claude Code

Oct 16, 2026 · prepared for Roberto · to hand to Claude Code in the repository that holds your automation scripts · based on the *Keycloak Configuration Plan without Tailscale* (§D3–D4) and the *Phase 1 Operative Checklist without Tailscale* (7.1, 7.1a, 7.4, 9.5a, 9.6, 15.5), both in `docs/`

> **Revision, Oct 16, 2026 (later):** the server key and certificate are now created by their own checklist task, 9.5a, which ends with the two `keycloak.conf` lines; 9.6 only switches Keycloak to them. This plan follows: a new `server-cert` operation (= 9.5a) wraps `csr` and `sign`, stages the files on `raspberry01` and checks `keycloak.conf`; `install` (= 9.6) only switches. Your existing CA (`WindfireRootCA.crt`) is now step-ca's root (checklist 7.1), not a new one. Previous version: `docs/archive/2026-10-16_before_keycloak_cert_step/`. Keycloak's certificate and key are named `windfire-keycloak.crt` and `windfire-keycloak.key` (`KC_CERT_NAME`); rename any `raspberry01.crt`/`.key` in the scripts.

> **Revision, Oct 16, 2026 (no USB stick):** the root key is no longer on a USB stick mounted on the laptop. It is kept only in the password manager as a sops/age-encrypted file (`WindfireKeycloakRootCA.key.sops.json`). `CA_KEY_DIR` is replaced by `CA_KEY_SOPS`, `CA_AGE_RECIPIENT` and `KC_CA_TMP`; `sign` now runs on `raspberry01`: it streams the decrypted key over SSH into RAM (`/dev/shm/kc-ca`), signs there and always shreds the folder. No serial file is kept between renewals. Changed: sections 3 (assumption 4), 4 (task 1), 5 (operations 1–3a), 6, 9. Previous version: `docs/archive/2026-10-16_before_no_usb/`.

## 1. Goal

Keycloak's TLS certificate on `raspberry01` must be signed by a brand new certificate authority, **Windfire Keycloak Root CA**, whose certificate is the file **`WindfireKeycloakRootCA.crt`**. Until now the scripts issued or installed a certificate from Roberto's existing CA (referred to in the docs as `roberto-root-ca.pem`, possibly `WindfireRootCA.crt` in the scripts). This plan tells Claude Code what to change in the scripts so the whole lifecycle is automated: create the root once, issue the server certificate, distribute the root, install and switch with rollback, check expiry, renew.

The manual procedure the scripts must reproduce is KC plan §D3 (commands tested with OpenSSL 3.0). Treat that section as the reference for exact `openssl` options.

## 2. How to use this file

Open Claude Code in the scripts repository and paste:

> Read `Keycloak_Root_CA_automation_plan.md` (attached / copied into this repo as `docs/`). First explore this repository and report how the existing CA and Keycloak certificate scripts are organised (section 4, task 0), then propose the concrete file-by-file changes before editing. Follow the conventions already used in this repo. Implement sections 5–8, run the tests in section 9, and stop before anything that touches a real host or the real root key.

## 3. Assumptions (this plan was written without seeing the scripts repo)

Claude Code must check each one and adapt, saying which ones were wrong:

1. The scripts are Bash (or POSIX sh), run from the macOS admin laptop, and reach `raspberry01` over SSH as `pi` with `sudo`. If they are Ansible, Python or Make targets instead, implement the same operations in that form.
2. There are existing scripts that create a CA and/or sign Keycloak's certificate with the old CA, and something that references the old root file by name (`roberto-root-ca.pem`, `WindfireRootCA.crt` or similar), for example in the backend's `EXP_JWKS_CA_FILE`, a Caddy config, a trust-store installer or a health check.
3. The Keycloak layout is the one from the KC plan: config in `/etc/keycloak/keycloak.conf`, TLS files `/etc/keycloak/tls/windfire-keycloak.crt` and `/etc/keycloak/tls/windfire-keycloak.key` (root:keycloak, 0640), systemd unit `keycloak.service`, management health on `https://raspberry01:9000/health/ready`, HTTPS on 8443, TLS 1.3 only.
4. There is no USB stick. The root key is kept only in the password manager as a sops/age-encrypted file (`WindfireKeycloakRootCA.key.sops.json`, sops binary format stored as JSON, encrypted to the age key in `~/.config/sops/age/keys.txt`); you save it from the password manager to the laptop before a signing run. The scripts decrypt it with `sops -d` and stream it over SSH into a RAM-only folder on `raspberry01` (`KC_CA_TMP`, default `/dev/shm/kc-ca`, mode 0700), sign there, and shred it. The decrypted key is never written to the laptop disk, the repository, or a Pi's SD card/SSD.
5. The laptop has OpenSSL 3 from Homebrew (`$(brew --prefix openssl@3)/bin/openssl`); macOS's LibreSSL `openssl` is not used. Raspberry Pi OS has OpenSSL 3.
6. Your existing CA (`WindfireRootCA.crt`), which is also step-ca's root (checklist 7.1), and its scripts are a different CA and must not be changed.

## 4. Tasks

**Task 0 — Survey (no edits).** List every script, config and doc in the repo that: creates or uses a CA; signs, installs or checks Keycloak's certificate; references the old root file; installs roots into trust stores. Report what each does today and which operation in section 5 it maps to. Propose the change list and wait for approval.

**Task 1 — Configuration.** One settings file (for example `keycloak-ca.env`, or the repo's existing equivalent) with these values and the defaults shown; scripts read it and every value can be overridden by an environment variable:

| Setting | Default |
| --- | --- |
| `CA_CN` | `Windfire Keycloak Root CA` |
| `CA_ORG` | `Windfire` |
| `CA_BASENAME` | `WindfireKeycloakRootCA` (→ `WindfireKeycloakRootCA.crt`, `.key`, `.key.sops.json`; a `.srl` exists only inside `KC_CA_TMP` while signing) |
| `CA_DAYS` / `CA_KEY_BITS` | `3650` / `4096` (RSA, key encrypted with AES-256) |
| `CA_KEY_SOPS` | path of `WindfireKeycloakRootCA.key.sops.json` saved from the password manager (no default; required for signing; deleted after a successful run unless `--keep-sops-file`) |
| `CA_AGE_RECIPIENT` | `$(age-keygen -y "$SOPS_AGE_KEY_FILE")` (age public key used by `create-root`) |
| `KC_CA_TMP` | `/dev/shm/kc-ca` (RAM-only working folder on `raspberry01`; must be on tmpfs) |
| `CA_CERT_REPO_PATH` | `infra/keycloak/WindfireKeycloakRootCA.crt` (in the `windfire-expenses` repo, or the path this repo uses) |
| `KC_HOST` / `KC_SSH` | `raspberry01` / `pi@raspberry01` |
| `KC_TLS_DIR` | `/etc/keycloak/tls` |
| `KC_CONF` | `/etc/keycloak/keycloak.conf` |
| `KC_CERT_NAME` | `windfire-keycloak` (→ `windfire-keycloak.crt`, `windfire-keycloak.key`) |
| `SERVER_DAYS` / `SERVER_KEY_BITS` | `397` / `3072` |
| `SERVER_SANS` | `DNS:raspberry01,IP:<raspberry01-IP>` plus every name in the current certificate's SAN list |
| `RENEW_BEFORE_DAYS` | `30` |
| `TRUST_CLIENTS` | list of `user@host:store` entries (store = `system` or `java:<path-to-cacerts>`) from the "Clients of raspberry01" runbook list |
| `OPENSSL` | `$(brew --prefix openssl@3)/bin/openssl` on macOS, `openssl` elsewhere |

**Task 2 — Replace the old CA for Keycloak.** Every place that used the old root to sign, verify or trust **Keycloak** now uses `WindfireKeycloakRootCA.crt`: backend env (`EXP_JWKS_CA_FILE`), Caddy `tls_trust_pool` (D4), health checks, curl/openssl checks, trust-store installers. Keep old-CA scripts only if something other than Keycloak still uses them, and say so. Rename variables or files that name the old CA in a Keycloak context.

**Task 3 — Implement the operations in section 5**, as subcommands of one script (for example `keycloak-ca.sh <command>`) or as separate scripts, following the repo's style.

**Task 4 — Tests (section 9) and docs:** a short README section listing the commands, the yearly renewal, and the rollback.

## 5. Operations and expected behaviour

Each operation prints what it is about to do, supports `--dry-run` (print commands, change nothing), exits non-zero with a clear message on any failure, and never prints key material or passphrases.

1. **`create-root`** (laptop, once).
   - Refuses to run if `WindfireKeycloakRootCA.crt`, `.key` or `.key.sops.json` already exists in the target directory (no `--force`; replacing a root is a deliberate manual act).
   - Generates the RSA 4096 key encrypted with AES-256, asking for the passphrase interactively (never as a command-line argument), and a self-signed certificate: subject `CN=Windfire Keycloak Root CA, O=Windfire`, `basicConstraints = critical, CA:TRUE, pathlen:0`, `keyUsage = critical, keyCertSign, cRLSign`, `subjectKeyIdentifier = hash`, SHA-256, `CA_DAYS`.
   - Writes the key with mode 0600 (umask 077), encrypts it with `sops -e --age "$CA_AGE_RECIPIENT" --input-type binary --output-type json` to `WindfireKeycloakRootCA.key.sops.json`, checks that `sops -d --input-type json --output-type binary` gives back the same bytes (`cmp`), then removes the plain key. Copies the certificate to `CA_CERT_REPO_PATH`, prints the SHA-256 fingerprint and the expiry for the runbook, and reminds you to attach the `.sops.json` to the password manager entry and then delete it from the laptop.
2. **`csr`** (runs on `raspberry01` over SSH).
   - Generates a new RSA 3072 key at `KC_TLS_DIR/KC_CERT_NAME.key.new` (root:keycloak, 0640) and a CSR with subject `CN=raspberry01, O=Windfire` in `KC_CA_TMP`. The CSR stays on the Pi; the server key never leaves it.
3. **`sign`** (laptop drives it, runs on `raspberry01`).
   - Requires `CA_KEY_SOPS` to exist and to decrypt (`sops -d ... >/dev/null`); fails otherwise. Refuses to run unless `KC_CA_TMP` is on tmpfs (`findmnt -n -o FSTYPE --target /dev/shm` prints `tmpfs`).
   - Streams `sops -d --input-type json --output-type binary "$CA_KEY_SOPS" | ssh "$KC_SSH" 'umask 077 && mkdir -p KC_CA_TMP && cat > KC_CA_TMP/WindfireKeycloakRootCA.key'` (the decrypted key goes through the pipe only) and copies `WindfireKeycloakRootCA.crt` next to it.
   - Signs the CSR there with an extensions file built from config (the SANs come from `SERVER_SANS`, never copied from the CSR): `basicConstraints = critical, CA:FALSE`, `keyUsage = critical, digitalSignature, keyEncipherment`, `extendedKeyUsage = serverAuth`, `subjectAltName`, `subjectKeyIdentifier = hash`, `authorityKeyIdentifier = keyid:always`, `SERVER_DAYS`, SHA-256, `-CAcreateserial` inside `KC_CA_TMP` (random serial; no serial state is kept between renewals). The root key passphrase is asked interactively on the SSH TTY (`ssh -t`).
   - Runs `openssl verify -CAfile` on the result and prints issuer, expiry, SANs and EKU.
   - A `trap` always runs `sudo shred -u KC_CA_TMP/* && rmdir KC_CA_TMP` on `raspberry01`, on success, failure or Ctrl-C, then checks the folder is gone and exits non-zero if it is not. After a successful run it deletes `CA_KEY_SOPS` from the laptop (unless `--keep-sops-file`).
3a. **`server-cert`** (laptop → `raspberry01`; checklist 9.5a). Runs `csr` then `sign`, then stages the result on `raspberry01` without touching the running Keycloak:
   - Before the cleanup trap of `sign` runs, installs the signed certificate from `KC_CA_TMP` to `KC_TLS_DIR/KC_CERT_NAME.crt.new` (root:keycloak, 0640) and `WindfireKeycloakRootCA.crt` to `KC_TLS_DIR/` (root:keycloak, 0644).
   - Checks `keycloak.conf` (`KC_CONF`, default `/etc/keycloak/keycloak.conf`) has exactly these two lines and no `KC_HTTPS_CERTIFICATE_*` variable overriding them in `/etc/keycloak/keycloak.env` or the unit:
     ```properties
     https-certificate-file=/etc/keycloak/tls/windfire-keycloak.crt
     https-certificate-key-file=/etc/keycloak/tls/windfire-keycloak.key
     ```
     If they are missing or different, it prints the expected lines and exits non-zero. With `--set-conf` it writes them instead (after copying `keycloak.conf` to `keycloak.conf.bak-<date>`, keeping owner root:keycloak and mode 0640), and removes any `https-key-store-*` lines. It never restarts Keycloak.
   - Prints the staged certificate's issuer, expiry and SANs, and reminds you to run `trust` for every client before `install`.
4. **`trust`** (laptop → each client).
   - Installs `WindfireKeycloakRootCA.crt` on the laptop (macOS System keychain, `trustRoot`), on `raspberry01` (`/usr/local/share/ca-certificates/WindfireKeycloakRootCA.crt` + `update-ca-certificates`) and on each `TRUST_CLIENTS` entry (system store, or `keytool -importcert -cacerts -alias windfire-keycloak-root` for Java). Idempotent: an entry that already has the root is reported and skipped.
   - Prints a table of clients with OK / FAILED; exits non-zero if any failed.
5. **`install`** (laptop → `raspberry01`; checklist 9.6). Switches to the files staged by `server-cert`.
   - Refuses to run unless `trust` has succeeded for every client (for example a state file written by `trust`, or a `--clients-confirmed` flag) so other realms' apps are not cut off, and unless both `.new` files exist and the `keycloak.conf` check of `server-cert` passes.
   - Checks that the new key and certificate have the same public key, renames the current `KC_CERT_NAME.crt`/`.key` to `.old`, moves the new ones into place, restarts `keycloak`.
   - Waits up to 120 s for `curl --cacert KC_TLS_DIR/WindfireKeycloakRootCA.crt https://raspberry01:9000/health/ready` to return `"status": "UP"`, then checks from the laptop with `openssl s_client -CAfile ... -servername raspberry01` that the issuer is Windfire Keycloak Root CA and the verify code is 0.
   - **If any check fails, it rolls back automatically** (restores the `.old` files, restarts, re-checks health) and exits non-zero. File names in `keycloak.conf` never change.
6. **`rollback`** — restores the `.old` files and restarts Keycloak; fails cleanly if there are no `.old` files.
7. **`cleanup`** — `shred -u` the `.old` files after you confirm the other realms' apps still sign in (checklist 16.4).
8. **`check`** — read-only: prints the root's and the server certificate's subject, issuer, SANs and days left; exits 1 if the server certificate expires within `RENEW_BEFORE_DAYS` or does not chain to `WindfireKeycloakRootCA.crt`. Suitable for a cron job or systemd timer on the laptop or `raspberry01`.
9. **`renew`** — `server-cert` + `install` (no `trust`: the root does not change). Run once a year when `check` warns.

## 6. Safety rules

- The root key (`*.key` of the CA) is never written inside the repository, never written in plain form to the laptop disk (only `create-root` writes it, passphrase-encrypted, and removes it after the sops round trip), never logged. On `raspberry01` it exists only in `KC_CA_TMP` on tmpfs for the duration of `sign`, and is shredded right after. Add `*.key`, `*.key.new`, `*.csr`, `*.srl`, `*.key.sops.json` to `.gitignore` if not already there; only `WindfireKeycloakRootCA.crt` is committed (the `.sops.json` lives in the password manager, not in Git).
- Passphrases are read interactively (or from the password manager CLI if the repo already does that), never passed as arguments or stored in files.
- Scripts use `set -euo pipefail`, quote every variable, and clean temporary files with a `trap`.
- No change to the step-ca scripts, ufw rules or anything else not listed here; `keycloak.conf` is changed only by `server-cert --set-conf`, and only its two `https-certificate-*` lines (and any `https-key-store-*` lines it replaces).
- Nothing runs against a real host, the real root key or the real `.sops.json` during tests.

## 7. Files expected after the change (names adapt to the repo)

- `keycloak-ca.sh` (or the repo's equivalent) with the operations of section 5.
- `keycloak-ca.env.example` with the settings of task 1 and placeholders, no secrets.
- `templates/root.cnf` and `templates/server.ext` (or generated inline from config).
- Updated references from the old root to `WindfireKeycloakRootCA.crt` (task 2).
- `tests/` for section 9 and a README section.

## 8. Order of use (matches the checklist)

1. `create-root` → checklist 7.1a.
2. `trust` on the laptop and `raspberry01` → checklist 7.4.
3. `server-cert` → checklist 9.5a (key, certificate and the `keycloak.conf` lines).
4. `trust` for every client from 2.2, then `install` → checklist 9.6.
5. `check` → runbook, 15.5; `cleanup` after 16.4.
6. Each year: `renew`.

## 9. Tests Claude Code should write and run

Use a throwaway directory and a throwaway CA; mock `ssh`, `scp`, `sudo`, `systemctl` and `curl` where a remote host is involved (bats-core, or the repo's test framework).

1. `create-root` produces a certificate with the exact subject, `CA:TRUE, pathlen:0`, `keyCertSign, cRLSign`, ~3650 days; it leaves only the `.crt` and the `.key.sops.json`, which decrypts (throwaway age key) to a passphrase-encrypted key; a second run refuses to overwrite.
2. `sign` produces a certificate that `openssl verify -CAfile WindfireKeycloakRootCA.crt` accepts, with `CA:FALSE`, EKU `serverAuth`, exactly the SANs from `SERVER_SANS` (even if the CSR asks for others), ~397 days.
3. `sign` fails cleanly when `CA_KEY_SOPS` is missing or `sops -d` cannot decrypt it (use a throwaway age key), and when `KC_CA_TMP` is not on tmpfs.
3b. After `sign` succeeds, and after a mocked failure of the `openssl x509` step, the mocked remote `KC_CA_TMP` no longer exists and `shred -u` was called on the key; the decrypted key never appears in a file on the laptop side (check the test's temp directory).
4. A local TLS test: `openssl s_server -tls1_3` with the signed certificate and `openssl s_client -CAfile WindfireKeycloakRootCA.crt` returns `Verify return code: 0 (ok)` and an issuer of Windfire Keycloak Root CA.
5. `install` with a mocked failing health check rolls back and leaves the `.old` files restored.
6. `install` refuses to run when `trust` has not succeeded for all clients.
7. `server-cert` fails when a fake `keycloak.conf` lacks the two `https-certificate-*` lines or points elsewhere, passes when they match, and with `--set-conf` writes them, keeps a backup and never calls `systemctl restart`.
8. `check` exits 1 for a certificate expiring in 10 days and for one signed by another CA, 0 otherwise.
9. `shellcheck` passes on every script; `--dry-run` changes nothing (compare a directory listing before and after).
10. `grep -r` finds no remaining reference to the old root file in a Keycloak context.

## 10. Acceptance criteria

- All tests in section 9 pass; the README lists the commands.
- Running the operations in the order of section 8 against the real setup gives the same results as checklist 9.6's **Check**: health `UP`, issuer Windfire Keycloak Root CA with verify code 0 from the laptop, `curl -sI https://raspberry01:8443/realms/master/` without `-k`, every other realm's app still signs in, TLS 1.2 refused.
- The backend on the laptop fetches the JWKS with `EXP_JWKS_CA_FILE=infra/keycloak/WindfireKeycloakRootCA.crt`.
