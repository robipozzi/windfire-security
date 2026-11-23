#!/bin/bash
# Restore a Keycloak backup (backup-keycloak.sh or fetch-keycloak-backups.sh):
#   restore-keycloak.sh [-e localhost|raspberry] [-f <backup>] [-m import|data] [-p <port>] [-k] [-c] [-y] [-h]
#   localhost: into a scratch Keycloak on this Mac, then check that its realms, the windfire clients and users are there.
#              Never contacts raspberry01, never writes to KEYCLOAK_HOME (common.sh): the scratch install is a copy of it.
#   raspberry: into the Keycloak running on raspberry01 (raspberry/keycloak-restore.yaml), then the same checks over HTTPS.
#              The current database is kept on the Pi as data.before-restore-<stamp> until you remove it with -c.
cd "$(dirname "$0")" || exit 1
source ../../common.sh
SOPS_CRYPT=$WINDFIRE_SECURITY_HOME/sops/sops-crypt.sh
# Same folder as backup-keycloak.sh and fetch-keycloak-backups.sh
LOCAL_BACKUP_DIR=$HOME/opt/keycloak/backup
# Hold the decrypted backup (secrets in plain text), and the scratch Keycloak for localhost: mode 0700, removed after the run
LOCALHOST_WORK_DIR=$HOME/opt/keycloak/restore-test
RASPBERRY_WORK_DIR=$HOME/opt/keycloak/restore-raspberry
WORK_DIR=
PID_FILE=
ADMIN_USER=restore-test-admin
CHECK_REALM=windfire
DEFAULT_PORT=18080
MANAGEMENT_PORT=19000
START_TIMEOUT_SECONDS=180
# raspberry01: inventory group identitymanager, version expected to run there (raspberry/conf/raspberry-config.yml)
RASPBERRY_HOST=raspberry01
RASPBERRY_URL=https://${RASPBERRY_HOST}:${KEYCLOAK_TLS_SERVER_PORT}
RASPBERRY_VERSION=$(sed -n 's/^keycloak_version: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' raspberry/conf/raspberry-config.yml)
RASPBERRY_CA_FILE=$KEYCLOAK_DEFAULT_TRUSTSTORE_DIR/$KEYCLOAK_ROOT_CA_CERTIFICATE
DEFAULT_RASPBERRY_ADMIN=admin
ENVIRONMENT=
BACKUP_FILE=
MODE=
PORT=
KEEP=false
CLEAN=false
ASSUME_YES=false
WORK_DIR_CREATED=false
SUCCESS=false

usage()
{
    echo "Usage: $(basename "$0") [-e localhost|raspberry] [-f <backup>] [-m import|data] [-p <port>] [-k] [-c] [-y] [-h]"
    echo "  -e  Where to restore: localhost (scratch Keycloak on this Mac) or raspberry (${RASPBERRY_HOST}); asked if not given"
    echo "  -f  Backup to restore (default: the newest keycloak-*-backup-*.tgz${SOPS_ENCRYPTED_SUFFIX} in ${LOCAL_BACKUP_DIR})"
    echo "  -m  import: kc.sh import of the realm export; data: copy of the raw H2 data/ (same version only)"
    echo "      Default: import on localhost; on raspberry data if the backup is Keycloak ${RASPBERRY_VERSION}, otherwise import"
    echo "  -p  localhost only: HTTP port of the scratch Keycloak (default: ${DEFAULT_PORT}, management port ${MANAGEMENT_PORT})"
    echo "  -k  localhost only: keep the scratch Keycloak running and ${LOCALHOST_WORK_DIR} after the checks"
    echo "  -c  localhost: stop a kept scratch Keycloak and remove ${LOCALHOST_WORK_DIR}"
    echo "      raspberry: remove data.before-restore-* and restore folders left on ${RASPBERRY_HOST}, and ${RASPBERRY_WORK_DIR}"
    echo "  -y  raspberry only: do not ask for confirmation before restoring or cleaning up"
}

fail()
{
    echo -e "${RED}$*${RESET}" >&2
    exit 1
}

