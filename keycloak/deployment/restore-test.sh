#!/bin/bash
# Restore a Keycloak backup (backup-keycloak.sh or fetch-keycloak-backups.sh) into a scratch Keycloak on this Mac
# and check that its realms, the windfire clients and users are there:
#   restore-test.sh [-f <backup>] [-m import|data] [-p <port>] [-k] [-c] [-h]
# Never contacts raspberry01, never writes to KEYCLOAK_HOME (common.sh): the scratch install is a copy of it.
cd "$(dirname "$0")" || exit 1
source ../../common.sh
SOPS_CRYPT=$WINDFIRE_SECURITY_HOME/sops/sops-crypt.sh
# Same folder as backup-keycloak.sh and fetch-keycloak-backups.sh
LOCAL_BACKUP_DIR=$HOME/opt/keycloak/backup
# Holds the decrypted backup (secrets in plain text) and the scratch Keycloak: mode 0700, removed after the test
WORK_DIR=$HOME/opt/keycloak/restore-test
PID_FILE=$WORK_DIR/keycloak.pid
ADMIN_USER=restore-test-admin
CHECK_REALM=windfire
DEFAULT_PORT=18080
MANAGEMENT_PORT=19000
START_TIMEOUT_SECONDS=180
BACKUP_FILE=
MODE=import
PORT=$DEFAULT_PORT
KEEP=false
CLEAN=false
WORK_DIR_CREATED=false
SUCCESS=false

usage()
{
    echo "Usage: $(basename "$0") [-f <backup>] [-m import|data] [-p <port>] [-k] [-c] [-h]"
    echo "  -f  Backup to restore (default: the newest keycloak-*-backup-*.tgz${SOPS_ENCRYPTED_SUFFIX} in ${LOCAL_BACKUP_DIR})"
    echo "  -m  import: kc.sh import of the realm export (default); data: copy of the raw H2 data/ (same version only)"
    echo "  -p  HTTP port of the scratch Keycloak (default: ${DEFAULT_PORT}, management port ${MANAGEMENT_PORT})"
    echo "  -k  Keep the scratch Keycloak running and ${WORK_DIR} after the checks"
    echo "  -c  Stop a kept scratch Keycloak and remove ${WORK_DIR}, then exit"
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
    [[ -f "$PID_FILE" ]] || return 0
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
    # Fixed path, never derived from input
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

while getopts ":f:m:p:kch" opt; do
    case "$opt" in
        f) BACKUP_FILE="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        k) KEEP=true ;;
        c) CLEAN=true ;;
        h) usage; exit 0 ;;
        :) usage >&2; fail "Option -$OPTARG requires an argument" ;;
        *) usage >&2; exit 1 ;;
    esac
done

if [[ "$CLEAN" == true ]]; then
    if [[ ! -d "$WORK_DIR" ]]; then
        echo -e "${GREEN}Nothing to clean, ${WORK_DIR} does not exist${RESET}"
        exit 0
    fi
    stopScratchKeycloak
    removeWorkDir
    echo -e "${GREEN}Scratch Keycloak stopped, ${WORK_DIR} removed${RESET}"
    exit 0
fi

[[ "$MODE" == import || "$MODE" == data ]] || fail "Invalid mode: $MODE (expected import or data)"
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -le 65535 && "$PORT" -ne "$MANAGEMENT_PORT" ]] \
    || fail "Invalid port: $PORT (expected 1024-65535, not ${MANAGEMENT_PORT})"

#############################
##### Pre-flight checks #####
#############################
for cmd in sops age-keygen python3 rsync lsof curl openssl; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, install it first (e.g. brew install sops age python rsync)"
done
checkJava || exit 1
[[ -x "$KEYCLOAK_HOME/bin/kc.sh" ]] \
    || fail "No Keycloak in ${KEYCLOAK_HOME} (KEYCLOAK_HOME in common.sh): install it with install-keycloak.sh 2"
[[ -e "$WORK_DIR" ]] \
    && fail "${WORK_DIR} exists (scratch Keycloak kept with -k, or an interrupted run): remove it with $(basename "$0") -c"

if [[ -z "$BACKUP_FILE" ]]; then
    BACKUP_FILE=$(newestBackup)
    [[ -n "$BACKUP_FILE" ]] || fail "No backup (keycloak-*-backup-*.tgz${SOPS_ENCRYPTED_SUFFIX}) in ${LOCAL_BACKUP_DIR}: make one with backup-keycloak.sh or copy the weekly ones with fetch-keycloak-backups.sh"
