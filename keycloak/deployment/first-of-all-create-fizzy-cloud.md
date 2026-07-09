# Automate Keycloak install/deploy/config on Raspberry Pi via Ansible

## Context
`keycloak/deployment/raspberry/` currently only automates downloading and unzipping the Keycloak 25.0.2 distribution (`keycloak.yaml`) plus OS/Java prereqs (`raspberry.yaml`). Everything else — creating a non-root `keycloak` user, generating a TLS cert, writing `keycloak.conf`, building the optimized image, and starting/enabling Keycloak — is still manual, done by SSH'ing in and running interactive shell scripts (`keycloak_scripts/start-keycloak.sh` etc.) that `read -s` for passwords and background the process with `&` (no systemd, no boot-persistence). `README.md` even has a literal `[TODO]` under "Install and run Keycloak as server on a Raspberry Pi box". The user supplied a concrete runbook (9 numbered steps: system user, self-signed TLS cert with SAN, `keycloak.conf`, `kc.sh build`, systemd unit, enable/start, verify, harden admin creds) that needs to become idempotent Ansible automation, fully replacing the manual/interactive path.

Repo-wide conventions (confirmed by exploration): flat single-play playbooks (no `roles/` anywhere), `vars_files` loading `conf/*.yml`, `#####` banner comments, `become: yes`, idempotency via `creates:`, no handlers/tags/Vault/CI anywhere yet. The sibling `deployment/raspberry/` (Python auth server) is the closest style template. This work introduces the repo's first systemd usage — no prior art to reuse there.

**Decisions already confirmed with the user** (do not re-litigate):
- TLS cert: raw `openssl req -x509 ...` via `command` module with `creates:`, not `community.crypto` (no new collection dependency).
- Admin bootstrap password: `vars_prompt` (`private: yes`, `no_log` on the consuming task) — no Ansible Vault.
- `keycloak_scripts/` (setenv.sh, setupKeycloak.sh, start-keycloak.sh) is deleted entirely — systemd becomes the sole start/stop/enable-at-boot mechanism.
- `keycloak_hostname: "{{ inventory_hostname }}"` (resolves to `raspberry01` today via the `identitymanager` inventory group), not a hardcoded string.

Branch `feature/update-keycloak-ansible` already exists locally, checked out, 0 commits ahead of `main`, clean tree — confirm we're on it, no need to create it fresh.

## File plan