# Stop the scratch Keycloak started by this script (its own process group), if any
stopScratchKeycloak()
{
    local pid i
    [[ -n "$PID_FILE" && -f "$PID_FILE" ]] || return 0
    pid=$(cat "$PID_FILE")
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        echo -e "${BLU}Stopping the scratch Keycloak (PID ${pid}) ...${RESET}"
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for i in $(seq 1 30); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -KILL -- "-$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
}

removeWorkDir()
{
    # Fixed paths, never derived from input
    [[ "$WORK_DIR" == "$LOCALHOST_WORK_DIR" || "$WORK_DIR" == "$RASPBERRY_WORK_DIR" ]] || return 0
    [[ -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}

onExit()
{
    local rc=$?
    [[ "$WORK_DIR_CREATED" == true ]] || exit $rc
    if [[ "$KEEP" == true && "$SUCCESS" == true ]]; then
        exit $rc
    fi
    if [[ "$SUCCESS" != true && -f "$WORK_DIR/keycloak.log" ]]; then
        echo -e "${YELLOW}Last lines of the scratch Keycloak log:${RESET}" >&2
        tail -n 20 "$WORK_DIR/keycloak.log" >&2
    fi
    stopScratchKeycloak
    removeWorkDir
    [[ "$SUCCESS" == true ]] || echo -e "${YELLOW}${WORK_DIR} removed (it held the decrypted backup)${RESET}" >&2
    exit $rc
}

# Newest backup by the <stamp> after -backup-, so archives of different versions still sort by date
newestBackup()
{
    local f stamp best="" best_stamp=""
    for f in "$LOCAL_BACKUP_DIR"/keycloak-*-backup-*.tgz"$SOPS_ENCRYPTED_SUFFIX"; do
        [[ -f "$f" ]] || continue
        stamp=${f##*-backup-}
        stamp=${stamp%%.tgz*}
        if [[ -z "$best" || "$stamp" > "$best_stamp" ]]; then
            best=$f
            best_stamp=$stamp
        fi
    done
    echo "$best"
}

# True if version $1 <= version $2
versionLessOrEqual()
{
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" == "$1" ]]
}

portInUse()
{
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1
}

confirm()
{
    local answer
    read -r -p "$1 [y/N]: " answer
    [[ "$answer" =~ ^[yY]$ ]]
}

# -f, or the newest backup in LOCAL_BACKUP_DIR
selectBackup()
{
    if [[ -z "$BACKUP_FILE" ]]; then
        BACKUP_FILE=$(newestBackup)
        [[ -n "$BACKUP_FILE" ]] || fail "No backup (keycloak-*-backup-*.tgz${SOPS_ENCRYPTED_SUFFIX}) in ${LOCAL_BACKUP_DIR}: make one with backup-keycloak.sh or copy the weekly ones with fetch-keycloak-backups.sh"
    fi
    [[ -f "$BACKUP_FILE" ]] || fail "Backup not found: $BACKUP_FILE"
    [[ "$BACKUP_FILE" == *"$SOPS_ENCRYPTED_SUFFIX" ]] || fail "Expected a sops-encrypted backup (*${SOPS_ENCRYPTED_SUFFIX}): $BACKUP_FILE"
}

# Create WORK_DIR (0700, removed on exit), decrypt and unpack BACKUP_FILE in it and read its MANIFEST.txt.
# $1 = true keeps the decrypted archive as WORK_DIR/backup.tgz (raspberry: the playbook copies it to the Pi)
decryptBackup()
{
    umask 077
    trap onExit EXIT
    trap 'exit 130' INT TERM
    mkdir -m 0700 -p "$WORK_DIR" || fail "Cannot create ${WORK_DIR}"
    WORK_DIR_CREATED=true

    echo -e "${BLU}Decrypting ${BACKUP_FILE} to ${WORK_DIR} ...${RESET}"
    "$SOPS_CRYPT" -d -f "$BACKUP_FILE" -o "$WORK_DIR/backup.tgz" -y >/dev/null || fail "Decryption failed"
    mkdir "$WORK_DIR/backup"
    tar xzf "$WORK_DIR/backup.tgz" -C "$WORK_DIR/backup" || fail "Cannot unpack the backup archive"
    [[ "$1" == true ]] || rm -f "$WORK_DIR/backup.tgz"

    BACKUP_ROOT=$(find "$WORK_DIR/backup" -mindepth 1 -maxdepth 1 -type d -name 'kc-backup-*' | head -n 1)
    [[ -n "$BACKUP_ROOT" && -f "$BACKUP_ROOT/MANIFEST.txt" ]] || fail "Not a Keycloak backup: no kc-backup-*/MANIFEST.txt in the archive"
    EXPORT_DIR=$BACKUP_ROOT/export
    [[ -f "$EXPORT_DIR/${CHECK_REALM}-realm.json" ]] || fail "The backup has no ${CHECK_REALM} realm (export/${CHECK_REALM}-realm.json)"

    BACKUP_VERSION=$(sed -n 's/^Keycloak version: *\([0-9][0-9.]*\) (\(.*\))$/\1/p' "$BACKUP_ROOT/MANIFEST.txt")
    BACKUP_HOME=$(sed -n 's/^Keycloak version: *\([0-9][0-9.]*\) (\(.*\))$/\2/p' "$BACKUP_ROOT/MANIFEST.txt")
    BACKUP_DATE=$(sed -n 's/^Date: *//p' "$BACKUP_ROOT/MANIFEST.txt")
    BACKUP_REALMS=$(sed -n 's/^Realms: *//p' "$BACKUP_ROOT/MANIFEST.txt")
    BACKUP_HOST=$(sed -n 's/^Host: *//p' "$BACKUP_ROOT/MANIFEST.txt")
    [[ -n "$BACKUP_VERSION" && -n "$BACKUP_HOME" ]] || fail "Cannot read the Keycloak version from MANIFEST.txt"
    echo "  Backup of ${BACKUP_DATE}, Keycloak ${BACKUP_VERSION}, realms: ${BACKUP_REALMS}"
}

# Compare the Keycloak at KC_URL with the realm export in EXPORT_DIR: realms, CHECK_REALM clients, client secrets,
# users and passwords. Admin login (master realm) from KC_ADMIN/KC_ADMIN_PASSWORD, optional CA file in KC_CA_FILE
checkKeycloak()
{
    KC_URL="$1" KC_ADMIN="$2" KC_CA_FILE="$3" EXPORT_DIR="$EXPORT_DIR" CHECK_REALM="$CHECK_REALM" \
    python3 -I - <<'PYTHON'
import glob, json, os, ssl, sys, urllib.parse, urllib.request

base = os.environ["KC_URL"]
realm = os.environ["CHECK_REALM"]
export_dir = os.environ["EXPORT_DIR"]
ca_file = os.environ.get("KC_CA_FILE")
context = ssl.create_default_context(cafile=ca_file) if ca_file else None
failures = 0


def call(path, token=None, data=None):
    request = urllib.request.Request(base + path, data=data)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=30, context=context) as response:
        return json.load(response)


def check(ok, label, detail=""):
    global failures
    if not ok:
        failures += 1
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f": {detail}" if detail else ""))


def diff(expected, actual):
    parts = []
    if expected - actual:
        parts.append("missing " + ", ".join(sorted(expected - actual)))
    if actual - expected:
        parts.append("extra " + ", ".join(sorted(actual - expected)))
    return "; ".join(parts)


def regular_users(users):
    return {u["username"] for u in users if not u["username"].startswith("service-account-")}


token = call(
    "/realms/master/protocol/openid-connect/token",
    data=urllib.parse.urlencode({
        "grant_type": "password",
        "client_id": "admin-cli",
        "username": os.environ["KC_ADMIN"],
        "password": os.environ["KC_ADMIN_PASSWORD"],
    }).encode(),
)["access_token"]

exported = {}
for path in sorted(glob.glob(os.path.join(export_dir, "*-realm.json"))):
    with open(path) as f:
        rep = json.load(f)
    exported[rep["realm"]] = rep

server_realms = {r["realm"] for r in call("/admin/realms", token)}
check(set(exported) <= server_realms, f"realms {', '.join(sorted(exported))}", diff(set(exported), server_realms & set(exported)))

rep = exported[realm]
server_rep = call(f"/admin/realms/{realm}", token)
check(server_rep.get("enabled") == rep.get("enabled", True), f"{realm} enabled={server_rep.get('enabled')}")

exp_clients = {c["clientId"]: c for c in rep.get("clients", [])}
srv_clients = {c["clientId"]: c for c in call(f"/admin/realms/{realm}/clients?first=0&max=1000", token)}
check(set(exp_clients) == set(srv_clients), f"{realm} clients ({len(srv_clients)})", diff(set(exp_clients), set(srv_clients)))

# Confidential clients: same secret as exported (compared here, never printed)
secret_mismatch = []
for client_id, client in exp_clients.items():
    if client.get("publicClient") or client.get("bearerOnly") or not client.get("secret") or client_id not in srv_clients:
        continue
    server_secret = call(f"/admin/realms/{realm}/clients/{srv_clients[client_id]['id']}/client-secret", token).get("value")
    if server_secret != client["secret"]:
        secret_mismatch.append(client_id)
confidential = [c for c, v in exp_clients.items() if v.get("secret") and not v.get("publicClient") and not v.get("bearerOnly")]
check(not secret_mismatch, f"{realm} client secrets ({len(confidential)} confidential clients)",
      ("differ: " + ", ".join(sorted(secret_mismatch))) if secret_mismatch else "")

exp_users = rep.get("users", [])
srv_users = call(f"/admin/realms/{realm}/users?first=0&max=10000&briefRepresentation=true", token)
check(regular_users(exp_users) == regular_users(srv_users), f"{realm} users ({len(regular_users(srv_users))}, service accounts excluded)",
      diff(regular_users(exp_users), regular_users(srv_users)))

# Users exported with a password still have one (the hashes were restored)
srv_ids = {u["username"]: u["id"] for u in srv_users}
no_password = []
with_password = [u["username"] for u in exp_users
                 if any(c.get("type") == "password" for c in u.get("credentials", [])) and u["username"] in srv_ids]
for username in with_password:
    creds = call(f"/admin/realms/{realm}/users/{srv_ids[username]}/credentials", token)
    if not any(c.get("type") == "password" for c in creds):
        no_password.append(username)
check(not no_password, f"{realm} passwords ({len(with_password)} users with a password)",
      ("missing for " + ", ".join(sorted(no_password))) if no_password else "")

sys.exit(1 if failures else 0)
PYTHON
}