fi
[[ -f "$BACKUP_FILE" ]] || fail "Backup not found: $BACKUP_FILE"
[[ "$BACKUP_FILE" == *"$SOPS_ENCRYPTED_SUFFIX" ]] || fail "Expected a sops-encrypted backup (*${SOPS_ENCRYPTED_SUFFIX}): $BACKUP_FILE"

for p in "$PORT" "$MANAGEMENT_PORT"; do
    portInUse "$p" && fail "Port $p is already in use on this Mac: stop what listens there or choose another port with -p"
done

###########################################
##### Decrypt and unpack the backup   #####
###########################################
umask 077
trap onExit EXIT
trap 'exit 130' INT TERM
mkdir -m 0700 -p "$WORK_DIR" || fail "Cannot create ${WORK_DIR}"
WORK_DIR_CREATED=true

echo -e "${BLU}Decrypting ${BACKUP_FILE} to ${WORK_DIR} ...${RESET}"
"$SOPS_CRYPT" -d -f "$BACKUP_FILE" -o "$WORK_DIR/backup.tgz" -y >/dev/null || fail "Decryption failed"
mkdir "$WORK_DIR/backup"
tar xzf "$WORK_DIR/backup.tgz" -C "$WORK_DIR/backup" || fail "Cannot unpack the backup archive"
rm -f "$WORK_DIR/backup.tgz"

BACKUP_ROOT=$(find "$WORK_DIR/backup" -mindepth 1 -maxdepth 1 -type d -name 'kc-backup-*' | head -n 1)
[[ -n "$BACKUP_ROOT" && -f "$BACKUP_ROOT/MANIFEST.txt" ]] || fail "Not a Keycloak backup: no kc-backup-*/MANIFEST.txt in the archive"
EXPORT_DIR=$BACKUP_ROOT/export
[[ -f "$EXPORT_DIR/${CHECK_REALM}-realm.json" ]] || fail "The backup has no ${CHECK_REALM} realm (export/${CHECK_REALM}-realm.json)"

BACKUP_VERSION=$(sed -n 's/^Keycloak version: *\([0-9][0-9.]*\) (\(.*\))$/\1/p' "$BACKUP_ROOT/MANIFEST.txt")
BACKUP_HOME=$(sed -n 's/^Keycloak version: *\([0-9][0-9.]*\) (\(.*\))$/\2/p' "$BACKUP_ROOT/MANIFEST.txt")
BACKUP_DATE=$(sed -n 's/^Date: *//p' "$BACKUP_ROOT/MANIFEST.txt")
BACKUP_REALMS=$(sed -n 's/^Realms: *//p' "$BACKUP_ROOT/MANIFEST.txt")
[[ -n "$BACKUP_VERSION" && -n "$BACKUP_HOME" ]] || fail "Cannot read the Keycloak version from MANIFEST.txt"
echo "  Backup of ${BACKUP_DATE}, Keycloak ${BACKUP_VERSION}, realms: ${BACKUP_REALMS}"

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

##################################################
##### Scratch Keycloak, separate KEYCLOAK_HOME #####
##################################################
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

####################################################
##### Check realms, clients, users, secrets    #####
####################################################
echo -e "${BLU}Checking the restored Keycloak against the export ...${RESET}"
KC_URL="http://localhost:${PORT}" KC_ADMIN="$ADMIN_USER" EXPORT_DIR="$EXPORT_DIR" CHECK_REALM="$CHECK_REALM" \
python3 -I - <<'PYTHON'
import glob, json, os, sys, urllib.parse, urllib.request

base = os.environ["KC_URL"]
realm = os.environ["CHECK_REALM"]
export_dir = os.environ["EXPORT_DIR"]
failures = 0


def call(path, token=None, data=None):
    request = urllib.request.Request(base + path, data=data)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=30) as response:
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
        "password": os.environ["RESTORE_ADMIN_PASSWORD"],
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
CHECK_RC=$?
[[ $CHECK_RC -eq 0 ]] || fail "The restored Keycloak does not match the backup (see FAIL above)"

SUCCESS=true
echo
echo -e "${GREEN}Backup ${BACKUP_FILE} restored (mode ${MODE}) and checked: realms ${BACKUP_REALMS}${RESET}"
if [[ "$KEEP" == true ]]; then
    echo "Scratch Keycloak kept running (PID $(cat "$PID_FILE")):"
    echo "    Admin Console: http://localhost:${PORT}/admin, user ${ADMIN_USER}, password in ${WORK_DIR}/admin-password"
    echo "    Stop it and remove ${WORK_DIR} (decrypted backup) with: $0 -c"
else
    echo "Stopping the scratch Keycloak and removing ${WORK_DIR} ..."
fi
exit 0