**Modify `raspberry.yaml`** (OS prereqs):
- Pin Java explicitly: `apt: name=openjdk-17-jdk` instead of `default-jdk` (Keycloak 25 needs 17/21; `default-jdk` resolves unpredictably across Raspberry Pi OS variants/architectures — determinism matters since the systemd unit needs a real `JAVA_HOME`).
- Add `apt: name=openssl state=present` (mirrors the precedent already set in the sibling `deployment/raspberry/windfire-security-full-deploy.yaml`, which explicitly installs openssl rather than assuming it's present).

**Modify `keycloak.yaml`** (download/unpack only):
- Remove the `remote_keycloak_utils_dir` "ensure directory" + "copy keycloak_scripts" tasks (dead code once `keycloak_scripts/` is deleted).
- Interpolate the new `keycloak_version`/`keycloak_home` vars instead of the hardcoded `25.0.2` string in `keycloak_url`/`keycloak_zip`/the `unarchive` task's `creates:`.

**Create `keycloak-configure.yaml`** (new play, `hosts: identitymanager`, `become: yes`, `vars_files: conf/raspberry-config.yml`) — the bulk of the new work:
1. `vars_prompt` for `keycloak_admin_password` (`private: yes`).
2. `ansible.builtin.stat` on a sentinel path `{{ keycloak_home }}/.bootstrap_hardened`, registered as `hardened_marker` — used to compute `keycloak_bootstrap_admin: "{{ not hardened_marker.stat.exists }}"` as a `set_fact`. **Why**: without this, re-running this playbook after hardening (e.g. for an upgrade) would silently re-add the admin password to the world-readable systemd unit, undoing requirement 9. The sentinel makes the whole playbook set safely idempotent across the harden boundary.
3. System user/group: `ansible.builtin.group` (`system: yes`) then `ansible.builtin.user` (`system: yes`, `home={{ keycloak_home }}`, `shell=/usr/sbin/nologin`, `create_home=no` since the dir already exists from `keycloak.yaml`'s unarchive).
4. Ownership: `ansible.builtin.command: chown -R {{ keycloak_user }}:{{ keycloak_group }} {{ keycloak_home }}`, **not** `ansible.builtin.file` with `recurse: yes` — the Keycloak distribution has thousands of files (themes, providers, lib jars) and Python-level recursive stat/chown via the `file` module is dramatically slower than a native `chown -R`, which matters on Pi-class hardware. Guard with a `changed_when` based on a quick `stat` of the top-level dir owner rather than skipping it outright.
5. TLS cert: `ansible.builtin.command` running the literal `openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout {{ keycloak_home }}/conf/server.key.pem -out {{ keycloak_home }}/conf/server.crt.pem -subj "/CN={{ keycloak_hostname }}" -addext "subjectAltName=DNS:{{ keycloak_hostname }}"`, guarded by `creates: {{ keycloak_home }}/conf/server.crt.pem`. Follow with two `ansible.builtin.file` tasks: owner/group `{{ keycloak_user }}:{{ keycloak_group }}`, `mode: '0600'` on the key, `mode: '0644'` on the cert (cert is created as root by the command task, so ownership must be fixed explicitly after — the pre-generation directory chown in step 4 doesn't retroactively cover files that didn't exist yet).
6. `keycloak.conf`: `ansible.builtin.template` (`src=keycloak.conf.j2`), owner/group keycloak, `mode: '0640'`. **`notify: Rebuild keycloak`** — see handler below. Content: `hostname`, `https-certificate-file`, `https-certificate-key-file`, `db=dev-file` only; leave `hostname-strict`/`http-enabled` unset (production defaults are already correct per the requirements).
7. **Handler** `Rebuild keycloak`: `ansible.builtin.command: cmd="{{ keycloak_home }}/bin/kc.sh build"`, `become_user: "{{ keycloak_user }}"`. Fires only when `keycloak.conf` actually changes (first install, or a later build-time option change) — this is the correct idiomatic Ansible primitive for "rebuild whenever a build-time option changes" (exactly what the requirements doc says), and is more correct than a fake `creates:` sentinel (the shipped distribution already contains a `lib/quarkus/` directory pre-build, so that path can't be used as a "not yet built" guard).
8. Systemd unit: `ansible.builtin.template` (`src=keycloak.service.j2`, `dest=/etc/systemd/system/keycloak.service`, `mode: '0644'`), passing `keycloak_bootstrap_admin` (from step 2) and `keycloak_admin_password`. Task-level `no_log: true` (not play-level, so other tasks stay visible in output).
9. `ansible.builtin.systemd`: `daemon_reload: yes`, `name: keycloak`, `enabled: yes`, `state: started`.

**Create `templates/keycloak.conf.j2`** — 4 lines, no conditionals: `hostname={{ keycloak_hostname }}`, `https-certificate-file=...`, `https-certificate-key-file=...`, `db=dev-file`.

**Create `templates/keycloak.service.j2`** — mirrors the reference unit exactly, with `Environment=JAVA_HOME={{ java_home_discovered.stdout | default(java_home) }}` and the two `KEYCLOAK_ADMIN*` lines wrapped in `{% if keycloak_bootstrap_admin %}...{% endif %}` (emit-or-omit, not commented-out placeholders — cleaner for a production unit file). `java_home_discovered` comes from a small `ansible.builtin.shell` task (`dirname $(dirname $(readlink -f $(which java)))`) run before the template task in both `keycloak-configure.yaml` and `keycloak-harden.yaml` — **do not hardcode** `/usr/lib/jvm/java-17-openjdk-arm64` as truth, since Raspberry Pi OS ships both `armhf` and `arm64` variants with different paths; keep the hardcoded value only as a `default()` fallback var in `conf/raspberry-config.yml` in case discovery ever fails.

**Create `keycloak-harden.yaml`** (standalone, never wired into the main install path — requirement 9 is explicitly a manual/gated follow-up after the operator changes the admin password via the UI):
1. Same Java-path discovery task.
2. Re-template `keycloak.service.j2` with `keycloak_bootstrap_admin: false` (play-level var override, no `vars_prompt` needed — the `{% if %}` branch simply won't render).
3. `ansible.builtin.file`: touch `{{ keycloak_home }}/.bootstrap_hardened` (the sentinel `keycloak-configure.yaml` checks for).
4. `ansible.builtin.systemd`: `daemon_reload: yes`, then `name: keycloak`, `state: restarted`.

**Create `keycloak-verify.yaml`** (runnable after configure or harden):
1. `ansible.builtin.systemd: name=keycloak` (no state change, just query) → `register` → `ansible.builtin.assert` that `ActiveState == "active"`.
2. `ansible.builtin.uri: url="https://{{ keycloak_hostname }}:8443/" validate_certs=no status_code=[200,302,303]`.
3. `ansible.builtin.wait_for: host={{ keycloak_hostname }} port=8080 state=stopped timeout=5` — `state: stopped` is the correct primitive for "assert this port is closed" (confirms HTTPS-only, no plain-HTTP listener), cleaner than a `uri`+`ignore_errors`+`assert` combo.
4. `ansible.builtin.debug` summary of all three results.

**Modify `keycloak-uninstall.yaml`**:
- Fix the bug: `hosts: raspberry_identitymanager` → `hosts: identitymanager` (the old group doesn't exist in inventory; the playbook currently matches zero hosts).
- Add, in order: stop+disable service (`ansible.builtin.systemd`, `ignore_errors: yes` for partial installs) → remove `/etc/systemd/system/keycloak.service` → `daemon_reload` → remove `{{ remote_directory }}` (already covers `keycloak_home`, TLS cert, `keycloak.conf`, and the bootstrap sentinel since they're all nested under it) → remove `keycloak` user (`remove: yes`) → remove `keycloak` group (must come after user removal).
- Drop the now-dead `remote_keycloak_utils_dir` removal task.

**Delete** `keycloak_scripts/` (`setenv.sh`, `setupKeycloak.sh`, `start-keycloak.sh`) entirely.

**Modify `conf/raspberry-config.yml`** — add:
```
keycloak_version: "25.0.2"
keycloak_home: "{{ remote_directory }}/keycloak-{{ keycloak_version }}"
keycloak_hostname: "{{ inventory_hostname }}"
keycloak_user: keycloak
keycloak_group: keycloak
java_home: "/usr/lib/jvm/java-17-openjdk-arm64"   # fallback only; real value is discovered at runtime
```
Remove `remote_keycloak_utils_dir` (no longer referenced). Refactor `keycloak_url`/`keycloak_zip` to interpolate `{{ keycloak_version }}`.

**Wrapper scripts** (`keycloak/deployment/raspberry/`), keeping the existing one-line convention:
- New: `configure-keycloak.sh` → `ansible-playbook keycloak-configure.yaml`
- New: `harden-keycloak.sh` → `ansible-playbook keycloak-harden.yaml` (never called by anything else — explicit manual step only)
- New: `verify-keycloak.sh` → `ansible-playbook keycloak-verify.yaml`
- `install-keycloak.sh` becomes the "fully automated" orchestrator: runs `raspberry.yaml` → `keycloak.yaml` → `keycloak-configure.yaml` → `keycloak-verify.yaml` in sequence with `set -e`, so one command takes a bare Pi to a running, verified, HTTPS-only Keycloak. Discrete step scripts remain available for targeted re-runs/debugging.
- `uninstall-keycloak.sh` unchanged (still calls the now-fixed `keycloak-uninstall.yaml`).

**`README.md`**: replace the `[TODO]` under "Install and run Keycloak as server on a Raspberry Pi box" (lines 66-67) with a short section describing the one-command automated flow, the discrete step scripts, the manual harden-after-UI-password-change step, and where to adjust vars (`conf/raspberry-config.yml`) — matching the surrounding `####` prose style.

## Verification
- `ansible-playbook --syntax-check` on every modified/new `.yaml` file.
- `ansible-lint` if available locally (not currently in repo tooling — run ad hoc, don't add CI for it unless asked).
- Actual run against the `raspberry01` host (if reachable): `./install-keycloak.sh`, then confirm via `keycloak-verify.yaml`'s assertions (service active, HTTPS 200/302/303, port 8080 closed) and manually via `curl -k https://raspberry01:8443/` / `curl http://raspberry01:8080/` (expect refusal) as the original requirements doc specifies.
- Manually log into `https://raspberry01:8443/admin`, change the admin password, then run `./harden-keycloak.sh` and re-run `./verify-keycloak.sh`; confirm `grep KEYCLOAK_ADMIN /etc/systemd/system/keycloak.service` on the Pi returns nothing after hardening.
- Re-run `./install-keycloak.sh` a second time end-to-end after hardening to confirm the sentinel-file idempotency guard prevents the admin credentials from reappearing in the unit file.