selectEnvironment()
{
    while [[ -z "$ENVIRONMENT" ]]; do
        echo -e "${BLU}Select where to restore Keycloak :${RESET}"
        echo -e "${GREEN}1. Raspberry (${RASPBERRY_HOST})${RESET}"
        echo -e "${GREEN}2. localhost (scratch Keycloak on this Mac)${RESET}"
        read -r ENVIRONMENT
        case "$ENVIRONMENT" in
            1) ENVIRONMENT=raspberry ;;
            2) ENVIRONMENT=localhost ;;
            *) echo -e "${RED}No valid option selected${RESET}"; ENVIRONMENT= ;;
        esac
    done
}

#####################################################################
##### localhost: scratch Keycloak on this Mac (restore test)    #####
#####################################################################
cleanLocalhost()
{
    if [[ ! -d "$WORK_DIR" ]]; then
        echo -e "${GREEN}Nothing to clean, ${WORK_DIR} does not exist${RESET}"
        exit 0
    fi
    stopScratchKeycloak
    removeWorkDir
    echo -e "${GREEN}Scratch Keycloak stopped, ${WORK_DIR} removed${RESET}"
    exit 0
}

restoreLocalhost()
{
    MODE=${MODE:-import}
    PORT=${PORT:-$DEFAULT_PORT}
    [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -le 65535 && "$PORT" -ne "$MANAGEMENT_PORT" ]] \
        || fail "Invalid port: $PORT (expected 1024-65535, not ${MANAGEMENT_PORT})"

    ##### Pre-flight checks #####
    for cmd in sops age-keygen python3 rsync lsof curl openssl; do
        command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, install it first (e.g. brew install sops age python rsync)"
    done
    checkJava || exit 1
    [[ -x "$KEYCLOAK_HOME/bin/kc.sh" ]] \
        || fail "No Keycloak in ${KEYCLOAK_HOME} (KEYCLOAK_HOME in common.sh): install it with install-keycloak.sh 2"
    [[ -e "$WORK_DIR" ]] \
        && fail "${WORK_DIR} exists (scratch Keycloak kept with -k, or an interrupted run): remove it with $(basename "$0") -e localhost -c"

    selectBackup

    for p in "$PORT" "$MANAGEMENT_PORT"; do
        portInUse "$p" && fail "Port $p is already in use on this Mac: stop what listens there or choose another port with -p"
    done

    ##### Decrypt and unpack the backup #####
    decryptBackup false

    if [[ "$MODE" == data ]]; then
        [[ "$BACKUP_VERSION" == "$KEYCLOAK_VERSION" ]] \
            || fail "Mode data needs the same version: the backup is Keycloak ${BACKUP_VERSION}, KEYCLOAK_VERSION is ${KEYCLOAK_VERSION} (use -m import)"
        [[ -d "$BACKUP_ROOT/files${BACKUP_HOME}/data" ]] || fail "The backup has no files${BACKUP_HOME}/data"
    else
        versionLessOrEqual "$BACKUP_VERSION" "$KEYCLOAK_VERSION" \
            || fail "The backup is Keycloak ${BACKUP_VERSION}, newer than KEYCLOAK_VERSION ${KEYCLOAK_VERSION}: an export cannot be imported into an older version"
        [[ "$BACKUP_VERSION" == "$KEYCLOAK_VERSION" ]] \
            || echo -e "${YELLOW}The backup is Keycloak ${BACKUP_VERSION}, the scratch install ${KEYCLOAK_VERSION}: the import migrates it${RESET}"
    fi

    ##### Scratch Keycloak, separate KEYCLOAK_HOME #####
    SCRATCH_HOME=$WORK_DIR/keycloak-$KEYCLOAK_VERSION
    echo -e "${BLU}Copying ${KEYCLOAK_HOME} to ${SCRATCH_HOME} (without data/ and conf/tls/) ...${RESET}"
    rsync -a --exclude '/data/' --exclude '/conf/tls/' "$KEYCLOAK_HOME/" "$SCRATCH_HOME/" || fail "Cannot copy ${KEYCLOAK_HOME}"

    if [[ "$MODE" == data ]]; then
        echo -e "${BLU}Copying the raw database files${BACKUP_HOME}/data to ${SCRATCH_HOME}/data ...${RESET}"
        cp -R "$BACKUP_ROOT/files${BACKUP_HOME}/data" "$SCRATCH_HOME/data" || fail "Cannot copy data/"
        # H2 credentials of databases created before Keycloak 26.2 (keycloak-upgrade.yaml writes them to keycloak.conf)
        BACKUP_CONF=$BACKUP_ROOT/files/etc/keycloak/keycloak.conf
        if [[ -f "$BACKUP_CONF" ]]; then
            DB_USERNAME=$(sed -n 's/^db-username=//p' "$BACKUP_CONF" | tail -n 1)
            DB_PASSWORD=$(sed -n 's/^db-password=//p' "$BACKUP_CONF" | tail -n 1)
            [[ -n "$DB_USERNAME" ]] && export KC_DB_USERNAME="$DB_USERNAME"
            [[ -n "$DB_PASSWORD" ]] && export KC_DB_PASSWORD="$DB_PASSWORD"
        fi
    else
        echo -e "${BLU}Importing every realm from export/ (kc.sh import --override true) ...${RESET}"
        "$SCRATCH_HOME/bin/kc.sh" import --dir "$EXPORT_DIR" --override true >"$WORK_DIR/import.log" 2>&1 \
            || { tail -n 20 "$WORK_DIR/import.log" >&2; fail "kc.sh import failed, see the log above"; }
    fi

    # Throwaway admin in master, whatever the admin password on raspberry01 is: password only in the environment
    RESTORE_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    export RESTORE_ADMIN_PASSWORD
    printf '%s\n' "$RESTORE_ADMIN_PASSWORD" >"$WORK_DIR/admin-password"
    echo -e "${BLU}Adding the temporary admin ${ADMIN_USER} to the master realm ...${RESET}"
    "$SCRATCH_HOME/bin/kc.sh" bootstrap-admin user --username "$ADMIN_USER" --password:env RESTORE_ADMIN_PASSWORD --no-prompt \
        >"$WORK_DIR/bootstrap-admin.log" 2>&1 \
        || { tail -n 20 "$WORK_DIR/bootstrap-admin.log" >&2; fail "kc.sh bootstrap-admin failed, see the log above"; }

    START_OPTIONS=(--http-port="$PORT" --http-management-port="$MANAGEMENT_PORT")
    # File vault of raspberry01 (vault=file in keycloak.conf): ${vault.<key>} references resolve as on the Pi
    BACKUP_VAULT_DIR=$BACKUP_ROOT/files/etc/keycloak/vault
    if [[ -d "$BACKUP_VAULT_DIR" ]]; then
        START_OPTIONS+=(--vault=file --vault-dir="$BACKUP_VAULT_DIR")
    fi
    echo -e "${BLU}Starting the scratch Keycloak on http://localhost:${PORT} (log: ${WORK_DIR}/keycloak.log) ...${RESET}"
    # Own process group (set -m), so stopScratchKeycloak stops kc.sh and its JVM together
    set -m
    nohup "$SCRATCH_HOME/bin/kc.sh" start-dev "${START_OPTIONS[@]}" >"$WORK_DIR/keycloak.log" 2>&1 </dev/null &
    echo $! >"$PID_FILE"
    set +m

    STATUS=
    for _ in $(seq 1 $(( START_TIMEOUT_SECONDS / 5 ))); do
        kill -0 "$(cat "$PID_FILE")" 2>/dev/null || fail "The scratch Keycloak exited during startup"
        STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/realms/${CHECK_REALM}/" || true)
        [[ "$STATUS" == 200 ]] && break
        sleep 5
    done
    [[ "$STATUS" == 200 ]] || fail "http://localhost:${PORT}/realms/${CHECK_REALM}/ did not answer 200 within ${START_TIMEOUT_SECONDS}s (last HTTP code ${STATUS:-none})"

    ##### Check realms, clients, users, secrets #####
    echo -e "${BLU}Checking the restored Keycloak against the export ...${RESET}"
    KC_ADMIN_PASSWORD="$RESTORE_ADMIN_PASSWORD" checkKeycloak "http://localhost:${PORT}" "$ADMIN_USER" "" \
        || fail "The restored Keycloak does not match the backup (see FAIL above)"

    SUCCESS=true
    echo
    echo -e "${GREEN}Backup ${BACKUP_FILE} restored (mode ${MODE}) and checked: realms ${BACKUP_REALMS}${RESET}"
    if [[ "$KEEP" == true ]]; then
        echo "Scratch Keycloak kept running (PID $(cat "$PID_FILE")):"
        echo "    Admin Console: http://localhost:${PORT}/admin, user ${ADMIN_USER}, password in ${WORK_DIR}/admin-password"
        echo "    Stop it and remove ${WORK_DIR} (decrypted backup) with: $0 -e localhost -c"
    else
        echo "Stopping the scratch Keycloak and removing ${WORK_DIR} ..."
    fi
    exit 0
}

