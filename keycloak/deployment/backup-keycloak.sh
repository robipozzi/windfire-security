#!/bin/bash
# Back up the Keycloak running on raspberry01 to this Mac and encrypt it with sops: backup-keycloak.sh [-v <version>] [-y]
cd "$(dirname "$0")" || exit 1
source ../../common.sh
export ANSIBLE_CONFIG=$PWD/raspberry/ansible.cfg
SOPS_CRYPT=$WINDFIRE_SECURITY_HOME/sops/sops-crypt.sh
# Default version: keycloak_version in raspberry/conf/raspberry-config.yml
DEFAULT_BACKUP_VERSION=$(sed -n 's/^keycloak_version: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' raspberry/conf/raspberry-config.yml)
# Must match local_backup_dir in raspberry/conf/keycloak-backup-config.yml
LOCAL_BACKUP_DIR=$HOME/opt/keycloak/backup
LAST_BACKUP_FILE=$LOCAL_BACKUP_DIR/.last-backup
BACKUP_VERSION=
ASSUME_YES=false

usage()
{
    echo "Usage: $(basename "$0") [-v <Keycloak version>] [-y] [-h]"
    echo "  -v  Keycloak version running on raspberry01 (default: ${DEFAULT_BACKUP_VERSION})"
    echo "  -y  Do not ask for confirmation"
}

while getopts ":v:yh" opt; do
    case "$opt" in
        v) BACKUP_VERSION="$OPTARG" ;;
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

if [[ -z "$BACKUP_VERSION" ]]; then
    read -r -p "Keycloak version [${DEFAULT_BACKUP_VERSION}]: " BACKUP_VERSION
    BACKUP_VERSION=${BACKUP_VERSION:-$DEFAULT_BACKUP_VERSION}
fi
if [[ ! "$BACKUP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid Keycloak version: $BACKUP_VERSION (expected e.g. 26.8.1)${RESET}" >&2
    exit 1
fi

if [[ "$ASSUME_YES" != true ]]; then
    echo -e "${YELLOW}Keycloak on raspberry01 is stopped during the export (about 1-2 minutes) and started again afterwards${RESET}"
    read -r -p "Back up Keycloak ${BACKUP_VERSION} now? [y/N]: " CONFIRMATION
    if [[ ! "$CONFIRMATION" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}Not confirmed, nothing done${RESET}"
        exit 1
    fi
fi

# The playbook writes the Mac copy path here only once the copy is verified
rm -f "$LAST_BACKUP_FILE"
echo -e "${BLU}Backing up Keycloak ${BACKUP_VERSION} from raspberry01 (inventory group identitymanager) to ${LOCAL_BACKUP_DIR} ...${RESET}"
if ! ansible-playbook -K raspberry/keycloak-backup.yaml -e keycloak_version="$BACKUP_VERSION" -e local_backup_dir="$LOCAL_BACKUP_DIR"; then
    echo -e "${RED}Backup failed, see the playbook output above${RESET}" >&2
    exit 1
fi

BACKUP_ARCHIVE=$(cat "$LAST_BACKUP_FILE" 2>/dev/null)
rm -f "$LAST_BACKUP_FILE"
if [[ -z "$BACKUP_ARCHIVE" || ! -f "$BACKUP_ARCHIVE" ]]; then
    echo -e "${RED}Backup archive not found on this Mac (${LAST_BACKUP_FILE} missing or stale)${RESET}" >&2
    exit 1
fi

# Binary mode, round trip check, plain archive deleted only if the check passes
echo -e "${BLU}Encrypting ${BACKUP_ARCHIVE} with sops ...${RESET}"
if ! "$SOPS_CRYPT" -e -f "$BACKUP_ARCHIVE" -r -y || [[ -f "$BACKUP_ARCHIVE" ]]; then
    echo -e "${RED}Encryption failed or not verified: ${BACKUP_ARCHIVE} is still in plain text (mode 0600), encrypt it with${RESET}" >&2
    echo "    $SOPS_CRYPT -e -f \"$BACKUP_ARCHIVE\" -r" >&2
    exit 1
fi

echo
echo -e "${GREEN}Keycloak ${BACKUP_VERSION} backup: ${BACKUP_ARCHIVE}${SOPS_ENCRYPTED_SUFFIX}${RESET}"
echo "To decrypt it:"
echo "    $SOPS_CRYPT -d -f \"${BACKUP_ARCHIVE}${SOPS_ENCRYPTED_SUFFIX}\""
