#!/bin/bash
# Copy the weekly Keycloak backups (keycloak-backup.timer) from raspberry01 to this Mac, encrypt them with sops
# and remove them from raspberry01: fetch-keycloak-backups.sh [-y]
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
SOPS_CRYPT=$WINDFIRE_SECURITY_HOME/sops/sops-crypt.sh
# Same folder as backup-keycloak.sh, must match local_backup_dir in raspberry/conf/keycloak-backup-config.yml
LOCAL_BACKUP_DIR=$HOME/opt/keycloak/backup
LAST_FETCH_FILE=$LOCAL_BACKUP_DIR/.last-fetch
ASSUME_YES=false

usage()
{
    echo "Usage: $(basename "$0") [-y] [-h]"
    echo "  -y  Do not ask for confirmation"
}

while getopts ":yh" opt; do
    case "$opt" in
        y) ASSUME_YES=true ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

for cmd in ansible-playbook sops age-keygen; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}$cmd not found, install it first (e.g. brew install ansible sops age)${RESET}" >&2
        exit 1
    fi
done

if [[ "$ASSUME_YES" != true ]]; then
    echo -e "${YELLOW}The weekly backups on raspberry01 are copied to ${LOCAL_BACKUP_DIR}, encrypted with sops and removed from raspberry01${RESET}"
    read -r -p "Fetch the Keycloak backups now? [y/N]: " CONFIRMATION
    if [[ ! "$CONFIRMATION" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}Not confirmed, nothing done${RESET}"
        exit 1
    fi
fi

# The playbook appends each Mac copy here once it is verified and removed from raspberry01
rm -f "$LAST_FETCH_FILE"
FAILED=false
echo -e "${BLU}Fetching the Keycloak backups from raspberry01 (inventory group identitymanager) to ${LOCAL_BACKUP_DIR} ...${RESET}"
if ! ansible-playbook -K raspberry/keycloak-backup-fetch.yaml -e local_backup_dir="$LOCAL_BACKUP_DIR"; then
    echo -e "${RED}Fetch failed, see the playbook output above: the archives fetched before the failure are encrypted now${RESET}" >&2
    FAILED=true
fi

FETCHED=()
if [[ -f "$LAST_FETCH_FILE" ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && FETCHED+=("$line")
    done < "$LAST_FETCH_FILE"
fi
rm -f "$LAST_FETCH_FILE"

if [[ ${#FETCHED[@]} -eq 0 ]]; then
    [[ "$FAILED" == true ]] && exit 1
    echo -e "${GREEN}No new backup on raspberry01${RESET}"
    exit 0
fi

# Binary mode, round trip check, plain archive deleted only if the check passes
ENCRYPTED=()
for archive in "${FETCHED[@]}"; do
    echo -e "${BLU}Encrypting ${archive} with sops ...${RESET}"
    if [[ ! -f "$archive" ]] || ! "$SOPS_CRYPT" -e -f "$archive" -r -y || [[ -f "$archive" ]]; then
        echo -e "${RED}Encryption failed or not verified: ${archive} is still in plain text (mode 0600), encrypt it with${RESET}" >&2
        echo "    $SOPS_CRYPT -e -f \"$archive\" -r" >&2
        FAILED=true
    else
        ENCRYPTED+=("${archive}${SOPS_ENCRYPTED_SUFFIX}")
    fi
done

echo
if [[ ${#ENCRYPTED[@]} -gt 0 ]]; then
    echo -e "${GREEN}Keycloak backups copied from raspberry01:${RESET}"
    printf '    %s\n' "${ENCRYPTED[@]}"
    echo "To decrypt one:"
    echo "    $SOPS_CRYPT -d -f <file>${SOPS_ENCRYPTED_SUFFIX}"
fi
[[ "$FAILED" == true ]] && exit 1
exit 0