#############################################################
##### raspberry: the Keycloak running on raspberry01    #####
#############################################################
runRestorePlaybook()
{
    ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg runWithAnsibleSshKey ansible-playbook -K raspberry/keycloak-restore.yaml "$@"
}

cleanRaspberry()
{
    command -v ansible-playbook >/dev/null 2>&1 || fail "ansible-playbook not found, install it first (e.g. brew install ansible)"
    if [[ "$ASSUME_YES" != true ]]; then
        echo -e "${YELLOW}The database saved before the last restore (data.before-restore-*) and any restore folder left on ${RASPBERRY_HOST} are removed${RESET}"
        confirm "Remove them now?" || { echo -e "${YELLOW}Not confirmed, nothing done${RESET}"; exit 1; }
    fi
    removeWorkDir
    echo -e "${BLU}Cleaning up the restore leftovers on ${RASPBERRY_HOST} ...${RESET}"
    runRestorePlaybook -e restore_action=cleanup || fail "Clean-up failed, see the playbook output above"
    echo -e "${GREEN}Restore leftovers removed from ${RASPBERRY_HOST}${RESET}"
    exit 0
}

restoreRaspberry()
{
    local answer restore_config=false backup_stamp admin_user check_rc

    [[ -z "$PORT" ]] || fail "-p applies to localhost only"
    [[ "$KEEP" != true ]] || fail "-k applies to localhost only"

    ##### Pre-flight checks #####
    for cmd in ansible-playbook sops age-keygen python3; do
        command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, install it first (e.g. brew install ansible sops age python)"
    done
    [[ -f "$RASPBERRY_CA_FILE" ]] || fail "No Windfire Keycloak Root CA certificate in ${RASPBERRY_CA_FILE} (needed to check ${RASPBERRY_URL})"
    [[ -n "$RASPBERRY_VERSION" ]] || fail "Cannot read keycloak_version from raspberry/conf/raspberry-config.yml"
    [[ -e "$WORK_DIR" ]] \
        && fail "${WORK_DIR} exists (an interrupted run): remove it with $(basename "$0") -e raspberry -c"

    selectBackup

    ##### Gate: the same backup restored and checked on this Mac first #####
    read -r -p "Test this backup on the Mac first (scratch Keycloak, ${RASPBERRY_HOST} not touched)? [Y/n]: " answer
    if [[ ! "$answer" =~ ^[nN]$ ]]; then
        echo -e "${BLU}Testing ${BACKUP_FILE} on this Mac ...${RESET}"
        "$0" -e localhost -f "$BACKUP_FILE" || fail "The test on the Mac failed: ${RASPBERRY_HOST} was not touched"
        echo
    else
        echo -e "${YELLOW}Test on the Mac skipped${RESET}"
    fi

    ##### Decrypt, keep the archive for the playbook #####
    decryptBackup true
    backup_stamp=${BACKUP_ROOT##*/kc-backup-}
    [[ "$backup_stamp" =~ ^[0-9]{8}-[0-9]{6}$ ]] || fail "Unexpected backup folder name: $(basename "$BACKUP_ROOT")"
    echo "  Backed up from ${BACKUP_HOST:-unknown host} (${BACKUP_HOME})"

    if [[ -z "$MODE" ]]; then
        [[ "$BACKUP_VERSION" == "$RASPBERRY_VERSION" ]] && MODE=data || MODE=import
    fi
    if [[ "$MODE" == data ]]; then
        [[ "$BACKUP_VERSION" == "$RASPBERRY_VERSION" ]] \
            || fail "Mode data needs the same version: the backup is Keycloak ${BACKUP_VERSION}, ${RASPBERRY_HOST} runs ${RASPBERRY_VERSION} (use -m import)"
        [[ -d "$BACKUP_ROOT/files${BACKUP_HOME}/data" ]] || fail "The backup has no files${BACKUP_HOME}/data"
        read -r -p "Restore /etc/keycloak (keycloak.conf, TLS, vault) and the systemd unit from the backup too? [y/N]: " answer
        [[ "$answer" =~ ^[yY]$ ]] && restore_config=true
    else
        versionLessOrEqual "$BACKUP_VERSION" "$RASPBERRY_VERSION" \
            || fail "The backup is Keycloak ${BACKUP_VERSION}, newer than ${RASPBERRY_VERSION} on ${RASPBERRY_HOST}: an export cannot be imported into an older version"
        # kc.sh build reads the build options (db, health, metrics, vault) from keycloak.conf
        restore_config=true
    fi

    echo
    echo -e "${RED}Keycloak on ${RASPBERRY_HOST} is stopped and its database replaced by this backup${RESET}"
    echo "  Mode:          ${MODE} ($([[ "$MODE" == data ]] && echo "raw H2 data/" || echo "kc.sh import of every realm, master included"))"
    echo "  Configuration: $([[ "$restore_config" == true ]] && echo "/etc/keycloak and the systemd unit restored from the backup" || echo "kept as it is on ${RASPBERRY_HOST}")"
    echo "  The current database is kept as data.before-restore-${backup_stamp}, and put back if the restore fails"
    if [[ "$ASSUME_YES" != true ]]; then
        confirm "Restore ${RASPBERRY_HOST} now?" || { echo -e "${YELLOW}Not confirmed, nothing done${RESET}"; exit 1; }
    fi

    ##### Restore on the Pi #####
    echo -e "${BLU}Restoring Keycloak on ${RASPBERRY_HOST} (inventory group identitymanager) ...${RESET}"
    runRestorePlaybook \
        -e restore_action=restore \
        -e local_archive="$WORK_DIR/backup.tgz" \
        -e backup_stamp="$backup_stamp" \
        -e backup_version="$BACKUP_VERSION" \
        -e backup_home="$BACKUP_HOME" \
        -e restore_mode="$MODE" \
        -e restore_config="$restore_config" \
        || fail "Restore failed, see the playbook output above"
    rm -f "$WORK_DIR/backup.tgz"

    ##### Check realms, clients, users, secrets over HTTPS #####
    echo
    echo -e "${BLU}Checking ${RASPBERRY_URL} against the export: log in as a master realm admin of the backup${RESET}"
    read -r -p "Admin username [${DEFAULT_RASPBERRY_ADMIN}]: " admin_user
    admin_user=${admin_user:-$DEFAULT_RASPBERRY_ADMIN}
    read -r -s -p "Admin password (empty to skip the check): " KC_ADMIN_PASSWORD
    echo
    if [[ -z "$KC_ADMIN_PASSWORD" ]]; then
        echo -e "${YELLOW}Check skipped: log in to ${RASPBERRY_URL}/admin and check Clients and Users of the ${CHECK_REALM} realm${RESET}"
    else
        export KC_ADMIN_PASSWORD
        checkKeycloak "$RASPBERRY_URL" "$admin_user" "$RASPBERRY_CA_FILE"
        check_rc=$?
        unset KC_ADMIN_PASSWORD
        [[ $check_rc -eq 0 ]] || fail "${RASPBERRY_HOST} does not match the backup (see FAIL above, or a wrong login). The previous database is kept there as <Keycloak home>/data.before-restore-${backup_stamp} (see the playbook summary above)"
    fi

    SUCCESS=true
    echo
    echo -e "${GREEN}Backup ${BACKUP_FILE} restored on ${RASPBERRY_HOST} (mode ${MODE}): realms ${BACKUP_REALMS}${RESET}"
    echo "Log in to an application (for example windfire-calendar) to validate the restore."
    if confirm "Restore validated? Remove the previous database (data.before-restore-${backup_stamp}) from ${RASPBERRY_HOST} now?"; then
        runRestorePlaybook -e restore_action=cleanup || fail "Clean-up failed, see the playbook output above"
    else
        echo "Remove it later, once the restore is validated, with: $0 -e raspberry -c"
    fi
    exit 0
}

while getopts ":e:f:m:p:kcyh" opt; do
    case "$opt" in
        e) ENVIRONMENT="$OPTARG" ;;
        f) BACKUP_FILE="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        k) KEEP=true ;;
        c) CLEAN=true ;;
        y) ASSUME_YES=true ;;
        h) usage; exit 0 ;;
        :) usage >&2; fail "Option -$OPTARG requires an argument" ;;
        *) usage >&2; exit 1 ;;
    esac
done

[[ -z "$ENVIRONMENT" || "$ENVIRONMENT" == localhost || "$ENVIRONMENT" == raspberry ]] \
    || fail "Invalid environment: $ENVIRONMENT (expected localhost or raspberry)"
[[ -z "$MODE" || "$MODE" == import || "$MODE" == data ]] || fail "Invalid mode: $MODE (expected import or data)"
selectEnvironment

if [[ "$ENVIRONMENT" == localhost ]]; then
    WORK_DIR=$LOCALHOST_WORK_DIR
    PID_FILE=$WORK_DIR/keycloak.pid
    [[ "$ASSUME_YES" != true ]] || fail "-y applies to raspberry only"
    [[ "$CLEAN" == true ]] && cleanLocalhost
    restoreLocalhost
else
    WORK_DIR=$RASPBERRY_WORK_DIR
    [[ "$CLEAN" == true ]] && cleanRaspberry
    restoreRaspberry
fi
